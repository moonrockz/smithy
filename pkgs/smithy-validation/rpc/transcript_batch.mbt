///|
/// A 2.0 request batch that waits for one reply batch. `keys` are the IDs its
/// replies carry: one per call, and a null ID for each invalid element.
priv struct PendingBatch {
  entry : Int32
  text : String
  location : SourceLocation?
  keys : Set[CallKey]
  /// The methods of the accepted calls when the protocol has a session.
  methods : Map[CallKey, MethodName]
  /// The calls that a later cancellation named, with the error code they may
  /// answer with.
  cancelled : Map[CallKey, ErrorCode]
}

///|
/// One unit that still waits for a reply at the end of input.
priv enum Waiting {
  WaitingCall(Pending)
  WaitingBatch(PendingBatch)
}

///|
fn Waiting::entry(self : Waiting) -> Int32 {
  match self {
    WaitingCall(call) => call.entry
    WaitingBatch(batch) => batch.entry
  }
}

///|
fn Waiting::location(self : Waiting) -> SourceLocation? {
  match self {
    WaitingCall(call) => call.location
    WaitingBatch(batch) => batch.location
  }
}

///|
/// A 2.0 array is a reply batch when at least one element is an object with
/// `result` or `error` and no element has `method`.
fn is_reply_batch(values : Array[Json]) -> Bool {
  let mut replies = false
  for value in values {
    guard value is Object(fields) else { continue }
    if fields.contains("method") {
      return false
    }
    if fields.contains("result") || fields.contains("error") {
      replies = true
    }
  }
  replies
}

///|
/// The earliest pending batch whose replies include `key`.
fn PeerState::batch_with(self : PeerState, key : CallKey) -> PendingBatch? {
  self.batches.iter().find_first(batch => batch.keys.contains(key))
}

///|
/// The reply IDs of a checked request batch.
fn batch_keys(
  version : ProtocolVersion,
  values : Array[Json],
  checked : RequestBatchResult,
) -> Set[CallKey] {
  let keys = Set([])
  for entry in checked.entries {
    guard entry.index >= 0 && entry.index < values.length() else { continue }
    if batch_reply_id(version, values[entry.index], entry.result)
      is Some((id, _)) &&
      batch_id(id) is Some(key) {
      keys.add(Scalar(key))
    }
  }
  keys
}

///|
/// The reply IDs of a request batch that was not checked completely, from the
/// id members only. An element with no id and a string method is a
/// notification; any other element with no usable id is answered with a null ID.
fn unchecked_batch_keys(
  version : ProtocolVersion,
  values : Array[Json],
) -> Set[CallKey] {
  let keys = Set([])
  for value in values {
    if value is Object(fields) && !fields.contains("id") {
      if !(fields.get("method") is Some(String(_))) {
        keys.add(Scalar(NullId))
      }
      continue
    }
    match classify_unchecked(version, value) {
      Call(key, _) => keys.add(key)
      Unreadable => keys.add(Scalar(NullId))
      Silent | LegacyNotification => ()
    }
  }
  keys
}

///|
/// A 2.0 request batch from the step's sender to `receiver`.
fn TranscriptChecker::request_batch(
  self : TranscriptChecker,
  step : Step,
  receiver : PeerName,
  values : Array[Json],
) -> Unit {
  let version = self.protocol.version()
  let keys = match self.protocol.service_for(receiver) {
    Some(service) => {
      let checked = service.validate_request_batch(step.entry.message)
      self.report_messages(step, checked.findings, [])
      if !checked.complete {
        // A limit stopped the check, so the entries can be a prefix.
        self.complete = false
      }
      if values.is_empty() {
        None
      } else if !checked.complete || checked.entries.is_empty() {
        Some(unchecked_batch_keys(version, values))
      } else {
        Some(batch_keys(version, values, checked))
      }
    }
    None => {
      self.report_messages(
        step,
        [
          self.protocol_finding(
            UnknownMethod,
            None,
            "I expected no request batch for peer \{receiver.to_string()}, which accepts nothing; entry \{step.index} from \{step.entry.sender.to_string()} sent a batch of \{values.length()} elements.",
          ),
        ],
        [],
      )
      if values.is_empty() {
        None
      } else {
        Some(unchecked_batch_keys(version, values))
      }
    }
  }
  if !self.correlation {
    return
  }
  match keys {
    // An empty batch is answered by one null-ID error object.
    None => self.track_unreadable(step, form=InvalidWholeBatch)
    Some(keys) => self.track_batch(step, receiver, values, keys)
  }
}

