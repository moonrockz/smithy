// The dispatcher. Its layers (an envelope reader, a table of handlers, a
// table of pending calls, and a read loop that runs each incoming call in its
// own task) follow moonbitlang/openseek jsonrpc (Apache-2.0). The session
// rules, the cancellation and the transcript log are new.

///|
/// The message kinds that a method accepts.
pub(all) enum MethodKind {
  RequestOnly
  NotificationOnly
  RequestOrNotification
} derive(Eq, Debug)

///|
priv enum Handler {
  OnRequest(MethodKind, async (Json?, CallContext) -> Json)
  OnNotification(MethodKind, async (Json?, CallContext) -> Unit)
}

///|
priv enum Reply {
  Success(Json)
  Failure(Int32, String, Json?)
  Lost(String)
}

///|
/// A call that this peer sent and that has no reply yet.
priv struct Pending {
  method_name : String
  /// False when the session refused the call; its reply then settles
  /// nothing.
  admitted : Bool
  slot : @aqueue.Queue[Reply]
}

///|
/// A call that this peer received and did not answer yet.
priv struct Incoming {
  method_name : String
  mut task : @async.Task[Unit]?
  mut cancelled : Bool
}

///|
priv struct CallReference {
  id_member : String
  position : Int32?
}

///|
priv struct PeerCore {
  self_name : String
  remote_name : String
  session : Session
  log : TranscriptLog?
  handlers : Map[String, Handler]
  references : Map[String, CallReference]
  mut conn : &Connection?
  mut started : Bool
  mut finished : Bool
  attached : @cond_var.Cond
  lock : @async.Mutex
  mut next_id : Int64
  pending : Map[RequestId, Pending]
  active : Map[RequestId, Incoming]
}

///|
/// One peer of a JSON-RPC session. It answers the calls of the remote peer
/// with its handlers, and it calls the remote peer.
///
/// A Peer that `CallContext::peer` gives belongs to one incoming call: the
/// messages that it sends are related to that call (see `Connection`).
struct Peer {
  core : PeerCore
  scope : RequestId?
}

///|
/// The incoming call that a handler answers.
struct CallContext {
  request_id : RequestId?
  name : String
  owner : Peer
}

///|
/// The ID of the call, or None for a notification.
pub fn CallContext::id(self : CallContext) -> RequestId? {
  self.request_id
}

///|
/// The ID of the call as JSON, or null for a notification. A progress
/// notification uses it to name the running call.
pub fn CallContext::id_json(self : CallContext) -> Json {
  match self.request_id {
    Some(id) => id.to_json()
    None => Json::null()
  }
}

///|
/// The method of the call.
pub fn CallContext::method_name(self : CallContext) -> String {
  self.name
}

///|
/// The peer that received the call. The messages that it sends while the
/// call runs are related to the call.
pub fn CallContext::peer(self : CallContext) -> Peer {
  { core: self.owner.core, scope: self.request_id, }
}

///|
pub fn Peer::new(
  self_name~ : String,
  remote_name~ : String,
  rules~ : SessionRules,
  log~ : TranscriptLog? = None,
) -> Peer {
  let core : PeerCore = {
    self_name,
    remote_name,
    session: Session::new(rules),
    log,
    handlers: Map([]),
    references: Map([]),
    conn: None,
    started: false,
    finished: false,
    attached: @cond_var.Cond(),
    lock: @async.Mutex(),
    next_id: 1L,
    pending: Map([]),
    active: Map([]),
  }
  { core, scope: None, }
}

///|
/// The name of this peer.
pub fn Peer::self_name(self : Peer) -> String {
  self.core.self_name
}

///|
/// The current session state.
pub fn Peer::state(self : Peer) -> String {
  self.core.session.state
}

///|
/// Whether a result advertised the capability.
pub fn Peer::advertised(self : Peer, capability : String) -> Bool {
  self.core.session.advertised.contains(capability)
}

///|
/// Registers the handler of a method that this peer accepts. The handler
/// gives the result; use `Json::null()` for a method without a result.
pub fn Peer::on_request(
  self : Peer,
  method_name : String,
  kind : MethodKind,
  handler : async (Json?, CallContext) -> Json,
) -> Unit {
  self.core.handlers[method_name] = OnRequest(kind, handler)
}

///|
/// Registers the handler of a notification that this peer accepts.
pub fn Peer::on_notification(
  self : Peer,
  method_name : String,
  kind : MethodKind,
  handler : async (Json?, CallContext) -> Unit,
) -> Unit {
  self.core.handlers[method_name] = OnNotification(kind, handler)
}

