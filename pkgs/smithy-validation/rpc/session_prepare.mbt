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
  /// The capabilities that must be advertised first.
  requires : Array[CapabilitySource]
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
/// Prepares the order rules of a protocol with `jsonRpcSession`. The
/// lifecycle and cancellation traits of the operations apply only then.
fn prepare_session(
  model : @smithy.Model,
  protocol : @smithy.ShapeId,
  shape : @smithy.Shape,
  entries : Array[PeerEntry],
  config : @validation.Config,
) -> SessionRules? raise PreparationError {
  guard shape.trait_value("smithy.rpc#jsonRpcSession") is Some(trait_value) else {
    return None
  }
  let session = fields(Some(trait_value))
  guard session.get("states") is Some(Array(raw_states)) &&
    !raw_states.is_empty() else {
    raise InvalidContract(protocol, "I expected jsonRpcSession states.")
  }
  let states : Array[StateName] = []
  for raw in raw_states {
    guard raw is String(name) && StateName::parse(name) is Some(state) else {
      raise InvalidContract(
        protocol, "I expected valid jsonRpcSession state names.",
      )
    }
    if states.contains(state) {
      raise InvalidContract(
        protocol,
        "I expected distinct state names; I found \{name} twice.",
      )
    }
    states.push(state)
  }
  let sources : Array[CapabilitySource] = []
  let raw_sources = match session.get("capabilities") {
    None => []
    Some(Array(values)) => values
    Some(_) =>
      raise InvalidContract(protocol, "I expected a capability source list.")
  }
  for raw in raw_sources {
    let source = fields(Some(raw))
    guard text(source.get("name")) is Some(name) && name != "" else {
      raise InvalidContract(protocol, "I expected a nonempty capability name.")
    }
    if sources.iter().any(s => s.name == name) {
      raise InvalidContract(
        protocol,
        "I expected distinct capability names; I found \{name} twice.",
      )
    }
    let method_name = text(source.get("method")).unwrap_or("")
    guard MethodName::parse(method_name) is Some(method_) &&
      entries
      .iter()
      .any(e => e.service is Some(s) && s.methods.contains(method_)) else {
      raise InvalidContract(
        protocol,
        "I expected capability \{name} to come from a method that a peer accepts; I found method \{method_name}.",
      )
    }
    let pointer_text = text(source.get("pointer")).unwrap_or("")
    let pointer = JsonPointer::parse(pointer_text) catch {
      _ =>
        raise InvalidContract(
          protocol,
          "I expected capability \{name} to have a JSON Pointer into the result; I found \{pointer_text}.",
        )
    }
    sources.push({ name, method_, pointer, })
  }
  let methods : Map[PeerName, Map[MethodName, MethodRule]] = Map([])
  for entry in entries {
    guard entry.service is Some(service) else { continue }
    let rules : Map[MethodName, MethodRule] = Map([])
    for name, prepared in service.methods {
      if prepare_method_rule(model, prepared, states, sources, config)
        is Some(rule) {
        rules[name] = rule
      }
    }
    methods[entry.name] = rules
  }
  Some({ states, sources, methods, })
}

///|
/// The order rules of one operation, or None when it has neither
/// `jsonRpcLifecycle` nor `jsonRpcCancels`.
fn prepare_method_rule(
  model : @smithy.Model,
  method_ : PreparedMethod,
  states : Array[StateName],
  sources : Array[CapabilitySource],
  config : @validation.Config,
) -> MethodRule? raise PreparationError {
  let id = method_.operation
  guard model.shapes.get(id) is Some(operation) else {
    raise InvalidContract(id, "I expected an existing operation shape.")
  }
  let lifecycle = operation.trait_value("smithy.rpc#jsonRpcLifecycle")
  let cancels = operation.trait_value("smithy.rpc#jsonRpcCancels")
  if lifecycle is None && cancels is None {
    return None
  }
  let lifecycle = fields(lifecycle)
  fn state(
    field : String,
    raw : @smithy.NodeValue,
  ) -> StateName raise PreparationError {
    guard raw is String(name) &&
      StateName::parse(name) is Some(state) &&
      states.contains(state) else {
      raise InvalidContract(
        id,
        "I expected \{field} to name a jsonRpcSession state; I found \{@json.to_json(raw).stringify()}.",
      )
    }
    state
  }

  fn optional_state(field : String) -> StateName? raise PreparationError {
    match lifecycle.get(field) {
      None => None
      Some(raw) => Some(state(field, raw))
    }
  }

  let allowed = match lifecycle.get("allowedIn") {
    None => None
    Some(Array(values)) if !values.is_empty() =>
      Some(values.map(raw => state("allowedIn", raw)))
    Some(_) =>
      raise InvalidContract(id, "I expected allowedIn to list session states.")
  }
  let requires = match lifecycle.get("requires") {
    None => []
    Some(Array(values)) =>
      values.map(raw => {
        guard raw is String(name) &&
          sources.iter().find_first(s => s.name == name) is Some(source) else {
          raise InvalidContract(
            id,
            "I expected requires to name a jsonRpcSession capability; I found \{@json.to_json(raw).stringify()}.",
          )
        }
        source
      })
    Some(_) =>
      raise InvalidContract(id, "I expected requires to list capabilities.")
  }
  let cancels = match cancels {
    None => None
    Some(value) =>
      Some(prepare_cancel_rule(model, method_, fields(Some(value)), config))
  }
  Some({
    allowed,
    on_call: optional_state("onCall"),
    on_success: optional_state("onSuccess"),
    on_error: optional_state("onError"),
    requires,
    cancels,
  })
}

///|
fn prepare_cancel_rule(
  model : @smithy.Model,
  method_ : PreparedMethod,
  cancels : Map[String, @smithy.NodeValue],
  config : @validation.Config,
) -> CancelRule raise PreparationError {
  let id = method_.operation
  let member_name = text(cancels.get("idMember")).unwrap_or("")
  guard method_.input.with_member(member_name) is Some(member_id) &&
    model.shapes.get(method_.input) is Some(input) &&
    input.body is Structure(members) &&
    members.contains(member_id) &&
    model.shapes.get(member_id) is Some(member_) else {
    raise InvalidContract(
      id,
      "I expected idMember to name an input member; I found \{member_name}.",
    )
  }
  let wire_name = if config.member_names == @validation.JsonName {
    text(member_.trait_value("smithy.api#jsonName")).unwrap_or(member_name)
  } else {
    member_name
  }
  let code = match cancels.get("code") {
    None => None
    Some(Number(number)) =>
      match ErrorCode::from_number(number) {
        Some(code) => Some(code)
        None =>
          raise InvalidContract(
            id, "I expected an integer jsonRpcCancels code.",
          )
      }
    Some(_) =>
      raise InvalidContract(id, "I expected an integer jsonRpcCancels code.")
  }
  { wire_name, position: method_.positional.search(member_id), code, }
}
