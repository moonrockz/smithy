///|
/// A correlation key. Scalar IDs use the batch normalization (no exponent
/// expansion, no floating point). Structured 1.0 IDs compare by NodeValue
/// structural equality.
priv enum CallKey {
  Scalar(BatchId)
  Structured(@smithy.NodeValue)
} derive(Eq)

///|
impl Hash for CallKey with fn hash_combine(self, hasher) {
  match self {
    Scalar(id) => {
      hasher.combine_int(0)
      hasher.combine(id)
    }
    // Structural equality has no matching hash; structured IDs share a bucket.
    Structured(_) => hasher.combine_int(1)
  }
}

///|
fn call_key(id : RequestId) -> CallKey? {
  match id {
    Absent => None
    Present(node) =>
      match batch_id(id) {
        Some(key) => Some(Scalar(key))
        None => Some(Structured(node))
      }
  }
}

///|
fn render_id(id : RequestId) -> String {
  match id {
    Absent => "no readable id"
    Present(node) => "id " + @json.to_json(node).stringify()
  }
}

///|
/// How the reply to a pending entry is checked.
priv enum PendingForm {
  /// Against the original message text.
  SingleMessage
  /// As the one null-ID invalid-request error that an empty request batch
  /// needs.
  InvalidWholeBatch
  /// Against the envelope only. A 1.0 unreadable entry or a 1.0 call with an
  /// invalid envelope or an incomplete check gives no original request to
  /// check against, and version 1.0 has no standard invalid-request error.
  EnvelopeOnlyReply
}

///|
/// A call, or an unreadable entry, that waits for a reply.
priv struct Pending {
  entry : Int32
  text : String
  location : SourceLocation?
  id : RequestId
  form : PendingForm
  /// The method of an accepted call when the protocol has a session; its
  /// reply settles the session.
  method_ : MethodName?
}

///|
priv struct Answer {
  key : CallKey
  reply : Int32
  seq : Int32
}

///|
/// What one peer has sent: its active calls, its unreadable entries, its
/// pending request batches, the IDs the other peer answered, and its 1.0
/// notifications.
priv struct PeerState {
  name : PeerName
  active : Map[CallKey, Pending]
  unreadable : @deque.Deque[Pending]
  /// In entry order, so the earliest batch comes first.
  batches : Array[PendingBatch]
  answered : Map[CallKey, Answer]
  answered_order : @deque.Deque[Answer]
  mut next_seq : Int32
  mut forgot : Bool
  notifications : @deque.Deque[Int32]
  /// Active calls that a cancellation named, with the error code they may
  /// answer with.
  cancelled : Map[CallKey, ErrorCode]
}

///|
priv enum RequestClass {
  Silent
  LegacyNotification
  Unreadable
  Call(CallKey, RequestId)
}

///|
priv struct Step {
  index : Int32
  entry : TranscriptEntry
  out : Array[TranscriptFinding]
}

///|
/// Checks a transcript one entry at a time. It does no I/O and never raises;
/// problems are findings. Feeding entries one by one or in groups gives the
/// same findings.
pub struct TranscriptChecker {
  priv protocol : ProtocolDescription
  priv completeness : Completeness
  priv correlation : Bool
  priv limits : TranscriptLimits
  priv legacy_errors : LegacyErrorMode
  priv peers : Array[PeerState]
  /// The session state, when the protocol has `jsonRpcSession` and
  /// correlation is on.
  priv session : SessionState?
  priv mut entries : Int32
  priv mut emitted : Int32
  priv mut stopped : Bool
  priv mut complete : Bool
  priv mut summary : TranscriptSummary?
}

///|
pub fn TranscriptChecker::new(
  protocol : ProtocolDescription,
  completeness~ : Completeness = Partial,
  correlation~ : Bool = true,
  limits~ : TranscriptLimits = TranscriptLimits::default(),
  legacy_errors~ : LegacyErrorMode = Opaque,
) -> TranscriptChecker {
  let peers = protocol
    .peers()
    .map(name => {
      name,
      active: Map([]),
      unreadable: @deque.Deque([]),
      batches: [],
      answered: Map([]),
      answered_order: @deque.Deque([]),
      next_seq: 0,
      forgot: false,
      notifications: @deque.Deque([]),
      cancelled: Map([]),
    })
  let session = if correlation {
    protocol.session.map(SessionState::new)
  } else {
    None
  }
  {
    protocol,
    completeness,
    correlation,
    limits,
    legacy_errors,
    peers,
    session,
    entries: 0,
    emitted: 0,
    stopped: false,
    complete: true,
    summary: None,
  }
}

