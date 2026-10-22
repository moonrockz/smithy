///|
pub struct PeerName {
  priv text : String
} derive(Eq, Hash, Debug)

///|
/// Accepts `^[A-Za-z][A-Za-z0-9_-]{0,63}$`.
pub fn PeerName::parse(text : String) -> PeerName? {
  if is_protocol_name(text) {
    Some({ text, })
  } else {
    None
  }
}

///|
/// True for `^[A-Za-z][A-Za-z0-9_-]{0,63}$`, the rule of peer and state names.
fn is_protocol_name(text : String) -> Bool {
  let n = text.length()
  if n == 0 || n > 64 {
    return false
  }
  for i in 0..<n {
    let c = text[i].to_int()
    let letter = (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
      (c >= 'A'.to_int() && c <= 'Z'.to_int())
    let other = (c >= '0'.to_int() && c <= '9'.to_int()) ||
      c == '_'.to_int() ||
      c == '-'.to_int()
    if !(letter || (i > 0 && other)) {
      return false
    }
  }
  true
}

///|
pub fn PeerName::to_string(self : PeerName) -> String {
  self.text
}

///|
priv struct PeerEntry {
  name : PeerName
  service : PreparedService?
}

///|
/// A two-peer JSON-RPC protocol: each peer names the service it accepts, or
/// accepts nothing.
pub struct ProtocolDescription {
  priv protocol : @smithy.ShapeId
  priv version : ProtocolVersion
  priv entries : Array[PeerEntry]
  /// The order rules of `jsonRpcSession`. None means no order checks.
  priv session : SessionRules?
}

///|
/// Snapshot a `jsonRpcProtocol` shape and prepare the service each peer accepts.
pub fn ProtocolDescription::from_smithy(
  model : @smithy.Model,
  protocol : @smithy.ShapeId,
  version : ProtocolVersion,
  config~ : @validation.Config = @validation.Config::new(),
) -> ProtocolDescription raise {
  guard model.shapes.get(protocol) is Some(shape) else {
    raise InvalidContract(protocol, "I expected an existing protocol shape.")
  }
  guard shape.trait_value("smithy.rpc#jsonRpcProtocol") is Some(_) else {
    raise InvalidContract(
      protocol, "I expected the shape to carry the jsonRpcProtocol trait.",
    )
  }
  let contract = fields(shape.trait_value("smithy.rpc#jsonRpcProtocol"))
  guard contract.get("versions") is Some(Array(versions)) else {
    raise InvalidContract(protocol, "I expected jsonRpcProtocol versions.")
  }
  let declared = versions.any(v => {
    v is String(name) && ProtocolVersion::parse(name) == Some(version)
  })
  if !declared {
    invalid(
      protocol,
      "I expected the selected version \{version.to_string()} to be declared by the protocol.",
    )
  }
  guard contract.get("peers") is Some(Array(peers)) && peers.length() == 2 else {
    raise InvalidContract(protocol, "I expected exactly two peers.")
  }
  let entries : Array[PeerEntry] = []
  for peer in peers {
    let peer_fields = fields(Some(peer))
    guard text(peer_fields.get("name")) is Some(raw) &&
      PeerName::parse(raw) is Some(name) else {
      raise InvalidContract(protocol, "I expected a valid peer name.")
    }
    if entries.iter().any(e => e.name == name) {
      invalid(
        protocol,
        "I expected distinct peer names; I found \{name.text} twice.",
      )
    }
    let service = match peer_fields.get("accepts") {
      None => None
      Some(String(raw_id)) => {
        guard @smithy.ShapeId::parse(raw_id) is Some(id) else {
          raise InvalidContract(
            protocol,
            "I expected a shape id for accepts; I found \{raw_id}.",
          )
        }
        guard model.shapes.get(id) is Some(target) && target.body is Service(..) else {
          raise InvalidContract(
            protocol,
            "I expected peer \{name.text} to accept an existing service; I found \{raw_id}.",
          )
        }
        let declares = fields(target.trait_value("smithy.rpc#jsonRpc"))
        guard declares.get("versions") is Some(Array(vs)) &&
          vs.any(v => {
            v is String(s) && ProtocolVersion::parse(s) == Some(version)
          }) else {
          raise InvalidContract(
            protocol,
            "I expected service \{raw_id} to declare version \{version.to_string()}.",
          )
        }
        Some(PreparedService::prepare(model, id, version, config~))
      }
      Some(_) =>
        raise InvalidContract(protocol, "I expected accepts to be a shape id.")
    }
    entries.push({ name, service, })
  }
  let session = prepare_session(model, protocol, shape, entries, config)
  { protocol, version, entries, session, }
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
      invalid(
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
      invalid(
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
        guard raw is String(name) && sources.iter().any(s => s.name == name) else {
          raise InvalidContract(
            id,
            "I expected requires to name a jsonRpcSession capability; I found \{@json.to_json(raw).stringify()}.",
          )
        }
        name
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

///|
pub fn ProtocolDescription::protocol(
  self : ProtocolDescription,
) -> @smithy.ShapeId {
  self.protocol
}

///|
pub fn ProtocolDescription::version(
  self : ProtocolDescription,
) -> ProtocolVersion {
  self.version
}

///|
/// Peers in declaration order.
pub fn ProtocolDescription::peers(
  self : ProtocolDescription,
) -> Array[PeerName] {
  self.entries.map(e => e.name)
}

///|
pub fn ProtocolDescription::other(
  self : ProtocolDescription,
  peer : PeerName,
) -> PeerName? {
  if !self.entries.iter().any(e => e.name == peer) {
    return None
  }
  self.entries.iter().find_first(e => e.name != peer).map(e => e.name)
}

///|
/// The service the receiving peer accepts. `None` means it accepts nothing.
pub fn ProtocolDescription::service_for(
  self : ProtocolDescription,
  receiver : PeerName,
) -> PreparedService? {
  match self.entries.iter().find_first(e => e.name == receiver) {
    Some(e) => e.service
    None => None
  }
}
