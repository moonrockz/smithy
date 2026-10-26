///|
priv struct Settings {
  module_name : String
  package_name : String
  peer : @rpc.PeerName
  protocol : @smithy.ShapeId?
}

///|
fn go_identifier(text : String) -> Bool {
  if text.is_empty() {
    return false
  }
  for i, c in text.to_array() {
    if !(c == '_' ||
      (c >= 'A' && c <= 'Z') ||
      (c >= 'a' && c <= 'z') ||
      (i > 0 && c >= '0' && c <= '9')) {
      return false
    }
  }
  ![
    "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough",
    "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range",
    "return", "select", "struct", "switch", "type", "var", "_",
  ].contains(text)
}

///|
fn check_output_names(
  module_name : String,
  package_name : String,
) -> Unit raise @codegen.CodegenError {
  if module_name.is_empty() ||
    module_name.has_prefix("/") ||
    module_name.has_suffix("/") ||
    module_name
    .split("/")
    .any(part => part == ".." || part == "." || part.is_empty()) ||
    module_name
    .to_array()
    .any(c => {
      !((c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '/' ||
      c == '.' ||
      c == '-' ||
      c == '_')
    }) {
    raise @codegen.InvalidSettings(
      "I expected a Go module path in setting `module`; I found `\{module_name}`.",
    )
  }
  if !go_identifier(package_name) {
    raise @codegen.InvalidSettings(
      "I expected a Go package name in setting `package`; I found `\{package_name}`.",
    )
  }
}

///|
fn settings(
  plugin : @codegen.PluginContext,
) -> Settings raise @codegen.CodegenError {
  plugin.check_settings([
    "module", "package", "peer", "protocol", "version", "transports",
  ])
  let module_name = plugin
    .setting_string("module")
    .unwrap_or("example/generated")
  let package_name = plugin.setting_string("package").unwrap_or("generated")
  check_output_names(module_name, package_name)
  let peer_text = plugin.setting_string("peer").unwrap_or("client")
  guard @rpc.PeerName::parse(peer_text) is Some(peer) else {
    raise @codegen.InvalidSettings(
      "I expected a peer name in setting `peer`; I found `\{peer_text}`.",
    )
  }
  let protocol = match plugin.setting_string("protocol") {
    None => None
    Some(text) =>
      match @smithy.ShapeId::parse(text) {
        Some(id) => Some(id)
        None =>
          raise @codegen.InvalidSettings(
            "I expected a shape ID in setting `protocol`; I found `\{text}`.",
          )
      }
  }
  let version = plugin.setting_string("version").unwrap_or("2.0")
  if version != "2.0" {
    raise @codegen.InvalidSettings(
      "I support JSON-RPC version `2.0` in the Go generator; I found `\{version}`.",
    )
  }
  match plugin.settings.get("transports") {
    None => ()
    Some(Array(items)) =>
      for item in items {
        guard item is String(name) &&
          ["stdio", "http", "websocket"].contains(name) else {
          raise @codegen.InvalidSettings(
            "I expected `stdio`, `http`, or `websocket` in setting `transports`.",
          )
        }
      }
    Some(_) =>
      raise @codegen.InvalidSettings(
        "I expected an array in setting `transports`.",
      )
  }
  { module_name, package_name, peer, protocol, }
}

///|
/// Register this plugin as `go-jsonrpc-codegen` in the build runner.
pub fn plugin(
  model : @smithy.Model,
  raw : Json,
) -> Map[String, String] raise @build.BuildError {
  @codegen.build_plugin(run)(model, raw)
}

///|
/// Prepare RPC settings once, then generate one peer.
pub fn run(
  plugin : @codegen.PluginContext,
) -> Map[String, String] raise @codegen.CodegenError {
  let config = settings(plugin)
  let description = try {
    match config.protocol {
      Some(id) =>
        @jsonrpc.Description::for_protocol(plugin.model, id, @rpc.V2_0)
      None =>
        @jsonrpc.Description::for_service(
          plugin.model,
          plugin.service.id,
          @rpc.V2_0,
        )
    }
  } catch {
    @rpc.InvalidContract(id, message) =>
      raise @codegen.InvalidSettings(
        "I could not prepare RPC construct `\{id}`: \{message}",
      )
    error =>
      raise @codegen.InvalidSettings(
        "I could not prepare the Go RPC contract: \{error}",
      )
  }
  generate(
    plugin.model,
    description,
    config.peer,
    module_name=config.module_name,
    package_name=config.package_name,
  )
}
