///|
test "long forward mixin chains use an explicit dependency stack" {
  let text = StringBuilder()
  text.write_string(
    "$version: \"2\"\nnamespace example.chain\nstructure Result with [Mixin0] {}\n",
  )
  for i in 0..<400 {
    text.write_string("@mixin\nstructure Mixin\{i} with [Mixin\{i + 1}] {}\n")
  }
  text.write_string("@mixin\nstructure Mixin400 { value: String }\n")
  let model = loaded(
    @smithy.Loader::new().add_idl("chain.smithy", text.to_string()),
  )
  guard model.get("example.chain#Result$value").unwrap().body is Member(target~) else {
    fail("no member")
  }
  assert_eq(target.to_string(), "smithy.api#String")
}

///|
test "resource binding rejects explicit targets that conflict with the resource" {
  let result = @smithy.Loader::new()
    .add_idl(
      "binding.smithy",
      (
        #|$version: "2"
        #|namespace example.binding
        #|resource R { identifiers: { id: String } }
        #|structure Input for R { id: Integer }
      ),
    )
    .assemble()
  assert_true(result.diagnostics.iter().any(d => d.code == "SM-MODEL-012"))
}

///|
test "a caller source name cannot impersonate the prelude" {
  let result = @smithy.Loader::new()
    .add_idl("<prelude>", "namespace smithy.api\nstring Injected\n")
    .assemble()
  assert_eq(result.model, None)
  assert_true(result.diagnostics.iter().any(d => d.code == "SM-MODEL-001"))
}

///|
test "an export including the unchanged standard prelude can be loaded again" {
  let model = loaded(@smithy.Loader::new())
  let document = model.to_json_ast(include_prelude=true)
  let restored = loaded(@smithy.Loader::new().add_ast("full.json", document))
  assert_eq(
    @syntax.encode_json_ast(restored.to_json_ast()),
    @syntax.encode_json_ast(model.to_json_ast()),
  )
}
