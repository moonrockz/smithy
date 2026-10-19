///|
test "structure members become value schemas and linked shapes become references" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|structure Input {
    #|    name: String
    #|    next: Input
    #|}
  let result = @smithy.Loader::new().add_idl("input.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let actual = @jsonschema.convert(model)
  let expected_text =
    #|{"definitions":{"Input":{"type":"object","properties":{"name":{"type":"string"},"next":{"$ref":"#/definitions/Input"}}}}}
  let expected = @json.parse(expected_text)
  assert_eq(actual, expected)
}

///|
test "configured service limits definitions to its closure" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|service Api { version: "1", operations: [Get] }
    #|operation Get { input: Input, output: Output }
    #|structure Input { name: String }
    #|structure Output { ok: Boolean }
    #|structure Unused { id: String }
  let result = @smithy.Loader::new().add_idl("api.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let actual = @jsonschema.convert(model, service="example#Api")
  let expected_text =
    #|{"definitions":{"Input":{"type":"object","properties":{"name":{"type":"string"}}},"Output":{"type":"object","properties":{"ok":{"type":"boolean"}}}}}
  assert_eq(actual, @json.parse(expected_text))
}

///|
test "enum definitions retain values and documentation" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|structure Foo { bar: TestEnum }
    #|@documentation("This is a test enum")
    #|enum TestEnum {
    #|  @documentation("it really does foo")
    #|  FOO = "Foo"
    #|  @title("TestEnum Bar")
    #|  BAR = "Bar"
    #|}
  let result = @smithy.Loader::new().add_idl("enum.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let actual = @jsonschema.convert(model)
  let expected_text =
    #|{"definitions":{"Foo":{"type":"object","properties":{"bar":{"$ref":"#/definitions/TestEnum"}}},"TestEnum":{"type":"string","enum":["Foo","Bar"],"description":"This is a test enum"}}}
  assert_eq(actual, @json.parse(expected_text))
}

///|
test "simple and collection targets inline at member sites" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|string Name
    #|list Names { member: Name }
    #|structure Person { names: Names }
  let result = @smithy.Loader::new().add_idl("inline.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let actual = @jsonschema.convert(model)
  let expected_text =
    #|{"definitions":{"Person":{"type":"object","properties":{"names":{"type":"array","items":{"type":"string"}}}}}}
  assert_eq(actual, @json.parse(expected_text))
}

///|
test "maps use propertyNames and additionalProperties by default" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|map Labels { key: String, value: String }
  let result = @smithy.Loader::new().add_idl("map.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let expected_text =
    #|{"definitions":{"Labels":{"type":"object","propertyNames":{"type":"string"},"additionalProperties":{"type":"string"}}}}
  assert_eq(@jsonschema.convert(model), @json.parse(expected_text))
}

///|
test "patternProperties map strategy uses key pattern" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|map Labels {
    #|  @pattern("^[a-z]+$")
    #|  key: String
    #|  value: String
    #|}
  let result = @smithy.Loader::new().add_idl("map.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let config = @jsonschema.Config::new(map_strategy="patternProperties")
  let expected_text =
    #|{"definitions":{"Labels":{"type":"object","patternProperties":{"^[a-z]+$":{"type":"string"}}}}}
  assert_eq(@jsonschema.convert(model, config~), @json.parse(expected_text))
}

///|
test "unions use oneOf by default" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|union Choice { text: String, count: Integer }
  let result = @smithy.Loader::new().add_idl("union.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let expected_text =
    #|{"definitions":{"Choice":{"oneOf":[{"type":"object","title":"text","required":["text"],"properties":{"text":{"type":"string"}}},{"type":"object","title":"count","required":["count"],"properties":{"count":{"type":"number"}}}]}}}
  assert_eq(@jsonschema.convert(model), @json.parse(expected_text))
}

///|
test "structure union strategy emits an object with all members" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|union Choice { text: String, count: Integer }
  let result = @smithy.Loader::new().add_idl("union.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let config = @jsonschema.Config::new(union_strategy="structure")
  let expected_text =
    #|{"definitions":{"Choice":{"type":"object","properties":{"text":{"type":"string"},"count":{"type":"number"}}}}}
  assert_eq(@jsonschema.convert(model, config~), @json.parse(expected_text))
}

///|
test "oneOf enum strategy keeps per-value documentation" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|@documentation("Choices")
    #|enum Choice {
    #|  @documentation("First")
    #|  FIRST = "a"
    #|  @title("Second")
    #|  SECOND = "b"
    #|}
  let result = @smithy.Loader::new().add_idl("enum.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let config = @jsonschema.Config::new(enum_strategy="oneOf")
  let expected_text =
    #|{"definitions":{"Choice":{"type":"string","description":"Choices","oneOf":[{"const":"a","description":"First"},{"const":"b","title":"Second"}]}}}
  assert_eq(@jsonschema.convert(model, config~), @json.parse(expected_text))
}

///|
test "useJsonName changes structure property names" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|structure Input {
    #|  @jsonName("wire_name")
    #|  name: String
    #|}
  let result = @smithy.Loader::new().add_idl("name.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let config = @jsonschema.Config::new(use_json_name=true)
  let expected_text =
    #|{"definitions":{"Input":{"type":"object","properties":{"wire_name":{"type":"string"}}}}}
  assert_eq(@jsonschema.convert(model, config~), @json.parse(expected_text))
}

///|
test "timestamps default to date-time format" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|timestamp CreatedAt
    #|structure Event { created: CreatedAt }
  let result = @smithy.Loader::new().add_idl("time.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let expected_text =
    #|{"definitions":{"Event":{"type":"object","properties":{"created":{"type":"string","format":"date-time"}}}}}
  assert_eq(@jsonschema.convert(model), @json.parse(expected_text))
}

///|
test "epoch-seconds timestamp setting emits a number" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|timestamp CreatedAt
    #|structure Event { created: CreatedAt }
  let result = @smithy.Loader::new().add_idl("time.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let config = @jsonschema.Config::new(default_timestamp_format="epoch-seconds")
  let expected_text =
    #|{"definitions":{"Event":{"type":"object","properties":{"created":{"type":"number"}}}}}
  assert_eq(@jsonschema.convert(model, config~), @json.parse(expected_text))
}

///|
test "nonnumeric float support allows string sentinel values" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|float Temperature
    #|structure Event { temperature: Temperature }
  let result = @smithy.Loader::new().add_idl("float.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let config = @jsonschema.Config::new(support_non_numeric_floats=true)
  let expected_text =
    #|{"definitions":{"Event":{"type":"object","properties":{"temperature":{"oneOf":[{"type":"number"},{"type":"string","enum":["NaN","Infinity","-Infinity"]}]}}}}}
  assert_eq(@jsonschema.convert(model, config~), @json.parse(expected_text))
}

///|
test "schemaDocumentExtensions add root keys" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|string Name
    #|structure Person { name: Name }
  let result = @smithy.Loader::new().add_idl("name.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let extensions = @json.parse(
    "{\"$id\":\"https://example.test/schema\",\"x-owner\":\"team\"}",
  )
  let config = @jsonschema.Config::new(schema_document_extensions=extensions)
  let expected_text =
    #|{"$id":"https://example.test/schema","x-owner":"team","definitions":{"Person":{"type":"object","properties":{"name":{"type":"string"}}}}}
  assert_eq(@jsonschema.convert(model, config~), @json.parse(expected_text))
}

///|
test "definitionPointer nests schemas and changes references" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|structure Input { next: Input }
  let result = @smithy.Loader::new()
    .add_idl("pointer.smithy", source)
    .assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let config = @jsonschema.Config::new(
    definition_pointer="#/components/schemas",
  )
  let expected_text =
    #|{"components":{"schemas":{"Input":{"type":"object","properties":{"next":{"$ref":"#/components/schemas/Input"}}}}}}
  assert_eq(@jsonschema.convert(model, config~), @json.parse(expected_text))
}

///|
test "member documentation survives inline and referenced targets" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|structure Foo {
    #|  /// simple docs
    #|  foo: String
    #|  /// structure docs
    #|  bar: Bar
    #|}
    #|structure Bar {}
  let result = @smithy.Loader::new().add_idl("docs.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let config = @jsonschema.Config::new(add_reference_descriptions=true)
  let expected_text =
    #|{"definitions":{"Foo":{"type":"object","properties":{"foo":{"type":"string","description":"simple docs"},"bar":{"$ref":"#/definitions/Bar","description":"structure docs"}}},"Bar":{"type":"object"}}}
  assert_eq(@jsonschema.convert(model, config~), @json.parse(expected_text))
}

///|
test "vendored string-enums fixture matches reference document" {
  let root = "../../tests/tck/jsonschema/"
  let source = @fs.read_file_to_string(root + "string-enums.smithy")
  let expected = @json.parse(
    @fs.read_file_to_string(root + "string-enums.jsonschema.v07.json"),
  )
  let result = @smithy.Loader::new()
    .add_idl("string-enums.smithy", source)
    .assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  assert_eq(@jsonschema.convert(model), expected)
}
