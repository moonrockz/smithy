///|
/// The session state of one transcript, shared by both peers. The cancelled
/// calls are kept per sender, beside its active calls.
priv struct SessionState {
  rules : SessionRules
  mut state : StateName
  /// The entry that caused the last transition.
  mut transition : Int32?
  advertised : Set[String]
  /// The entry of the last accepted call of each capability source, by
  /// capability name.
  source_calls : Map[String, Int32]
}

///|
fn SessionState::new(rules : SessionRules) -> SessionState {
  {
    rules,
    state: rules.states[0],
    transition: None,
    advertised: Set([]),
    source_calls: Map([]),
  }
}

///|
fn render_states(states : Array[StateName]) -> String {
  let names = states.map(s => s.text)
  match names.length() {
    1 => "state " + names[0]
    n =>
      "states " + names[0:n - 1].to_owned().join(", ") + " or " + names[n - 1]
  }
}

///|
/// The method of a request or notification object.
fn request_method(value : Json) -> MethodName? {
  guard value is Object(fields) && fields.get("method") is Some(String(name)) else {
    return None
  }
  MethodName::parse(name)
}

///|
/// Checks a request or notification from the step's sender to `receiver`
/// against the session. It gives the method when the message is accepted, so
/// that its reply can settle the session, and None when it is rejected, when
/// the receiver does not model the method, or when there is no session.
/// `batch` holds the reply keys of the request batch that the message is an
/// element of.
fn TranscriptChecker::order_request(
  self : TranscriptChecker,
  step : Step,
  receiver : PeerName,
  value : Json,
  batch~ : Set[CallKey]? = None,
) -> MethodName? {
  guard self.session is Some(session) && request_method(value) is Some(method_) else {
    return None
  }
  // A method that the receiver does not model is an UnknownMethod finding
  // already, so it applies no rule, no transition and no capability.
  guard self.protocol.service_for(receiver) is Some(service) &&
    service.methods.contains(method_) else {
    return None
  }
  if session.rules.rule(receiver, method_) is Some(rule) &&
    !self.apply_rule(step, session, method_, rule, value, batch) {
    return None
  }
  for source in session.rules.sources {
    if source.method_ == method_ {
      session.source_calls[source.name] = step.index
    }
  }
  Some(method_)
}

///|
/// Checks a message against the rule of its method, and applies the
/// transition and the cancellation of an accepted message. It gives false
/// when the message is rejected.
fn TranscriptChecker::apply_rule(
  self : TranscriptChecker,
  step : Step,
  session : SessionState,
  method_ : MethodName,
  rule : MethodRule,
  value : Json,
  batch : Set[CallKey]?,
) -> Bool {
  let sender = step.entry.sender.to_string()
  let mut accepted = true
  if rule.allowed is Some(allowed) && !allowed.contains(session.state) {
    accepted = false
    self.report(
      step,
      StateViolation,
      session.transition.map(entry => [entry]).unwrap_or([]),
      "I expected method \{method_.to_string()} only in \{render_states(allowed)}; entry \{step.index} from \{sender} sent it in state \{session.state.text}.",
    )
  }
  for source in rule.requires {
    if !session.advertised.contains(source.name) {
      accepted = false
      self.report(
        step,
        CapabilityNotAdvertised,
        session.source_calls.get(source.name).map(e => [e]).unwrap_or([]),
        "I expected capability \{source.name} to be advertised before method \{method_.to_string()}; entry \{step.index} from \{sender} sent it, and no \{source.method_.to_string()} result advertised it.",
      )
    }
  }
  if !accepted {
    return false
  }
  if rule.on_call is Some(next) {
    session.state = next
    session.transition = Some(step.index)
  }
  if rule.cancels is Some(cancels) {
    self.cancel(step, method_, cancels, value, batch)
  }
  true
}