///|
/// Declares that a received notification of `method_name` names an active
/// call that this peer sent, in the params member `id_member` (or at
/// `position` for positional params). The peer drops such a notification
/// when no such call is pending, and writes a diagnostic to stderr.
pub fn Peer::call_reference(
  self : Peer,
  method_name : String,
  id_member~ : String,
  position~ : Int32?,
) -> Unit {
  self.core.references[method_name] = { id_member, position, }
}

///|
/// Serializes the diagnostics: stderr accepts one write at a time.
let stderr_lock : @async.Mutex = @async.Mutex()

///|
/// Writes a diagnostic line to stderr. A diagnostic never goes to stdout.
async fn diagnose(message : String) -> Unit {
  stderr_lock.acquire()
  defer stderr_lock.release()
  @stdio.stderr.write(message + "\n") catch {
    _ => ()
  }
}

///|
/// Runs `f` while the peer holds its lock, and protects it from
/// cancellation, so that a log line, its session change and its wire text
/// stay together and in order.
async fn[T] PeerCore::locked(self : PeerCore, f : async () -> T) -> T {
  self.lock.acquire()
  defer self.lock.release()
  let result : Result[T, Error] = @async.protect_from_cancel(() => {
    try f() catch {
      err => Err(err)
    } noraise {
      value => Ok(value)
    }
  })
  match result {
    Ok(value) => value
    Err(err) => raise err
  }
}

///|
/// Waits until `run` attaches a connection.
async fn PeerCore::connection(self : PeerCore) -> &Connection {
  while true {
    if self.conn is Some(conn) {
      return conn
    }
    if self.finished {
      raise TransportError(
        "I have no connection: the session with \{self.remote_name} ended.",
      )
    }
    self.attached.wait()
  }
  panic()
}

///|
/// The incoming call that a message sent outside a handler is related to:
/// the latest active call.
fn PeerCore::latest_call(self : PeerCore) -> RequestId? {
  let mut last = None
  for id, _ in self.active {
    last = Some(id)
  }
  last
}

///|
/// Writes a message to the log and to the wire. The caller holds the lock.
async fn PeerCore::send_locked(
  self : PeerCore,
  conn : &Connection,
  message : Json,
  related : RequestId?,
) -> Unit {
  let text = write_json(message)
  if self.log is Some(log) {
    log.record("send", text)
  }
  conn.send(text, related~)
}

///|
fn request_message(
  id : RequestId?,
  method_name : String,
  params : Json?,
) -> Json {
  let fields : Map[String, Json] = Map([("jsonrpc", Json::string("2.0"))])
  if id is Some(id) {
    fields["id"] = id.to_json()
  }
  fields["method"] = Json::string(method_name)
  if params is Some(params) {
    fields["params"] = params
  }
  Json::object(fields)
}

///|
fn result_message(id : RequestId, result : Json) -> Json {
  Json::object(
    Map([
      ("jsonrpc", Json::string("2.0")),
      ("id", id.to_json()),
      ("result", result),
    ]),
  )
}

///|
fn error_message(
  id : RequestId?,
  code : Int32,
  message : String,
  data : Json?,
) -> Json {
  let error : Map[String, Json] = Map([
    ("code", Json::number(code.to_double())),
    ("message", Json::string(message)),
  ])
  if data is Some(data) {
    error["data"] = data
  }
  Json::object(
    Map([
      ("jsonrpc", Json::string("2.0")),
      (
        "id",
        match id {
          Some(id) => id.to_json()
          None => Json::null()
        },
      ),
      ("error", Json::object(error)),
    ]),
  )
}

///|
/// Sends a request and waits for its result. With `checked` true, a call
/// that the session refuses raises the modeled RpcError, and nothing is sent.
/// An error response raises RpcError with its code, message and data.
pub async fn Peer::request(
  self : Peer,
  method_name : String,
  params : Json?,
  checked~ : Bool = true,
) -> Json {
  let core = self.core
  let conn = core.connection()
  let slot : @aqueue.Queue[Reply] = @aqueue.Queue(kind=Unbounded)
  let id = core.locked(() => {
    if core.finished {
      raise TransportError(
        "I have no connection: the session with \{core.remote_name} ended.",
      )
    }
    let admission = core.session.check(core.remote_name, method_name)
    if checked && admission is Refused(code, message) {
      raise RpcError(code~, message~, data=None)
    }
    core.session.accept(admission)
    let id = RequestId::Number(core.next_id.to_string())
    core.next_id += 1L
    core.pending[id] = {
      method_name,
      admitted: !(admission is Refused(_, _)),
      slot,
    }
    let related = match self.scope {
      Some(scope) => Some(scope)
      None => core.latest_call()
    }
    errdefer core.pending.remove(id)
    core.send_locked(
      conn,
      request_message(Some(id), method_name, params),
      related,
    )
    id
  })
  defer core.pending.remove(id)
  match slot.get() {
    Success(result) => result
    Failure(code, message, data) => raise RpcError(code~, message~, data~)
    Lost(message) => raise TransportError(message)
  }
}

