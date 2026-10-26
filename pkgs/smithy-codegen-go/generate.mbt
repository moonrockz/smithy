///|
/// Generate one peer from a prepared description. This function does not read
/// RPC traits. The semantic model supplies value shapes and service names.
pub fn generate(
  model : @smithy.Model,
  description : @jsonrpc.Description,
  peer : @rpc.PeerName,
  module_name~ : String = "example/generated",
  package_name~ : String = "generated",
) -> Map[String, String] raise @codegen.CodegenError {
  check_output_names(module_name, package_name)
  if description.version != @rpc.V2_0 {
    raise @codegen.InvalidSettings(
      "I support JSON-RPC version `2.0` in the Go generator.",
    )
  }
  let ctx = create_context(model, description, peer, module_name, package_name)
  check_generated_names(ctx)
  let files = runtime_files()
  let out : Map[String, String] = Map([])
  let paths = files.keys().to_array()
  paths.sort_by((a, b) => a.lexical_compare(b))
  for path in paths {
    if path == "go.mod" {
      let lines = files[path].split("\n").to_array()
      out["go.mod"] = lines
        .map(line => {
          if line.has_prefix("module ") {
            "module " + module_name
          } else {
            line.to_owned()
          }
        })
        .join("\n")
    } else if path == "go.sum" {
      out[path] = files[path]
    } else {
      out["rpc/" + path] = files[path]
    }
  }
  if !out.contains("go.mod") {
    raise @codegen.StateError(
      "I could not find the embedded runtime manifest `go.mod` in the Go generator.",
    )
  }
  out["types.go"] = generate_types(ctx)
  out["contract.go"] = generate_contract(ctx)
  out["peer.go"] = generate_peer(ctx)
  out["errors.go"] = generate_errors(ctx)
  out
}
