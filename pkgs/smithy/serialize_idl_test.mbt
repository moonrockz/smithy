///|
test "IDL serialization preserves namespaces, traits, metadata and every shape kind" {
  let text =
    #|$version: "2"
    #|metadata values = [9007199254740993, {"escaped": "line\nquote\""}]
    #|namespace example
    #|@trait
    #|structure custom { value: String }
    #|@custom(value: "test")
    #|string Name
    #|list Names { member: Name }
    #|map Lookup { key: String, value: Name }
    #|enum Color {
    #|    RED = "red"
    #|    BLUE
    #|}
    #|intEnum Code { OK = 200 }
    #|union Choice { name: Name, code: Code }
    #|@mixin
    #|structure Base { @required id: String }
    #|structure Input with [Base] { count: Integer = 3 }
    #|@error("client")
    #|structure Problem { message: String }
    #|operation Get { input: Input, output: other#Output, errors: [Problem] }
    #|resource Item { identifiers: {id: String}, properties: {name: Name}, read: Get }
    #|service Api { version: "1", operations: [Get], resources: [Item], errors: [Problem], rename: {"other#Output": "Result"} }
  let result = @smithy.Loader::new()
    .add_idl("example.smithy", text)
    .add_idl(
      "other.smithy", "$version: \"2\"\nnamespace other\nstructure Output {}",
    )
    .assemble()
  assert_eq(result.diagnostics, [])
  let model = result.model.unwrap()
  let files = model.to_idl()
  assert_eq(files.length(), 2)
  let loader = @smithy.Loader::new()
  for ns, text in files {
    ignore(loader.add_idl(ns + ".smithy", text))
  }
  let restored = loader.assemble()
  assert_eq(restored.diagnostics, [])
  assert_eq(
    @syntax.encode_json_ast(restored.model.unwrap().to_json_ast()),
    @syntax.encode_json_ast(model.to_json_ast()),
  )
  assert_eq(restored.model.unwrap().to_idl(), files)
}

///|
test "empty and metadata-only models have one namespace-free document" {
  for text in ["", "metadata items = [1, 2]"] {
    let model = @smithy.Loader::new().add_idl("input", text).assemble().model.unwrap()
    let files = model.to_idl()
    assert_eq(files.length(), 1)
    let restored = @smithy.Loader::new()
      .add_idl("output", files.get("").unwrap())
      .assemble()
    assert_eq(restored.diagnostics, [])
    assert_eq(restored.model.unwrap().metadata, model.metadata)
  }
}