///|
/// Sends a notification. With `checked` true, a notification that the session
/// refuses raises the modeled RpcError, and nothing is sent.
pub async fn Peer::notify(
  self : Peer,
  method_name : String,
  params : Json?,
  checked~ : Bool = true,
) -> Unit {
  let core = self.core
  let conn = core.connection()
  core.locked(() => {
    let admission = core.session.check(core.remote_name, method_name)
    if checked && admission is Refused(code, message) {
      raise RpcError(code~, message~, data=None)
    }
    core.session.accept(admission)
    let related = match self.scope {
      Some(scope) => Some(scope)
      None => core.latest_call()
    }
    core.send_locked(conn, request_message(None, method_name, params), related)
  })
}

///|
/// Reads and answers messages from `conn` until the remote peer closes it.
/// Each incoming call runs in its own task, so that a handler can call the
/// remote peer while its call runs. When `run` returns, the calls that still
/// run are cancelled, and the pending calls of this peer fail with a
/// TransportError.
pub async fn Peer::run(self : Peer, conn : &Connection) -> Unit {
  let core = self.core
  if core.started || core.finished {
    raise TransportError(
      "I expected one connection for the peer \{core.self_name}; run was called again.",
    )
  }
  core.started = true
  defer core.finish()
  @async.with_task_group(group => {
    // The transport gets the group before any message is sent on it.
    conn.start(group)
    core.conn = Some(conn)
    core.attached.broadcast()
    while conn.receive() is Some(text) {
      core.locked(() => core.receive_locked(group, conn, text))
    }
    group.return_immediately(())
  })
}

///|
/// Ends the session: no later call can be sent, and each pending call fails.
fn PeerCore::finish(self : PeerCore) -> Unit {
  self.finished = true
  self.conn = None
  self.attached.broadcast()
  for _, pending in self.pending {
    let _ = pending.slot.try_put(
      Lost("I lost the connection before the reply to \{pending.method_name}."),
    ) catch {
      _ => false
    }
  }
  for _, incoming in self.active {
    incoming.cancelled = true
  }
  if self.log is Some(log) {
    log.close()
  }
}

///|
/// The params member that names a call.
fn named_call(params : Json?, key : String, position : Int32?) -> RequestId? {
  let raw = match params {
    Some(Object(fields)) => fields.get(key)
    Some(Array(items)) => position.bind(i => items.get(i))
    _ => None
  }
  raw.bind(RequestId::from_json)
}