///|
/// A ProtocolDescription has exactly two peers.
fn TranscriptChecker::state(
  self : TranscriptChecker,
  peer : PeerName,
) -> PeerState {
  if self.peers[0].name == peer {
    self.peers[0]
  } else {
    self.peers[1]
  }
}

///|
fn TranscriptChecker::add(
  self : TranscriptChecker,
  out : Array[TranscriptFinding],
  finding : TranscriptFinding,
) -> Unit {
  if self.stopped {
    return
  }
  self.emitted += 1
  if self.emitted < self.limits.findings {
    out.push(finding)
    return
  }
  self.stopped = true
  self.complete = false
  let at = match finding.entry {
    Some(entry) => " at entry \{entry}"
    None => ""
  }
  out.push({
    ..finding,
    code: FindingLimit,
    severity: @validation.Error,
    related: [],
    finding: None,
    message: "I reached the limit of \{self.limits.findings} transcript findings\{at}; I report no more findings.",
  })
}

///|
fn TranscriptChecker::report(
  self : TranscriptChecker,
  step : Step,
  code : TranscriptCode,
  related : Array[Int32],
  message : String,
  severity~ : @validation.FindingSeverity = @validation.Error,
) -> Unit {
  self.add(step.out, {
    code,
    severity,
    entry: Some(step.index),
    location: step.entry.location,
    sender: Some(step.entry.sender),
    related,
    finding: None,
    message,
  })
}

///|
fn TranscriptChecker::report_messages(
  self : TranscriptChecker,
  step : Step,
  findings : Array[Finding],
  related : Array[Int32],
) -> Unit {
  for finding in findings {
    self.add(step.out, {
      code: Message(finding.code),
      severity: finding.severity,
      entry: Some(step.index),
      location: step.entry.location,
      sender: Some(step.entry.sender),
      related,
      finding: Some(finding),
      message: finding.message,
    })
  }
}

///|
/// A message-level finding that no peer service can name, on the protocol shape.
fn TranscriptChecker::protocol_finding(
  self : TranscriptChecker,
  code : FindingCode,
  field : String?,
  message : String,
) -> Finding {
  let root = @validation.InstancePath::root()
  {
    code,
    severity: @validation.Error,
    path: field
    .map(name => root.field(name) catch { _ => root })
    .unwrap_or(root),
    shape: self.protocol.protocol(),
    operation: None,
    offset: None,
    message,
  }
}

///|
/// Findings and their related entries for each entry, in order.
pub fn TranscriptChecker::feed(
  self : TranscriptChecker,
  entry : TranscriptEntry,
) -> Array[TranscriptFinding] {
  let step = { index: self.entries, entry, out: [], }
  if self.summary is Some(_) {
    return step.out
  }
  self.entries += 1
  let sender = entry.sender
  guard self.protocol.other(sender) is Some(receiver) else {
    let names = self.protocol.peers().map(p => p.to_string()).join(" or ")
    self.report(
      step,
      UnknownPeer,
      [],
      "I expected a sender named by protocol \{self.protocol.protocol().to_string()} (\{names}); entry \{step.index} came from \{sender.to_string()}.",
    )
    return step.out
  }
  if entry.receiver is Some(named) && named != receiver {
    self.report(
      step,
      UnknownPeer,
      [],
      "I expected entry \{step.index} from \{sender.to_string()} to go to \{receiver.to_string()}, the other peer of protocol \{self.protocol.protocol().to_string()}; it names \{named.to_string()}.",
    )
    return step.out
  }
  let bytes = @validation.utf8_length(entry.message)
  if bytes > self.limits.entry_bytes {
    self.report(
      step,
      EntryLimit,
      [],
      "I expected at most \{self.limits.entry_bytes} UTF-8 bytes in a transcript entry; entry \{step.index} from \{sender.to_string()} has \{bytes} bytes.",
    )
    return step.out
  }
  let value = @validation.parse_json_value(entry.message) catch {
    error => {
      let findings = match self.protocol.service_for(receiver) {
        Some(service) => service.validate_request(entry.message).findings
        None => {
          let (code, offset, message) = match error {
            @validation.InvalidJson(at, message) => (InvalidJson, at, message)
            @validation.DuplicateJsonKey(at) =>
              (
                DuplicateJsonKey,
                at,
                "I expected unique JSON object member names.",
              )
            @validation.JsonInputLimit(at, message) =>
              (JsonInputLimit, at, message)
          }
          [
            {
              ..self.protocol_finding(code, None, message),
              offset: Some(offset),
            },
          ]
        }
      }
      self.report_messages(step, findings, [])
      if self.correlation {
        self.track_unreadable(step) |> ignore
      }
      return step.out
    }
  }
  match value {
    Array(_) if self.protocol.version() == V1_0 =>
      self.report_messages(
        step,
        [
          self.protocol_finding(
            UnsupportedMessage,
            None,
            "I expected one JSON-RPC 1.0 message, because version 1.0 has no batches; entry \{step.index} from \{sender.to_string()} is a JSON array.",
          ),
        ],
        [],
      )
    Array(values) if is_reply_batch(values) =>
      self.reply_batch(step, receiver, values)
    Array(values) => self.request_batch(step, receiver, values)
    Object(fields) if fields.contains("method") =>
      self.request(step, receiver, value)
    Object(_) => self.reply(step, receiver, value)
    _ => self.request(step, receiver, value)
  }
  step.out
}

