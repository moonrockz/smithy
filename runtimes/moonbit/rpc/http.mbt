// The HTTP transport, in the style of MCP Streamable HTTP:
//
// - The client POSTs each message to one endpoint (`/rpc`), with
//   `Accept: application/json, text/event-stream`.
// - The server gives a session ID in `Smithy-Session-Id` on the response to
//   the first POST, and on each later response. The client sends it on each
//   later POST. An unknown session ID gives 404.
// - A POSTed request gets 200 `text/event-stream`. Each event is
//   `event: message` and `data: <one JSON message>`. The notifications and
//   requests that the handler of that request sends come first, and its
//   response comes last; then the stream ends. The server first writes the
//   SSE comment `: open`, so that the headers go out at once.
// - A POSTed notification or response gets 202 with an empty body.
// - Text that is not one JSON object (invalid JSON, a batch) gets 200
//   `application/json` with one error, and the session does not see it.
//
// The client sends the next POST only after it has the response headers of
// the last POST. So the server receives the messages in the order of the
// client, and the client knows the session ID before its second POST.

///|
/// The name of the session header.
pub let session_header : String = "Smithy-Session-Id"

///|
/// Splits `http://host:port/path` into the base URL and the path.
fn split_url(
  url : String,
  scheme : String,
) -> (String, String) raise TransportError {
  guard url.has_prefix(scheme + "://") else {
    raise TransportError(
      "I expected a URL that starts with \{scheme}://, found '\{url}'.",
    )
  }
  let rest = url[scheme.length() + 3:].to_owned()
  match rest.find("/") {
    Some(i) if i > 0 =>
      (scheme + "://" + rest[:i].to_owned(), rest[i:].to_owned())
    None if rest != "" => (scheme + "://" + rest, "/")
    _ => raise TransportError("I expected a host in the URL, found '\{url}'.")
  }
}

///|
/// A connection to a JSON-RPC server over HTTP.
struct HttpClientConnection {
  url : String
  base : String
  path : String
  mut session : String?
  inbox : @aqueue.Queue[String]
  mut group : @async.TaskGroup[Unit]?
  /// Fails a pending call of the peer; see `Connection::watch`.
  mut lost : ((RequestId) -> Unit)?
  mut closed : Bool
}

///|
/// Connects to the JSON-RPC endpoint at `url`, such as
/// `http://127.0.0.1:8080/rpc`. It checks that the server accepts a TCP
/// connection. The first POST starts the session.
pub async fn http_connect(url : String) -> HttpClientConnection {
  let (base, path) = split_url(url, "http")
  let probe = @http.Client(base) catch {
    err => raise TransportError("I could not connect to \{url}: \{err}")
  }
  probe.close()
  {
    url,
    base,
    path,
    session: None,
    inbox: @aqueue.Queue(kind=Unbounded),
    group: None,
    lost: None,
    closed: false,
  }
}

///|
/// The session ID that the server gave, when it gave one.
pub fn HttpClientConnection::session_id(self : HttpClientConnection) -> String? {
  self.session
}

///|
/// Reads the events of an SSE stream, and gives the data of each event to
/// `deliver`.
async fn[R : @io.Reader] read_events(
  reader : R,
  deliver : async (String) -> Unit,
) -> Unit {
  let data : Array[String] = []
  while reader.read_until("\n") is Some(raw) {
    let line = if raw.has_suffix("\r") {
      raw[:raw.length() - 1].to_owned()
    } else {
      raw
    }
    if line == "" {
      if !data.is_empty() {
        deliver(data.join("\n"))
        data.clear()
      }
      continue
    }
    if line.has_prefix(":") {
      continue
    }
    let (field, value) = match line.find(":") {
      Some(i) => {
        let value = line[i + 1:].to_owned()
        (
          line[:i].to_owned(),
          if value.has_prefix(" ") {
            value[1:].to_owned()
          } else {
            value
          },
        )
      }
      None => (line, "")
    }
    if field == "data" {
      data.push(value)
    }
  }
  if !data.is_empty() {
    deliver(data.join("\n"))
  }
}

