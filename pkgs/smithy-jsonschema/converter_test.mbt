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
    #|{"definitions":{"Name":{"type":"string"},"Names":{"type":"array","items":{"type":"string"}},"Person":{"type":"object","properties":{"names":{"type":"array","items":{"type":"string"}}}}}}
  assert_eq(actual, @json.parse(expected_text))
}