///|
pub fn TranscriptChecker::feed_all(
  self : TranscriptChecker,
  entries : Array[TranscriptEntry],
) -> Array[TranscriptFinding] {
  let out = []
  for entry in entries {
    out.append(self.feed(entry))
  }
  out
}

///|
/// A request or notification from the step's sender to `receiver`.
fn TranscriptChecker::request(
  self : TranscriptChecker,
  step : Step,
  receiver : PeerName,
  value : Json,
) -> Unit {
  let version = self.protocol.version()
  let mut form = SingleMessage
  let class = match self.protocol.service_for(receiver) {
    Some(service) => {
      let result = service.validate_json(value)
      self.report_messages(step, result.findings, [])
      if version == V1_0 &&
        (!result.complete || invalid_request_envelope(version, value, result)) {
        form = EnvelopeOnlyReply
      }
      classify(version, value, result)
    }
    None => {
      let finding = match value {
        Object(fields) => {
          let method_ = match fields.get("method") {
            Some(String(name)) => name
            Some(other) => other.stringify()
            None => "nothing"
          }
          self.protocol_finding(
            UnknownMethod,
            Some("method"),
            "I expected no request for peer \{receiver.to_string()}, which accepts nothing; entry \{step.index} from \{step.entry.sender.to_string()} sent method \{method_}.",
          )
        }
        _ =>
          self.protocol_finding(
            InvalidEnvelope,
            None,
            "I expected a JSON-RPC object for peer \{receiver.to_string()}; entry \{step.index} from \{step.entry.sender.to_string()} sent \{value.stringify()}.",
          )
      }
      self.report_messages(step, [finding], [])
      classify_unchecked(version, value)
    }
  }
  if !self.correlation {
    return
  }
  // A call or an unreadable entry applies the order rules only when the
  // checker tracks it.
  match class {
    Silent => self.order_request(step, receiver, value) |> ignore
    LegacyNotification => {
      self.order_request(step, receiver, value) |> ignore
      let state = self.state(step.entry.sender)
      state.notifications.push_back(step.index)
      if state.notifications.length() > self.limits.answered_ids {
        state.notifications.pop_front() |> ignore
      }
    }
    Unreadable =>
      if self.track_unreadable(step) {
        self.order_request(step, receiver, value) |> ignore
      }
    Call(key, id) => self.track_call(step, receiver, value, key, id, form)
  }
}

///|
/// A call needs a usable ID. Without one, an entry is unreadable: the other
/// peer can answer it only with a null-ID protocol error.
fn classify(
  version : ProtocolVersion,
  value : Json,
  result : RequestResult,
) -> RequestClass {
  let usable = result.id is Present(_) &&
    !result.findings.iter().any(f => f.code == InvalidId)
  if !usable {
    if result.kind == Some(Notification) &&
      !invalid_request_envelope(version, value, result) {
      Silent
    } else {
      Unreadable
    }
  } else if version == V1_0 && result.id == Present(@smithy.Null) {
    LegacyNotification
  } else {
    match call_key(result.id) {
      Some(key) => Call(key, result.id)
      None => Unreadable
    }
  }
}

