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
