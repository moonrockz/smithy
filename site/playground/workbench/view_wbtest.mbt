///|
test "hint: each output names the CLI command that gives it" {
  assert_eq(cli_hint(JsonAst, "", 1), "smithy convert --to json model.smithy")
  assert_eq(cli_hint(Idl, "", 1), "smithy convert --to idl model.smithy")
  assert_eq(
    cli_hint(Idl, "", 2),
    "smithy convert --to idl --output-dir DIR model.smithy",
  )
  assert_eq(
    cli_hint(Selector, "structure > member", 1),
    "smithy select --selector 'structure > member' model.smithy",
  )
  assert_eq(
    cli_hint(JsonSchema, "", 1),
    "smithy build --config smithy-build.json, with the plugin \"jsonSchema\"",
  )
  assert_eq(
    cli_hint(OpenApi31, "", 1),
    "smithy build --config smithy-build.json, with the plugin \"openapi\" and \"version\": \"3.1.0\"",
  )
  assert_eq(
    cli_hint(OpenRpc, "", 1),
    "smithy build --config smithy-build.json, with the plugin \"openrpc\"",
  )
}

///|
test "hint: a selector with a single quote stays one argument" {
  assert_eq(
    cli_hint(Selector, "[id='a#B']", 1),
    "smithy select --selector '[id='\\''a#B'\\'']' model.smithy",
  )
}

///|
test "picker: every output has its own key and label" {
  let keys = outputs.map(output => output.key())
  assert_eq(keys.length(), 7)
  for output in outputs {
    assert_eq(output_of_key(output.key()), Some(output))
  }
  assert_eq(output_of_key("nope"), None)
  assert_eq(outputs.map(output => output.label()), [
    "JSON AST", "Formatted IDL", "Selector query", "JSON Schema", "OpenAPI 3.0.2",
    "OpenAPI 3.1.0", "OpenRPC 1.3.2",
  ])
}
