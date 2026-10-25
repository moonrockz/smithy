///|
/// A service contract and the shapes that its operations reach.
pub struct ServiceDescription {
  service : @smithy.ShapeId
  methods : Array[@rpc.MethodContract]
  shapes : Array[@smithy.ShapeId]
  values : Array[@validation.StructureContract]
  value_config : @validation.Config
} derive(Eq, Debug)

///|
/// The service that a peer receives. None means that the peer receives no calls.
pub struct PeerDescription {
  name : @rpc.PeerName
  accepts : ServiceDescription?
} derive(Eq, Debug)

///|
/// A language-neutral JSON-RPC contract. Each constructor uses RPC preparation.
pub struct Description {
  protocol : @smithy.ShapeId?
  version : @rpc.ProtocolVersion
  peers : Array[PeerDescription]
  session : @rpc.SessionContract?
} derive(Eq, Debug)

///|
/// Prepare a service with the implicit client and server peers.
pub fn Description::for_service(
  model : @smithy.Model,
  service : @smithy.ShapeId,
  version : @rpc.ProtocolVersion,
  config~ : @validation.Config = @validation.Config::new(
    unknown_members=@validation.Ignore,
  ),
) -> Description raise {
  let prepared = @rpc.PreparedService::prepare(model, service, version, config~)
  {
    protocol: None,
    session: None,
    version,
    peers: [
      { name: @rpc.PeerName::parse("client").unwrap(), accepts: None, },
      {
        name: @rpc.PeerName::parse("server").unwrap(),
        accepts: Some({
          service,
          methods: prepared.contracts(),
          values: prepared.value_contracts(),
          value_config: prepared.value_config(),
          shapes: @codegen.service_closure(model, service),
        }),
      },
    ],
  }
}

///|
/// Both directions for one peer: the service it accepts and the service it calls.
pub struct PeerSelection {
  name : @rpc.PeerName
  accepts : ServiceDescription?
  calls : ServiceDescription?
} derive(Eq, Debug)

///|
/// Prepare an explicit two-peer protocol with its session rules.
pub fn Description::for_protocol(
  model : @smithy.Model,
  protocol : @smithy.ShapeId,
  version : @rpc.ProtocolVersion,
  config~ : @validation.Config = @validation.Config::new(
    unknown_members=@validation.Ignore,
  ),
) -> Description raise {
  let prepared = @rpc.ProtocolDescription::from_smithy(
    model,
    protocol,
    version,
    config~,
  )
  let peers = prepared
    .peers()
    .map(name => {
      name,
      accepts: prepared
      .service_for(name)
      .map(service => {
        service: service.service_id(),
        methods: service.contracts(),
        values: service.value_contracts(),
        value_config: service.value_config(),
        shapes: @codegen.service_closure(model, service.service_id()),
      }),
    })
  peers.sort_by((a, b) => a.name.to_string().lexical_compare(b.name.to_string()))
  {
    protocol: Some(protocol),
    version,
    peers,
    session: prepared.session_contract(),
  }
}

///|
/// Select the two directions of a known peer.
pub fn Description::peer(
  self : Description,
  name : @rpc.PeerName,
) -> PeerSelection? {
  guard self.peers.iter().find_first(peer => peer.name == name) is Some(peer) else {
    return None
  }
  Some({
    name,
    accepts: peer.accepts,
    calls: self.peers
    .iter()
    .find_first(other => other.name != name)
    .bind(other => other.accepts),
  })
}
