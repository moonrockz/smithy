///|
fn loaded(loader : @smithy.Loader) -> @smithy.Model raise {
  let result = loader.assemble()
  guard result.model is Some(model) else {
    fail(
      "assembly failed: " +
      result.diagnostics.map(d => d.code + ": " + d.message).join("\n"),
    )
  }
  model
}

///|
test "the official prelude assembles and contains public and private definitions" {
  let model = loaded(@smithy.Loader::new())
  assert_true(model.get("smithy.api#String") is Some(_))
  assert_true(model.get("smithy.api#trait") is Some(_))
  assert_true(model.get("smithy.api#Unit") is Some(_))
  assert_true(model.shapes.length() > 100)
  assert_eq(model.to_json_ast().shapes, Some(Map([])))
}

///|
test "load a JSON structure, add the prelude, and expose member shapes" {
  let model = loaded(
    @smithy.Loader::new().add_json(
      "city.json",
      (
        #|{"smithy":"2.0","shapes":{"example.weather#City":{"type":"structure","members":{"name":{"target":"smithy.api#String"}}}}}
      ),
    ),
  )
  let member_ = model.get("example.weather#City$name").unwrap()
  guard member_.body is Member(target~) else { fail("expected a member") }
  assert_eq(target.to_string(), "smithy.api#String")
  assert_eq(member_.source.file, "city.json")
}

///|
test "unresolved references return diagnostics and no partial model" {
  let result = @smithy.Loader::new()
    .add_idl(
      "city.smithy",
      (
        #|$version: "2"
        #|namespace example.weather
        #|structure City {
        #|  name: Missing
        #|}
      ),
    )
    .assemble()
  assert_true(result.has_errors())
  assert_eq(result.model, None)
  assert_true(
    result.diagnostics
    .iter()
    .any(d => {
      d.code == "SM-MODEL-004" &&
      d.message.contains("example.weather#Missing") &&
      d.source.file == "city.smithy"
    }),
  )
}

///|
test "mixed representations resolve imports, local forward references, and prelude shadowing" {
  let loader = @smithy.Loader::new()
    .add_idl(
      "city.smithy",
      (
        #|$version: "2"
        #|namespace example.weather
        #|use example.other#Name
        #|structure City {
        #|  name: Name
        #|  local: String
        #|  builtin: smithy.api#String
        #|}
      ),
    )
    .add_json(
      "name.json",
      (
        #|{"smithy":"2","shapes":{"example.other#Name":{"type":"string"},"example.weather#String":{"type":"string"}}}
      ),
    )
  let model = loaded(loader)
  guard model.get("example.weather#City$local").unwrap().body is Member(target~) else {
    fail("expected a member")
  }
  assert_eq(target.to_string(), "example.weather#String")
  let again = loaded(loader)
  assert_eq(
    @syntax.encode_json_ast(model.to_json_ast()),
    @syntax.encode_json_ast(again.to_json_ast()),
  )
}

///|
test "mixins and apply flatten with inherited member traits and local precedence" {
  let model = loaded(
    @smithy.Loader::new().add_idl(
      "mixins.smithy",
      (
        #|$version: "2"
        #|namespace example.weather
        #|@mixin
        #|structure Base {
        #|  @documentation("base")
        #|  name: String
        #|}
        #|structure City with [Base] {
        #|  @required
        #|  $name
        #|}
        #|apply City$name @documentation("city")
      ),
    ),
  )
  let member_ = model.get("example.weather#City$name").unwrap()
  assert_eq(
    member_.trait_value("smithy.api#documentation"),
    Some(String("city")),
  )
  assert_true(member_.trait_value("smithy.api#required") is Some(_))
  assert_true(
    model.get("example.weather#City").unwrap().trait_value("smithy.api#mixin")
    is None,
  )
  loaded(@smithy.Loader::new().add_ast("flattened.json", model.to_json_ast()))
  |> ignore
}

///|
test "metadata and list-valued traits merge across files" {
  let model = loaded(
    @smithy.Loader::new()
    .add_idl(
      "a.smithy",
      (
        #|$version: "2"
        #|metadata files = ["a"]
        #|namespace example.weather
        #|@tags(["first"])
        #|string Name
      ),
    )
    .add_idl(
      "b.smithy",
      (
        #|$version: "2"
        #|metadata files = ["b"]
        #|namespace example.weather
        #|apply Name @tags(["second"])
      ),
    ),
  )
  assert_eq(
    model.metadata.get("files"),
    Some(Array([String("a"), String("b")])),
  )
  assert_eq(
    model.get("example.weather#Name").unwrap().trait_value("smithy.api#tags"),
    Some(Array([String("first"), String("second")])),
  )
}

///|
test "resource-bound elision and inline operation suffixes produce explicit targets" {
  let model = loaded(
    @smithy.Loader::new().add_idl(
      "resource.smithy",
      (
        #|$version: "2"
        #|$operationInputSuffix: "Request"
        #|namespace example.weather
        #|resource City {
        #|  identifiers: { id: String }
        #|  read: GetCity
        #|}
        #|operation GetCity {
        #|  input := for City { $id }
        #|}
      ),
    ),
  )
  assert_true(model.get("example.weather#GetCityRequest$id") is Some(_))
  assert_true(
    model
    .get("example.weather#GetCityRequest")
    .unwrap()
    .trait_value("smithy.api#input")
    is Some(_),
  )
}