///|
pub impl Connection for HttpClientConnection with fn start(self, group) {
  self.group = Some(group)
}

///|
pub impl Connection for HttpClientConnection with fn receive(self) {
  let text = self.inbox.get() catch {
    @aqueue.QueueAlreadyClosed => return None
    err => raise err
  }
  Some(text)
}

///|
pub impl Connection for HttpClientConnection with fn send(self, text, related~) {
  ignore(related)
  if self.closed {
    raise TransportError(
      "I could not send the message: the HTTP connection is closed.",
    )
  }
  guard self.group is Some(group) else {
    raise TransportError(
      "I need Peer::run on the HTTP connection to read the replies, found no running peer.",
    )
  }
  // The ID of the request that this POST carries: its stream must end with
  // the response to it.
  let call = request_id_of(text)
  let body = @utf8.encode(text)
  let headers : @http.Headers = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream",
    "Content-Length": body.length().to_string(),
  }
  if self.session is Some(id) {
    headers[@http.CaseInsensitiveString(session_header)] = id
  }
  let client = @http.Client(self.base) catch {
    err => raise TransportError("I could not connect to \{self.url}: \{err}")
  }
  errdefer client.close()
  let response = client.post(self.path, body, extra_headers=headers)
  if self.session is None {
    self.session = response.headers.get(
      @http.CaseInsensitiveString(session_header),
    )
  }
  let content_type = response.headers
    .get(@http.CaseInsensitiveString("Content-Type"))
    .unwrap_or("")
  match response.code {
    202 => {
      client.skip_response_body()
      client.close()
    }
    200 if content_type.has_prefix("text/event-stream") =>
      group.spawn_bg(allow_failure=true, () => {
        defer client.close()
        let answered = Ref(false)
        let deliver = async fn(data : String) {
          if call is Some(id) && is_response_to(data, id) {
            answered.val = true
          }
          self.inbox.put(data)
        }
        read_events(client, deliver) catch {
          err => {
            if @async.is_being_cancelled() {
              return
            }
            diagnose("I lost the event stream from \{self.url}: \{err}")
          }
        }
        // A stream that ends before its response fails that call only.
        if !answered.val {
          self.lose(call)
        }
      })
    200 => {
      let reply = client.read_all().text()
      client.close()
      if reply.trim().to_owned() != "" {
        self.inbox.put(reply)
      }
      if !(call is Some(id) && is_response_to(reply, id)) {
        self.lose(call)
      }
    }
    404 => {
      client.close()
      raise TransportError(
        "I expected the server at \{self.url} to know the session \{self.session.unwrap_or("")}, found HTTP status 404.",
      )
    }
    code => {
      client.close()
      raise TransportError(
        "I expected HTTP status 200 or 202 for the POST to \{self.url}, found \{code}.",
      )
    }
  }
}

///|
pub impl Connection for HttpClientConnection with fn watch(self, lost) {
  self.lost = Some(lost)
}

///|
/// Fails the call `call` of the peer, when there is one.
fn HttpClientConnection::lose(
  self : HttpClientConnection,
  call : RequestId?,
) -> Unit {
  if call is Some(id) && self.lost is Some(lost) {
    lost(id)
  }
}

///|
/// The ID of a request, or None for any other message.
fn request_id_of(text : String) -> RequestId? {
  let value = parse_json(text) catch { _ => return None }
  guard value is Object(fields) && fields.get("method") is Some(_) else {
    return None
  }
  fields.get("id").bind(RequestId::from_json)
}

///|
pub impl Connection for HttpClientConnection with fn close(self) {
  self.closed = true
  self.inbox.close()
}