///|
/// Marks the call that a cancellation names. The canceller cancels its own
/// call: an active call, or a call in an earlier pending request batch. A
/// call that is not active gives an advisory, because a cancellation may race
/// the reply. A null id names an active null-id call only, never a batch
/// call. `batch` holds the reply keys of the request batch that the
/// cancellation is an element of.
fn TranscriptChecker::cancel(
  self : TranscriptChecker,
  step : Step,
  method_ : MethodName,
  rule : CancelRule,
  value : Json,
  batch : Set[CallKey]?,
) -> Unit {
  guard value is Object(fields) else { return }
  let named = match fields.get("params") {
    Some(Object(params)) => params.get(rule.wire_name)
    Some(Array(params)) => rule.position.bind(i => params.get(i))
    _ => None
  }
  // The request validator reports a missing ID member.
  guard named is Some(raw) else { return }
  let id = Present(@smithy.NodeValue::from_json(raw)) catch { _ => return }
  guard call_key(id) is Some(key) else { return }
  // In a batch, the null key also answers each invalid element, so it does
  // not name one call. A null-id cancellation never names a batch call.
  let in_batch = key != Scalar(NullId)
  // The receiver may process the elements of a batch in any order, so a
  // cancellation of a call in the same batch proves nothing.
  if in_batch && batch is Some(keys) && keys.contains(key) {
    return
  }
  let sender = step.entry.sender
  let state = self.state(sender)
  if state.active.contains(key) {
    if rule.code is Some(code) {
      // A key is cancelled only while its call is active, so this table is
      // bounded by the active calls.
      state.cancelled[key] = code
    }
    return
  }
  if in_batch && state.batch_with(key) is Some(pending) {
    if rule.code is Some(code) {
      // A batch holds the cancellations of its own calls only, so its keys
      // bound them.
      pending.cancelled[key] = code
    }
    return
  }
  let (related, answered) = match state.answered.get(key) {
    Some(answer) => ([answer.reply], " Entry \{answer.reply} answered it.")
    None => ([], "")
  }
  self.report(
    step,
    CancelInactiveCall,
    related,
    "I expected \{method_.to_string()} at entry \{step.index} from \{sender.to_string()} to name an active call from \{sender.to_string()}; it names \{render_id(id)}, which is not active.\{answered}",
    severity=@validation.Advisory,
  )
}

///|
/// Removes the cancellation of an answered call, and gives the error code
/// that the call may answer with.
fn PeerState::release_cancel(self : PeerState, pending : Pending) -> ErrorCode? {
  guard !self.cancelled.is_empty() && call_key(pending.id) is Some(key) else {
    return None
  }
  let code = self.cancelled.get(key)
  self.cancelled.remove(key)
  code
}

///|
/// Drops the UnknownError finding about the error code of a reply when that
/// code is the declared code of a cancelled call. `at` is the pointer of the
/// reply inside a reply batch.
fn excuse_cancelled(
  findings : Array[Finding],
  value : Json,
  excused : ErrorCode?,
  at~ : String = "",
) -> Array[Finding] {
  guard excused is Some(code) &&
    value is Object(fields) &&
    fields.get("error") is Some(Object(error)) &&
    error.get("code") is Some(Number(n, repr~)) &&
    @smithy.NodeNumber::parse(repr.unwrap_or(n.to_string())).bind(
      ErrorCode::from_number,
    )
    is Some(found) &&
    found == code else {
    return findings
  }
  findings.filter(f => {
    !(f.code == UnknownError && f.path.pointer() == at + "/error/code")
  })
}

///|
/// Drops the UnknownError findings about the error codes of the elements of a
/// reply batch that answer cancelled calls of the batch. A cancellation
/// excuses the first element that answers its call, and no other element.
fn excuse_cancelled_batch(
  findings : Array[Finding],
  values : Array[Json],
  cancelled : Map[CallKey, ErrorCode],
) -> Array[Finding] {
  if cancelled.is_empty() {
    return findings
  }
  let used : Set[CallKey] = Set([])
  let mut kept = findings
  for index, element in values {
    guard batch_id(read_id(element)) is Some(id) &&
      !used.contains(Scalar(id)) &&
      cancelled.get(Scalar(id)) is Some(code) else {
      continue
    }
    used.add(Scalar(id))
    kept = excuse_cancelled(kept, element, Some(code), at="/\{index}")
  }
  kept
}

///|
/// Applies the outcome of a reply to an accepted call: the transition of its
/// method and the capabilities that its result advertises.
fn TranscriptChecker::settle(
  self : TranscriptChecker,
  step : Step,
  responder : PeerName,
  method_ : MethodName?,
  value : Json,
) -> Unit {
  guard self.session is Some(session) &&
    method_ is Some(method_) &&
    value is Object(fields) else {
    return
  }
  let failed = match fields.get("error") {
    None | Some(Null) => false
    Some(_) => true
  }
  let result = if failed { None } else { fields.get("result") }
  if !failed && result is None {
    return
  }
  let next = match session.rules.rule(responder, method_) {
    Some(rule) => if failed { rule.on_error } else { rule.on_success }
    None => None
  }
  if next is Some(next) {
    session.state = next
    session.transition = Some(step.index)
  }
  guard result is Some(result) else { return }
  for source in session.rules.sources {
    if source.method_ == method_ {
      match source.pointer.resolve(result) {
        None | Some(Null) | Some(False) => ()
        Some(_) => session.advertised.add(source.name)
      }
    }
  }
}