///|
/// Handles one received message. The caller holds the lock.
async fn[G] PeerCore::receive_locked(
  self : PeerCore,
  group : @async.TaskGroup[G],
  conn : &Connection,
  text : String,
) -> Unit {
  let parsed : Result[Json, Error] = try parse_json(text) catch {
    err => Err(err)
  } noraise {
    value => Ok(value)
  }
  if self.log is Some(log) {
    log.record("recv", text, valid=parsed is Ok(_))
  }
  let value = match parsed {
    Ok(value) => value
    Err(err) => {
      let detail = match err {
        DecodeError(message~, ..) => message
        other => "\{other}"
      }
      self.send_locked(
        conn,
        error_message(
          None,
          parse_error_code,
          "I could not parse the message as JSON: \{detail}",
          None,
        ),
        None,
      )
      return
    }
  }
  guard value is Object(fields) else {
    let message = if value is Array(_) {
      "I do not accept a batch; I received a JSON array."
    } else {
      "I expected a valid JSON-RPC 2.0 request; I found \{json_kind(value)}."
    }
    self.send_locked(
      conn,
      error_message(None, invalid_request_code, message, None),
      None,
    )
    return
  }
  if fields.get("method") is None &&
    (fields.get("result") is Some(_) || fields.get("error") is Some(_)) {
    self.receive_reply(fields)
    return
  }
  // A request or a notification.
  let raw_id = fields.get("id")
  let id = raw_id.bind(RequestId::from_json)
  let usable_id = if raw_id is Some(_) && id is None { None } else { id }
  let invalid = (detail : String) => {
    error_message(
      usable_id,
      invalid_request_code,
      "I expected a valid JSON-RPC 2.0 request; I found \{detail}.",
      None,
    )
  }
  guard fields.get("jsonrpc") is Some(String("2.0")) else {
    self.send_locked(
      conn,
      invalid("no jsonrpc member with the value 2.0"),
      usable_id,
    )
    return
  }
  guard fields.get("method") is Some(String(method_name)) else {
    self.send_locked(
      conn,
      invalid("a method member that is not a string"),
      usable_id,
    )
    return
  }
  if raw_id is Some(raw) && id is None {
    self.send_locked(
      conn,
      invalid("an id that is not a string or an integer: \{write_json(raw)}"),
      None,
    )
    return
  }
  let params = fields.get("params")
  match params {
    None | Some(Object(_)) | Some(Array(_)) => ()
    Some(other) => {
      self.send_locked(conn, invalid("params that are \{json_kind(other)}"), id)
      return
    }
  }
  let handler = self.handlers.get(method_name)
  let rule = self.session.rules.rule(self.self_name, method_name)
  // A method is modeled when it has a handler, or a cancel rule that the
  // runtime applies itself.
  let modeled = handler is Some(_) || (rule is Some(r) && r.cancels is Some(_))
  if !modeled {
    if id is Some(id) {
      self.send_locked(
        conn,
        error_message(
          Some(id),
          method_not_found_code,
          "I do not know method \{method_name}.",
          None,
        ),
        Some(id),
      )
    } else {
      diagnose(
        "I dropped the notification \{method_name}, which I do not know.",
      )
    }
    return
  }
  if id is None && self.references.get(method_name) is Some(reference) {
    let named = named_call(params, reference.id_member, reference.position)
    if !(named is Some(call) && self.pending.contains(call)) {
      diagnose(
        "I dropped the notification \{method_name}, because it names no call that is pending.",
      )
      return
    }
  }
  let admission = self.session.check(self.self_name, method_name)
  if admission is Refused(code, message) {
    match id {
      Some(id) =>
        self.send_locked(
          conn,
          error_message(Some(id), code, message, None),
          Some(id),
        )
      None => diagnose("I dropped the notification \{method_name}: \{message}")
    }
    return
  }
  self.session.accept(admission)
  if admission is Accepted(rule) && rule.cancels is Some(cancel) {
    self.cancel_locked(conn, params, cancel)
  }
  match (id, handler) {
    (Some(id), Some(OnNotification(NotificationOnly, _))) =>
      self.reply_locked(
        conn,
        id,
        method_name,
        Err(
          (
            invalid_request_code,
            "I expected a notification for method \{method_name}; I received a request.",
            None,
          ),
        ),
      )
    (Some(id), None) =>
      // A cancel method without a handler, sent as a request.
      self.reply_locked(conn, id, method_name, Ok(Json::null()))
    (Some(id), Some(handler)) =>
      self.start_call(group, conn, id, method_name, handler, params)
    (None, Some(OnRequest(RequestOnly, _))) =>
      diagnose(
        "I dropped the notification \{method_name}, because the method needs a request.",
      )
    (None, Some(OnRequest(_, f))) =>
      self.start_notification(group, method_name, async fn(ctx) {
        f(params, ctx) |> ignore
      })
    (None, Some(OnNotification(_, f))) =>
      self.start_notification(group, method_name, async fn(ctx) {
        f(params, ctx)
      })
    (None, None) => ()
  }
}

///|
/// Cancels the call that a cancel message names, and answers that call with
/// the modeled code. A call that is not active is not changed.
async fn PeerCore::cancel_locked(
  self : PeerCore,
  conn : &Connection,
  params : Json?,
  rule : CancelRule,
) -> Unit {
  guard named_call(params, rule.id_member, rule.position) is Some(id) &&
    self.active.get(id) is Some(incoming) &&
    !incoming.cancelled else {
    return
  }
  incoming.cancelled = true
  if incoming.task is Some(task) {
    task.cancel()
  }
  self.reply_locked(
    conn,
    id,
    incoming.method_name,
    Err(
      (
        rule.code.unwrap_or(request_cancelled_code),
        "I cancelled \{incoming.method_name}.",
        None,
      ),
    ),
  )
}