///|
/// Classifies a request for a peer with no service, from the id member only.
fn classify_unchecked(version : ProtocolVersion, value : Json) -> RequestClass {
  guard value is Object(fields) else { return Unreadable }
  guard fields.get("id") is Some(raw) else {
    return if version == V2_0 { Silent } else { Unreadable }
  }
  let node = @smithy.NodeValue::from_json(raw) catch { _ => return Unreadable }
  let id = Present(node)
  if version == V1_0 && node is @smithy.Null {
    LegacyNotification
  } else if version == V2_0 && batch_id(id) is None {
    Unreadable
  } else {
    match call_key(id) {
      Some(key) => Call(key, id)
      None => Unreadable
    }
  }
}

///|
/// Tracks a call from the step's sender to `receiver`. Only a tracked call is
/// checked against the session, so a refused call causes no transition and no
/// cancellation.
fn TranscriptChecker::track_call(
  self : TranscriptChecker,
  step : Step,
  receiver : PeerName,
  value : Json,
  key : CallKey,
  id : RequestId,
  form : PendingForm,
) -> Unit {
  let sender = step.entry.sender
  let state = self.state(sender)
  match state.active.get(key) {
    Some(earlier) =>
      self.report(
        step,
        ActiveIdReused,
        [earlier.entry],
        "I expected a fresh call id from \{sender.to_string()}; entry \{step.index} reused \{render_id(id)}, which is still active from entry \{earlier.entry}.",
      )
    None =>
      if state.active.length() >= self.limits.active_calls {
        self.complete = false
        self.report(
          step,
          ActiveCallLimit,
          [],
          "I expected at most \{self.limits.active_calls} active calls from \{sender.to_string()}; I do not track the call at entry \{step.index} with \{render_id(id)}.",
        )
      } else {
        let method_ = self.order_request(step, receiver, value, call=true)
        state.active[key] = {
          entry: step.index,
          text: step.entry.message,
          location: step.entry.location,
          id,
          form,
          method_,
        }
      }
  }
}

///|
/// Tracks an unreadable entry, which only a null-ID error can answer. It
/// gives false when the entry is refused at the limit: then the entry, like
/// a refused call, applies no order rule.
fn TranscriptChecker::track_unreadable(
  self : TranscriptChecker,
  step : Step,
  form~ : PendingForm = SingleMessage,
) -> Bool {
  let sender = step.entry.sender
  let state = self.state(sender)
  if state.unreadable.length() >= self.limits.active_calls {
    if self.protocol.version() == V1_0 {
      // A 1.0 unreadable entry needs no reply, so the oldest one is dropped.
      state.unreadable.pop_front() |> ignore
    } else {
      self.complete = false
      self.report(
        step,
        ActiveCallLimit,
        [],
        "I expected at most \{self.limits.active_calls} unanswered unreadable entries from \{sender.to_string()}; I do not track entry \{step.index}.",
      )
      return false
    }
  }
  let form = match (self.protocol.version(), form) {
    (V1_0, SingleMessage) => EnvelopeOnlyReply
    _ => form
  }
  state.unreadable.push_back({
    entry: step.index,
    text: step.entry.message,
    location: step.entry.location,
    id: Absent,
    form,
    method_: None,
  })
  true
}

///|
/// The service that checks replies from `responder`. When the responder
/// accepts nothing, the other peer's service checks the envelope only, and its
/// findings name the protocol shape.
fn TranscriptChecker::reply_service(
  self : TranscriptChecker,
  responder : PeerName,
) -> (PreparedService, Bool)? {
  match self.protocol.service_for(responder) {
    Some(service) => Some((service, false))
    None =>
      match
        self.protocol.other(responder).bind(p => self.protocol.service_for(p)) {
        Some(service) => Some((service, true))
        None => None
      }
  }
}

///|
/// The envelope findings of a reply, checked by `reply_service`. A borrowed
/// service is not the responder's, so its findings name the protocol shape.
fn TranscriptChecker::envelope_findings(
  self : TranscriptChecker,
  findings : Array[Finding],
  borrowed : Bool,
) -> Array[Finding] {
  if borrowed {
    findings.map(f => { ..f, shape: self.protocol.protocol(), operation: None, })
  } else {
    findings
  }
}

///|
fn read_id(value : Json) -> RequestId {
  guard value is Object(fields) && fields.get("id") is Some(raw) else {
    return Absent
  }
  Present(@smithy.NodeValue::from_json(raw)) catch {
    _ => Absent
  }
}