///|
/// One HTTP session on the server: the connection of its Peer.
struct HttpSession {
  id : String
  inbox : @aqueue.Queue[String]
  /// The open event streams, by the ID of the POSTed request.
  streams : Map[RequestId, @aqueue.Queue[String?]]
  /// The messages that came when no stream was open.
  backlog : Array[String]
  mut closed : Bool
}

///|
fn HttpSession::new(id : String) -> HttpSession {
  {
    id,
    inbox: @aqueue.Queue(kind=Unbounded),
    streams: Map([]),
    backlog: [],
    closed: false,
  }
}

///|
/// Opens the event stream of a POSTed request. The messages of the backlog
/// go on it first.
fn HttpSession::open_stream(
  self : HttpSession,
  id : RequestId,
) -> @aqueue.Queue[String?] {
  let events : @aqueue.Queue[String?] = @aqueue.Queue(kind=Unbounded)
  for text in self.backlog {
    let _ = events.try_put(Some(text)) catch { _ => false }
  }
  self.backlog.clear()
  self.streams[id] = events
  events
}

///|
fn HttpSession::latest_stream(self : HttpSession) -> RequestId? {
  let mut last = None
  for id, _ in self.streams {
    last = Some(id)
  }
  last
}

///|
/// Whether `text` is the response to the call `id`.
fn is_response_to(text : String, id : RequestId) -> Bool {
  let value = parse_json(text) catch { _ => return false }
  guard value is Object(fields) else { return false }
  fields.get("method") is None &&
  fields.get("id").bind(RequestId::from_json) == Some(id)
}

///|
pub impl Connection for HttpSession with fn receive(self) {
  let text = self.inbox.get() catch {
    @aqueue.QueueAlreadyClosed => return None
    err => raise err
  }
  Some(text)
}

///|
pub impl Connection for HttpSession with fn send(self, text, related~) {
  if self.closed {
    raise TransportError(
      "I could not send the message: the HTTP session \{self.id} is closed.",
    )
  }
  let target = match related {
    Some(id) if self.streams.contains(id) => Some(id)
    _ => self.latest_stream()
  }
  match target {
    Some(id) => {
      let events = self.streams[id]
      events.put(Some(text))
      if is_response_to(text, id) {
        events.put(None)
        self.streams.remove(id)
      }
    }
    None => self.backlog.push(text)
  }
}

///|
pub impl Connection for HttpSession with fn close(self) {
  self.closed = true
  self.inbox.close()
  for _, events in self.streams {
    let _ = events.try_put(None) catch { _ => false }
  }
  self.streams.clear()
}

///|
/// The kind of a POSTed body.
priv enum PostKind {
  /// A request: it gets an event stream.
  Call(RequestId)
  /// A notification or a response: it gets 202.
  Accepted
  /// Not one message: the HTTP layer answers with this error.
  Answer(Json)
}

///|
fn classify_post(text : String) -> PostKind {
  let value = parse_json(text) catch {
    DecodeError(message~, ..) =>
      return Answer(
        error_message(
          None,
          parse_error_code,
          "I could not parse the message as JSON: \{message}",
          None,
        ),
      )
  }
  guard value is Object(fields) else {
    let message = if value is Array(_) {
      "I do not accept a batch; I received a JSON array."
    } else {
      "I expected a valid JSON-RPC 2.0 request; I found \{json_kind(value)}."
    }
    return Answer(error_message(None, invalid_request_code, message, None))
  }
  let id = fields.get("id").bind(RequestId::from_json)
  if fields.get("method") is Some(_) {
    match id {
      Some(id) => Call(id)
      None => Accepted
    }
  } else if fields.get("result") is Some(_) || fields.get("error") is Some(_) {
    Accepted
  } else {
    match id {
      Some(id) => Call(id)
      None =>
        Answer(
          error_message(
            None,
            invalid_request_code,
            "I expected a valid JSON-RPC 2.0 request; I found an object without a method.",
            None,
          ),
        )
    }
  }
}
