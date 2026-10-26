///|
/// A transport that a generated peer supports.
pub(all) enum Transport {
  Stdio
  Http
  WebSocket
} derive(Eq, Debug)

///|
/// The setting text of a transport.
pub fn Transport::to_string(self : Transport) -> String {
  match self {
    Stdio => "stdio"
    Http => "http"
    WebSocket => "websocket"
  }
}

///|
/// The settings that every JSON-RPC language plugin shares, after I checked
/// them against the model: the prepared description, the selected peer and
/// the transports.
pub struct PeerSettings {
  description : Description
  peer : PeerSelection
  transports : Array[Transport]
}

///|
fn peer_settings_error(error : Error) -> @codegen.CodegenError {
  match error {
    @rpc.InvalidContract(id, text) =>
      @codegen.InvalidSettings(
        "I could not prepare the JSON-RPC contract of `\{id}`: \{text}",
      )
    error =>
      @codegen.InvalidSettings(
        "I could not prepare the JSON-RPC contract: \{error.to_string()}",
      )
  }
}

///|
/// Read the shared settings of a JSON-RPC plugin. `service` is the service
/// shape of the plugin context. `protocol` (optional) is a `jsonRpcProtocol`
/// structure; without it, the service has the implicit peers `client` and
/// `server`. `peer` (required) selects the peer to generate. `transports`
/// (optional, all by default) lists `stdio`, `http` and `websocket`. `extra`
/// lists the settings of the language plugin. The generators target JSON-RPC
/// 2.0.
pub fn PeerSettings::from_context(
  ctx : @codegen.PluginContext,
  extra~ : Array[String] = [],
) -> PeerSettings raise @codegen.CodegenError {
  ctx.check_settings(["protocol", "peer", "transports", ..extra])
  guard ctx.setting_string("peer") is Some(peer_text) else {
    raise @codegen.InvalidSettings(
      "I expected setting `peer`, the name of the peer to generate.",
    )
  }
  let service = ctx.service.id
  let description = match ctx.setting_string("protocol") {
    Some(text) => {
      guard @smithy.ShapeId::parse(text) is Some(protocol) else {
        raise @codegen.InvalidSettings(
          "I expected a shape ID in setting `protocol`, found `\{text}`.",
        )
      }
      let description = Description::for_protocol(
        ctx.model,
        protocol,
        @rpc.V2_0,
      ) catch {
        error => raise peer_settings_error(error)
      }
      let services = description.peers.filter_map(peer => {
        peer.accepts.map(accepts => accepts.service)
      })
      services.sort_by((a, b) => a.to_string().lexical_compare(b.to_string()))
      if !services.contains(service) {
        let names = services.map(id => id.to_string()).join(", ")
        raise @codegen.InvalidSettings(
          "I expected setting `service` to name a service of protocol `\{protocol}` (\{names}), found `\{service}`.",
        )
      }
      description
    }
    None =>
      Description::for_service(ctx.model, service, @rpc.V2_0) catch {
        error => raise peer_settings_error(error)
      }
  }
  let selection = match @rpc.PeerName::parse(peer_text) {
    Some(name) => description.peer(name)
    None => None
  }
  guard selection is Some(peer) else {
    let names = description.peers.map(peer => peer.name.to_string())
    match description.protocol {
      Some(protocol) =>
        raise @codegen.InvalidSettings(
          "I expected setting `peer` to name a peer of protocol `\{protocol}` (\{names.join(", ")}), found `\{peer_text}`.",
        )
      None =>
        raise @codegen.InvalidSettings(
          "I expected setting `peer` to be `client` or `server` for service `\{service}`, found `\{peer_text}`.",
        )
    }
  }
  { description, peer, transports: read_transports(ctx), }
}

///|
fn read_transports(
  ctx : @codegen.PluginContext,
) -> Array[Transport] raise @codegen.CodegenError {
  guard ctx.settings.get("transports") is Some(value) else {
    return [Stdio, Http, WebSocket]
  }
  guard value is Array(items) else {
    raise @codegen.InvalidSettings(
      "I expected an array of transports in setting `transports`.",
    )
  }
  let transports : Array[Transport] = []
  for item in items {
    let transport = match item {
      String("stdio") => Stdio
      String("http") => Http
      String("websocket") => WebSocket
      String(text) =>
        raise @codegen.InvalidSettings(
          "I expected each transport in setting `transports` to be `stdio`, `http` or `websocket`, found `\{text}`.",
        )
      _ =>
        raise @codegen.InvalidSettings(
          "I expected each transport in setting `transports` to be a string.",
        )
    }
    if transports.contains(transport) {
      raise @codegen.InvalidSettings(
        "I found transport `\{transport.to_string()}` twice in setting `transports`.",
      )
    }
    transports.push(transport)
  }
  transports
}

///|
/// The services of the peer: the service it accepts and the service it calls,
/// without duplicates, in lexical shape ID order.
pub fn PeerSettings::services(self : PeerSettings) -> Array[@smithy.ShapeId] {
  let out : Array[@smithy.ShapeId] = []
  for service in [self.peer.accepts, self.peer.calls] {
    if service is Some(description) && !out.contains(description.service) {
      out.push(description.service)
    }
  }
  out.sort_by((a, b) => a.to_string().lexical_compare(b.to_string()))
  out
}

///|
/// The contextual names of the shapes of the peer's services.
pub fn PeerSettings::names(
  self : PeerSettings,
  model : @smithy.Model,
) -> @codegen.ServiceNames raise @codegen.CodegenError {
  @codegen.ServiceNames::for_services(model, self.services())
}