///|
/// A reply from the step's sender to calls made by `caller`.
fn TranscriptChecker::reply(
  self : TranscriptChecker,
  step : Step,
  caller_name : PeerName,
  value : Json,
) -> Unit {
  let responder_name = step.entry.sender
  let service = self.reply_service(responder_name)
  let (envelope, id) = match service {
    Some((service, borrowed)) => {
      let result = service.validate_response_json(
        value,
        context=Some(EnvelopeOnly),
        legacy_errors=self.legacy_errors,
      )
      (self.envelope_findings(result.findings, borrowed), result.id)
    }
    None => ([], read_id(value))
  }
  if !self.correlation {
    self.report_messages(step, envelope, [])
    return
  }
  let errors = envelope.filter(f => f.severity == @validation.Error)
  let caller = self.state(caller_name)
  let responder = self.state(responder_name)
  let key = call_key(id)
  let null_key = Scalar(NullId)
  if key == Some(null_key) {
    let explicit = caller.active.get(null_key)
    let linked = match (caller.unreadable.front(), explicit) {
      (None, None) => None
      (Some(unreadable), None) => {
        caller.unreadable.pop_front() |> ignore
        Some(unreadable)
      }
      (None, Some(call)) => {
        caller.active.remove(null_key)
        Some(call)
      }
      (Some(unreadable), Some(call)) => {
        let (first, second) = if unreadable.entry < call.entry {
          caller.unreadable.pop_front() |> ignore
          (unreadable, call)
        } else {
          caller.active.remove(null_key)
          (call, unreadable)
        }
        self.report(
          step,
          AmbiguousReplyId,
          [first.entry, second.entry],
          "I linked the null-id reply at entry \{step.index} from \{responder_name.to_string()} to entry \{first.entry}; entry \{second.entry} from \{caller_name.to_string()} also waits for a null-id reply.",
          severity=@validation.Advisory,
        )
        Some(first)
      }
    }
    if linked is Some(pending) {
      self.link(step, service, value, caller, pending, errors)
      return
    }
  } else if key is Some(key) && caller.active.get(key) is Some(call) {
    caller.active.remove(key)
    self.link(step, service, value, caller, call, errors)
    self.remember_answer(caller, key, step.index)
    return
  }
  if key is Some(key) && caller.batch_with(key) is Some(batch) {
    self.report(
      step,
      WrongReplyForm,
      [batch.entry],
      "I expected a reply batch from \{responder_name.to_string()} to the batch at entry \{batch.entry} from \{caller_name.to_string()}; entry \{step.index} sent a single reply with \{render_id(id)}.",
    )
    self.report_messages(step, errors, [])
    return
  }
  if key is Some(key) && key != null_key {
    if caller.answered.get(key) is Some(first) {
      self.report(
        step,
        DuplicateReply,
        [first.reply],
        "I expected one reply to each call from \{caller_name.to_string()}; entry \{step.index} answers \{render_id(id)} again, first answered at entry \{first.reply}.",
      )
      self.report_messages(step, errors, [])
      return
    }
    if responder.active.get(key) is Some(call) {
      self.report(
        step,
        WrongResponder,
        [call.entry],
        "I expected a reply from \{caller_name.to_string()} to a call sent by \{responder_name.to_string()}; entry \{step.index} sent \{render_id(id)} from \{responder_name.to_string()}.",
      )
      self.report_messages(step, errors, [])
      return
    }
  }
  let notification = if self.protocol.version() == V1_0 && key == Some(null_key) {
    caller.notifications.pop_front()
  } else {
    None
  }
  match notification {
    Some(notified) =>
      self.report(
        step,
        ResponseToNotification,
        [notified],
        "I expected no reply to the notification at entry \{notified} from \{caller_name.to_string()}; entry \{step.index} from \{responder_name.to_string()} sent a null-id reply.",
      )
    None => {
      let forgot = if caller.forgot {
        " I remember only the last \{self.limits.answered_ids} answered ids, so it may be a late duplicate."
      } else {
        ""
      }
      self.report(
        step,
        UnsolicitedResponse,
        [],
        "I expected a reply to an active call from \{caller_name.to_string()}; entry \{step.index} from \{responder_name.to_string()} sent \{render_id(id)}, which matches no call.\{forgot}",
      )
    }
  }
  self.report_messages(step, errors, [])
}