///|
/// Tracks a request batch whose replies carry `keys`, and checks its elements
/// against the session in array order. A batch that the checker refuses
/// applies no order rule. An all-notification batch needs no reply.
fn TranscriptChecker::track_batch(
  self : TranscriptChecker,
  step : Step,
  receiver : PeerName,
  values : Array[Json],
  keys : Set[CallKey],
) -> Unit {
  let sender = step.entry.sender
  let state = self.state(sender)
  if !keys.is_empty() && state.batches.length() >= self.limits.active_calls {
    self.complete = false
    self.report(
      step,
      ActiveCallLimit,
      [],
      "I expected at most \{self.limits.active_calls} pending batches from \{sender.to_string()}; I do not track the batch at entry \{step.index}.",
    )
    return
  }
  let version = self.protocol.version()
  let methods : Map[CallKey, MethodName] = Map([])
  for element in values {
    let class = classify_unchecked(version, element)
    if self.order_request(
        step,
        receiver,
        element,
        batch=Some(keys),
        call=class is Call(_, _),
      )
      is Some(method_) &&
      class is Call(key, _) {
      methods[key] = method_
    }
  }
  if keys.is_empty() {
    return
  }
  state.batches.push({
    entry: step.index,
    text: step.entry.message,
    location: step.entry.location,
    keys,
    methods,
    cancelled: Map([]),
  })
}

///|
/// At most this many IDs are named in a finding about a reply batch.
const NAMED_REPLY_IDS : Int32 = 3

///|
fn render_ids(ids : Array[RequestId]) -> String {
  if ids.is_empty() {
    return "no readable id"
  }
  let named = ids
    .iter()
    .take(NAMED_REPLY_IDS)
    .map(render_id)
    .collect()
    .join(", ")
  if ids.length() > NAMED_REPLY_IDS {
    named + " and \{ids.length() - NAMED_REPLY_IDS} more"
  } else {
    named
  }
}

///|
/// A 2.0 reply batch from the step's sender to batches sent by `caller_name`.
fn TranscriptChecker::reply_batch(
  self : TranscriptChecker,
  step : Step,
  caller_name : PeerName,
  values : Array[Json],
) -> Unit {
  let responder_name = step.entry.sender
  let service = self.reply_service(responder_name)
  let (envelope, ids) = match service {
    Some((service, borrowed)) => {
      let result = service.validate_response_batch(
        Some(step.entry.message),
        context=Some(BatchEnvelopeOnly),
      )
      (
        self.envelope_findings(result.findings, borrowed),
        result.entries.map(e => e.result.id),
      )
    }
    None => ([], values.map(read_id))
  }
  if !self.correlation {
    self.report_messages(step, envelope, [])
    return
  }
  let errors = envelope.filter(f => f.severity == @validation.Error)
  let keys : Array[CallKey] = []
  let readable = []
  for id in ids {
    if batch_id(id) is Some(key) {
      keys.push(Scalar(key))
      readable.push(id)
    }
  }
  let caller = self.state(caller_name)
  let chosen = if keys.is_empty() {
    None
  } else {
    caller.batches.search_by(batch => {
      keys.iter().all(key => batch.keys.contains(key))
    })
  }
  guard chosen is Some(position) else {
    self.report(
      step,
      UnsolicitedResponse,
      [],
      "I expected a reply batch to a pending batch from \{caller_name.to_string()}; entry \{step.index} from \{responder_name.to_string()} sent \{render_ids(readable)}, which no batch contains.",
    )
    self.report_messages(step, errors, [])
    return
  }
  let batch = caller.batches.remove(position)
  match service {
    Some((service, false)) => {
      let result = service.validate_response_batch(
        Some(step.entry.message),
        context=Some(OriginalBatch(batch.text)),
      )
      self.report_messages(
        step,
        excuse_cancelled_batch(result.findings, values, batch.cancelled),
        [batch.entry],
      )
    }
    _ =>
      self.report_messages(
        step,
        excuse_cancelled_batch(errors, values, batch.cancelled),
        [batch.entry],
      )
  }
  if batch.methods.is_empty() {
    return
  }
  for element in values {
    if batch_id(read_id(element)) is Some(key) &&
      batch.methods.get(Scalar(key)) is Some(method_) {
      self.settle(step, responder_name, Some(method_), element)
    }
  }
}
