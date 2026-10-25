///|
/// A capability source checked by protocol preparation.
pub struct CapabilityContract {
  name : String
  method_name : MethodName
  pointer : JsonPointer
} derive(Eq, Debug)

///|
/// A prepared reference to an active call in named or positional parameters.
pub struct CallReferenceContract {
  wire_name : String
  position : Int32?
  code : ErrorCode?
} derive(Eq, Debug)

///|
/// The prepared lifecycle rules of a method, with its receiving peer.
pub struct MethodRuleContract {
  receiver : PeerName
  method_name : MethodName
  allowed : Array[StateName]?
  on_call : StateName?
  on_success : StateName?
  on_error : StateName?
  requires : Array[String]
  cancels : CallReferenceContract?
} derive(Eq, Debug)

///|
/// A detached session contract. State order keeps the initial state first.
pub struct SessionContract {
  states : Array[StateName]
  capabilities : Array[CapabilityContract]
  methods : Array[MethodRuleContract]
  refusals : Array[StateRefusalContract]
  capability_refusal : ErrorCode?
} derive(Eq, Debug)

///|
/// The error code of a request refused in one state.
pub struct StateRefusalContract {
  state : StateName
  code : ErrorCode
} derive(Eq, Debug)

///|
pub fn PreparedService::service_id(self : PreparedService) -> @smithy.ShapeId {
  self.service
}

///|
/// Copy the prepared session rules. Methods sort by receiver, then wire name.
pub fn ProtocolDescription::session_contract(
  self : ProtocolDescription,
) -> SessionContract? {
  guard self.session is Some(session) else { return None }
  let capabilities = session.sources.map(source => {
    name: source.name,
    method_name: source.method_,
    pointer: source.pointer,
  })
  capabilities.sort_by((a, b) => a.name.lexical_compare(b.name))
  let methods : Array[MethodRuleContract] = []
  for receiver, rules in session.methods {
    for method_name, rule in rules {
      let requires = rule.requires.map(source => source.name)
      requires.sort_by((a, b) => a.lexical_compare(b))
      methods.push({
        receiver,
        method_name,
        allowed: rule.allowed.map(states => states.copy()),
        on_call: rule.on_call,
        on_success: rule.on_success,
        on_error: rule.on_error,
        requires,
        cancels: rule.cancels.map(rule => {
          wire_name: rule.wire_name,
          position: rule.position,
          code: rule.code,
        }),
      })
    }
  }
  methods.sort_by((a, b) => {
    let peer_order = a.receiver
      .to_string()
      .lexical_compare(b.receiver.to_string())
    if peer_order != 0 {
      peer_order
    } else {
      a.method_name.to_string().lexical_compare(b.method_name.to_string())
    }
  })
  let refusals : Array[StateRefusalContract] = []
  for state, code in session.refusals {
    refusals.push({ state, code, })
  }
  refusals.sort_by((a, b) => {
    a.state.to_string().lexical_compare(b.state.to_string())
  })
  Some({
    states: session.states.copy(),
    capabilities,
    methods,
    refusals,
    capability_refusal: session.capability_refusal,
  })
}

///|
/// Collect the prepared structure policies for parameters, results and error data.
pub fn PreparedService::value_contracts(
  self : PreparedService,
) -> Array[@validation.StructureContract] {
  let found : Map[@smithy.ShapeId, @validation.StructureContract] = Map([])
  fn add(validator : @validation.PreparedValidator) -> Unit {
    for contract in validator.structure_contracts() {
      found[contract.shape] = contract
    }
  }
  for _, method_ in self.methods {
    add(method_.validator)
    if method_.result_validator is Some(validator) {
      add(validator)
    }
    for error in method_.errors {
      if error.data_validator is Some(validator) {
        add(validator)
      }
    }
  }
  let out = found.values().to_array()
  out.sort_by((a, b) => a.shape.to_string().lexical_compare(b.shape.to_string()))
  out
}

///|
/// The value config after the service unknown member policy applies.
pub fn PreparedService::value_config(
  self : PreparedService,
) -> @validation.Config {
  self.config
}
