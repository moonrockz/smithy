///|
/// A session state named by `jsonRpcSession`. It follows the PeerName rule.
priv struct StateName {
  text : String
} derive(Eq)

///|
fn StateName::parse(text : String) -> StateName? {
  if is_protocol_name(text) {
    Some({ text, })
  } else {
    None
  }
}

///|
/// A capability that the successful result of a named call advertises.
priv struct CapabilitySource {
  name : String
  method_ : MethodName
  /// Into the result. The capability is advertised unless the value is
  /// absent, null or false.
  pointer : JsonPointer
}

///|
/// How a method cancels a call: where its params hold the call ID, and the
/// error code that the cancelled call may answer with.
priv struct CancelRule {
  /// The wire name of the ID member in named params.
  wire_name : String
  /// The position of the ID member in positional params.
  position : Int32?
  code : ErrorCode?
}

///|
/// The order rules of one method, from `jsonRpcLifecycle` and `jsonRpcCancels`.
priv struct MethodRule {
  /// None means every state.
  allowed : Array[StateName]?
  on_call : StateName?
  on_success : StateName?
  on_error : StateName?
  requires : Array[String]
  cancels : CancelRule?
}

///|
/// The prepared `jsonRpcSession` of a protocol.
priv struct SessionRules {
  /// The first state is the initial state.
  states : Array[StateName]
  sources : Array[CapabilitySource]
  /// The rules of the methods each peer accepts, by receiving peer.
  methods : Map[PeerName, Map[MethodName, MethodRule]]
}

///|
fn SessionRules::rule(
  self : SessionRules,
  receiver : PeerName,
  method_ : MethodName,
) -> MethodRule? {
  self.methods.get(receiver).bind(rules => rules.get(method_))
}

///|
/// The session state of one transcript, shared by both peers. The cancelled
/// calls are kept per sender, beside its active calls.
priv struct SessionState {
  rules : SessionRules
  mut state : StateName
  /// The entry that caused the last transition.
  mut transition : Int32?
  advertised : Set[String]
}

///|
fn SessionState::new(rules : SessionRules) -> SessionState {
  { rules, state: rules.states[0], transition: None, advertised: Set([]), }
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
/// that its reply can settle the session, and None when it is rejected or
/// there is no session.
fn TranscriptChecker::order_request(
  self : TranscriptChecker,
  step : Step,
  receiver : PeerName,
  value : Json,
) -> MethodName? {
  guard self.session is Some(session) && request_method(value) is Some(method_) else {
    return None
  }
  guard session.rules.rule(receiver, method_) is Some(rule) else {
    return Some(method_)
  }
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
  for capability in rule.requires {
    if !session.advertised.contains(capability) {
      accepted = false
      let source = session.rules.sources
        .iter()
        .find_first(s => s.name == capability)
        .map(s => s.method_.to_string())
        .unwrap_or("")
      self.report(
        step,
        CapabilityNotAdvertised,
        [],
        "I expected capability \{capability} to be advertised before method \{method_.to_string()}; entry \{step.index} from \{sender} sent it, and no \{source} result advertised it.",
      )
    }
  }
  if !accepted {
    return None
  }
  if rule.on_call is Some(next) {
    session.state = next
    session.transition = Some(step.index)
  }
  if rule.cancels is Some(cancels) {
    self.cancel(step, method_, cancels, value)
  }
  Some(method_)
}

///|
/// Marks the call that a cancellation names. The canceller cancels its own
/// call; a call that is not active gives an advisory, because a cancellation
/// may race the reply.
fn TranscriptChecker::cancel(
  self : TranscriptChecker,
  step : Step,
  method_ : MethodName,
  rule : CancelRule,
  value : Json,
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
  // A call inside a pending batch is active, but its batch reply is checked
  // as usual.
  if state.batch_with(key) is Some(_) {
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
/// code is the declared code of a cancelled call.
fn excuse_cancelled(
  findings : Array[Finding],
  value : Json,
  excused : ErrorCode?,
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
    !(f.code == UnknownError && f.path.pointer() == "/error/code")
  })
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