///|
/// Sends the reply of an accepted incoming call, and settles the session.
/// The caller holds the lock.
async fn PeerCore::reply_locked(
  self : PeerCore,
  conn : &Connection,
  id : RequestId,
  method_name : String,
  outcome : Result[Json, (Int32, String, Json?)],
) -> Unit {
  self.active.remove(id)
  let message = match outcome {
    Ok(result) => result_message(id, result)
    Err((code, text, data)) => error_message(Some(id), code, text, data)
  }
  match outcome {
    Ok(result) =>
      self.session.settle(self.self_name, method_name, false, Some(result))
    Err(_) => self.session.settle(self.self_name, method_name, true, None)
  }
  self.send_locked(conn, message, Some(id))
}

///|
/// Maps an error of a handler to the error of its reply.
fn handler_error(method_name : String, err : Error) -> (Int32, String, Json?) {
  match err {
    RpcError(code~, message~, data~) => (code, message, data)
    DecodeError(path~, message~) =>
      (
        invalid_params_code,
        "I could not decode \{method_name} params at \{path}: \{message}",
        None,
      )
    other =>
      (internal_error_code, "I could not handle \{method_name}: \{other}", None)
  }
}

///|
/// Runs the handler of an incoming call in its own task. The caller holds the
/// lock.
fn[G] PeerCore::start_call(
  self : PeerCore,
  group : @async.TaskGroup[G],
  conn : &Connection,
  id : RequestId,
  method_name : String,
  handler : Handler,
  params : Json?,
) -> Unit {
  let incoming : Incoming = { method_name, task: None, cancelled: false, }
  self.active[id] = incoming
  let ctx : CallContext = {
    request_id: Some(id),
    name: method_name,
    owner: { core: self, scope: Some(id), },
  }
  let task = group.spawn(allow_failure=true, () => {
    let outcome = try {
      match handler {
        OnRequest(_, f) => Ok(f(params, ctx))
        OnNotification(_, f) => {
          f(params, ctx)
          Ok(Json::null())
        }
      }
    } catch {
      err => Err(handler_error(method_name, err))
    }
    if incoming.cancelled || @async.is_being_cancelled() {
      return
    }
    self.locked(() => {
      // A cancel message may have answered the call while this task waited
      // for the lock.
      if incoming.cancelled || self.finished {
        return
      }
      self.reply_locked(conn, id, method_name, outcome)
    }) catch {
      err => diagnose("I could not send the reply to \{method_name}: \{err}")
    }
  })
  incoming.task = Some(task)
}

///|
/// Runs the handler of an incoming notification in its own task. An error
/// of the handler goes to stderr.
fn[G] PeerCore::start_notification(
  self : PeerCore,
  group : @async.TaskGroup[G],
  method_name : String,
  f : async (CallContext) -> Unit,
) -> Unit {
  let ctx : CallContext = {
    request_id: None,
    name: method_name,
    owner: { core: self, scope: None, },
  }
  group.spawn_bg(allow_failure=true, () => {
    f(ctx) catch {
      err =>
        if !@async.is_being_cancelled() {
          diagnose("I could not handle the notification \{method_name}: \{err}")
        }
    }
  })
}

///|
/// Gives a reply to the call that waits for it, and settles the session.
fn PeerCore::receive_reply(self : PeerCore, fields : Map[String, Json]) -> Unit {
  guard fields.get("id").bind(RequestId::from_json) is Some(id) &&
    self.pending.get(id) is Some(pending) else {
    // A reply without a pending call: an error about a message that the
    // remote peer could not read, or a late reply.
    return
  }
  self.pending.remove(id)
  let reply = match fields.get("error") {
    Some(Object(error)) => {
      let code = match error.get("code").bind(RequestId::from_json) {
        Some(Number(text)) =>
          @string.parse_int(text) catch {
            _ => internal_error_code
          }
        _ => internal_error_code
      }
      let message = match error.get("message") {
        Some(String(text)) => text
        _ => ""
      }
      Failure(code, message, error.get("data"))
    }
    Some(Null) | None => Success(fields.get("result").unwrap_or(Json::null()))
    Some(other) =>
      Failure(
        internal_error_code,
        "I expected an error object in the reply, found \{json_kind(other)}.",
        None,
      )
  }
  if pending.admitted {
    match reply {
      Success(result) =>
        self.session.settle(
          self.remote_name,
          pending.method_name,
          false,
          Some(result),
        )
      _ =>
        self.session.settle(self.remote_name, pending.method_name, true, None)
    }
  }
  let _ = pending.slot.try_put(reply) catch { _ => false }
}
