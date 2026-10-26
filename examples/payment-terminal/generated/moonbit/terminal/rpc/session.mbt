// The session engine. The generator renders the rules from the prepared
// session contract. The semantics follow the transcript checker in
// pkgs/smithy-validation/rpc (transcript_order.mbt), so that a peer and the
// checker agree about each message:
//
// - One session state. Each peer applies every message that it sends or
//   receives, in the order of its transcript.
// - A request or notification is refused when its method is not allowed in
//   the current state, or when a required capability is not advertised. A
//   refused message causes no transition, and its reply settles nothing.
// - An accepted message applies `on_call`, then its cancellation.
// - The reply of an accepted call applies `on_error` or `on_success` of the
//   rule of the responding peer. A result advertises each capability of a
//   source of that method, unless the value at the pointer is absent, null or
//   false. A capability is never removed.

///|
/// A capability that the successful result of a method advertises.
pub struct CapabilitySource {
  name : String
  method_name : String
  /// A JSON Pointer into the result.
  pointer : String
} derive(Eq, Debug)

///|
pub fn CapabilitySource::new(
  name~ : String,
  method_name~ : String,
  pointer~ : String,
) -> CapabilitySource {
  { name, method_name, pointer, }
}

///|
/// How a method cancels a call: the params member (or the position) that
/// holds the ID of the call, and the error code of the cancelled call.
pub struct CancelRule {
  id_member : String
  position : Int32?
  code : Int32?
} derive(Eq, Debug)

///|
pub fn CancelRule::new(
  id_member~ : String,
  position~ : Int32?,
  code~ : Int32?,
) -> CancelRule {
  { id_member, position, code, }
}

///|
/// The order rules of one method that one peer receives.
pub struct MethodRule {
  receiver : String
  method_name : String
  /// None means every state.
  allowed : Array[String]?
  on_call : String?
  on_success : String?
  on_error : String?
  /// The capability names that must be advertised.
  requires : Array[String]
  cancels : CancelRule?
} derive(Eq, Debug)

///|
pub fn MethodRule::new(
  receiver~ : String,
  method_name~ : String,
  allowed~ : Array[String]?,
  on_call~ : String?,
  on_success~ : String?,
  on_error~ : String?,
  requires~ : Array[String],
  cancels~ : CancelRule?,
) -> MethodRule {
  {
    receiver,
    method_name,
    allowed,
    on_call,
    on_success,
    on_error,
    requires,
    cancels,
  }
}

///|
/// The session contract of a protocol. The first state is the initial state.
pub struct SessionRules {
  states : Array[String]
  capabilities : Array[CapabilitySource]
  priv methods : Map[String, Map[String, MethodRule]]
  priv refusals : Map[String, Int32]
  capability_refusal : Int32?
}

///|
pub fn SessionRules::new(
  states~ : Array[String],
  capabilities~ : Array[CapabilitySource],
  methods~ : Array[MethodRule],
  refusals~ : Array[(String, Int32)],
  capability_refusal~ : Int32?,
) -> SessionRules {
  let by_receiver : Map[String, Map[String, MethodRule]] = Map([])
  for rule in methods {
    match by_receiver.get(rule.receiver) {
      Some(rules) => rules[rule.method_name] = rule
      None => by_receiver[rule.receiver] = Map([(rule.method_name, rule)])
    }
  }
  let codes = Map([])
  for refusal in refusals {
    codes[refusal.0] = refusal.1
  }
  {
    states,
    capabilities,
    methods: by_receiver,
    refusals: codes,
    capability_refusal,
  }
}

///|
/// No session: every method is allowed in every state.
pub fn SessionRules::none() -> SessionRules {
  SessionRules::new(
    states=[],
    capabilities=[],
    methods=[],
    refusals=[],
    capability_refusal=None,
  )
}

///|
/// The rule of `method_name` when `receiver` receives it.
pub fn SessionRules::rule(
  self : SessionRules,
  receiver : String,
  method_name : String,
) -> MethodRule? {
  self.methods.get(receiver).bind(rules => rules.get(method_name))
}

///|
/// The code for a call refused in `state`. It is -32600 when the model gives
/// no code for that state.
pub fn SessionRules::state_refusal_code(
  self : SessionRules,
  state : String,
) -> Int32 {
  self.refusals.get(state).unwrap_or(invalid_request_code)
}

///|
/// The outcome of the session check of a request or a notification.
priv enum Admission {
  /// The method has no rule; it is accepted.
  Free
  Accepted(MethodRule)
  Refused(Int32, String)
}

///|
/// The session state that one peer keeps.
priv struct Session {
  rules : SessionRules
  mut state : String
  advertised : Set[String]
}

///|
fn Session::new(rules : SessionRules) -> Session {
  { rules, state: rules.states.get(0).unwrap_or(""), advertised: Set([]), }
}

///|
/// Checks a request or a notification that `receiver` receives, and does not
/// change the session.
fn Session::check(
  self : Session,
  receiver : String,
  method_name : String,
) -> Admission {
  guard self.rules.rule(receiver, method_name) is Some(rule) else {
    return Free
  }
  if rule.allowed is Some(allowed) && !allowed.contains(self.state) {
    return Refused(
      self.rules.state_refusal_code(self.state),
      "I refused \{method_name} in state \{self.state}.",
    )
  }
  for capability in rule.requires {
    if !self.advertised.contains(capability) {
      return Refused(
        self.rules.capability_refusal.unwrap_or(invalid_request_code),
        "I refused \{method_name} because \{capability} is not advertised.",
      )
    }
  }
  Accepted(rule)
}

///|
/// Applies the transition of an accepted message.
fn Session::accept(self : Session, admission : Admission) -> Unit {
  if admission is Accepted(rule) && rule.on_call is Some(next) {
    self.state = next
  }
}

///|
/// Applies the reply of an accepted call of `method_name` that `responder`
/// received. `result` is the result of a success reply.
fn Session::settle(
  self : Session,
  responder : String,
  method_name : String,
  failed : Bool,
  result : Json?,
) -> Unit {
  if !failed && result is None {
    return
  }
  if self.rules.rule(responder, method_name) is Some(rule) {
    let next = if failed { rule.on_error } else { rule.on_success }
    if next is Some(state) {
      self.state = state
    }
  }
  guard result is Some(result) else { return }
  for source in self.rules.capabilities {
    if source.method_name == method_name {
      match resolve_pointer(result, source.pointer) {
        None | Some(Null) | Some(False) => ()
        Some(_) => self.advertised.add(source.name)
      }
    }
  }
}