///|
/// Answers a call that the caller no longer holds as active: validates the
/// reply, then settles the session.
fn TranscriptChecker::link(
  self : TranscriptChecker,
  step : Step,
  service : (PreparedService, Bool)?,
  value : Json,
  caller : PeerState,
  call : Pending,
  envelope_errors : Array[Finding],
) -> Unit {
  let excused = caller.release_cancel(call)
  self.answer(step, service, value, call, envelope_errors, excused)
  self.settle(step, step.entry.sender, call.method_, value)
}

///|
/// Validates a linked reply against the call it answers. A borrowed service
/// and an EnvelopeOnlyReply call give the envelope errors only. The finding
/// about an `excused` error code of a cancelled call is dropped.
fn TranscriptChecker::answer(
  self : TranscriptChecker,
  step : Step,
  service : (PreparedService, Bool)?,
  value : Json,
  call : Pending,
  envelope_errors : Array[Finding],
  excused : ErrorCode?,
) -> Unit {
  let findings = match (service, call.form) {
    (Some((service, false)), SingleMessage) =>
      service.validate_response_json(
        value,
        context=Some(OriginalRequest(call.text)),
        legacy_errors=self.legacy_errors,
      ).findings
    (Some((service, false)), InvalidWholeBatch) =>
      service.validate_response_checked(
        value,
        InvalidBatch(error_code("-32600")),
        legacy_errors=self.legacy_errors,
      ).findings
    _ => envelope_errors
  }
  self.report_messages(step, excuse_cancelled(findings, value, excused), [
    call.entry,
  ])
}

///|
fn TranscriptChecker::remember_answer(
  self : TranscriptChecker,
  caller : PeerState,
  key : CallKey,
  reply : Int32,
) -> Unit {
  let answer = { key, reply, seq: caller.next_seq, }
  caller.next_seq += 1
  caller.answered[key] = answer
  caller.answered_order.push_back(answer)
  if caller.answered_order.length() > self.limits.answered_ids {
    if caller.answered_order.pop_front() is Some(oldest) &&
      caller.answered.get(oldest.key) is Some(current) &&
      current.seq == oldest.seq {
      caller.answered.remove(oldest.key)
      caller.forgot = true
    }
  }
}

///|
/// End-of-input findings and the summary. Idempotent: later feeds are ignored.
pub fn TranscriptChecker::finish(self : TranscriptChecker) -> TranscriptSummary {
  if self.summary is Some(summary) {
    return summary
  }
  let out = []
  let waiting : Array[(PeerName, Waiting)] = []
  if self.correlation {
    for state in self.peers {
      for _, call in state.active {
        waiting.push((state.name, WaitingCall(call)))
      }
      // A 1.0 unreadable entry needs no reply.
      if self.protocol.version() == V2_0 {
        for unreadable in state.unreadable {
          waiting.push((state.name, WaitingCall(unreadable)))
        }
      }
      for batch in state.batches {
        waiting.push((state.name, WaitingBatch(batch)))
      }
    }
  }
  waiting.sort_by((a, b) => a.1.entry().compare(b.1.entry()))
  for item in waiting {
    let (sender, pending) = item
    let receiver = self.protocol
      .other(sender)
      .map(p => p.to_string())
      .unwrap_or("")
    let (reply, what, related) = match pending {
      WaitingCall(call) =>
        (
          "reply",
          "from \{receiver} to entry \{call.entry} from \{sender.to_string()} with \{render_id(call.id)}",
          [],
        )
      WaitingBatch(batch) =>
        (
          "reply batch",
          "from \{receiver} to the batch at entry \{batch.entry} from \{sender.to_string()}",
          [batch.entry],
        )
    }
    let (code, severity, message) = match self.completeness {
      Complete =>
        (
          MissingReply,
          @validation.Error,
          "I expected a \{reply} \{what}; the complete transcript has none.",
        )
      Partial =>
        (
          OutstandingCall,
          @validation.Advisory,
          "I found no \{reply} yet \{what}; the transcript is partial.",
        )
    }
    self.add(out, {
      code,
      severity,
      entry: Some(pending.entry()),
      location: pending.location(),
      sender: Some(sender),
      related,
      finding: None,
      message,
    })
  }
  let summary = {
    findings: out,
    entries: self.entries,
    outstanding: waiting.length(),
    correlation: self.correlation,
    complete: self.complete,
  }
  self.summary = Some(summary)
  summary
}
