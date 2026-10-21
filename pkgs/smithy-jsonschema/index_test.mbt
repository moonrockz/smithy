///|
test "prepared structure filtering preserves references and drops required bindings" {
  let loaded = @smithy.Loader::new()
    .add_idl(
      "index.smithy",
      (
        #|$version: "2"
        #|namespace example
        #|service Api { version: "1", operations: [Get] }
        #|operation Get { input: Input, output: Output }
        #|@input
        #|structure Input {
        #|    @required
        #|    @httpHeader("x-token")
        #|    token: String
        #|    @required
        #|    value: Value
        #|}
        #|@output
        #|structure Output {}
        #|structure Value { name: String }
        #|list Values { member: Value }
        #|map Lookup { key: String, value: Value }
      ),
    )
    .assemble()
  assert_false(loaded.has_errors())
  let model = loaded.model.unwrap()
  let index = @jsonschema.SchemaIndex::new(model, service="example#Api")
  let before = index.document()
  let input = @smithy.ShapeId::parse("example#Input").unwrap()
  let value = input.with_member("value").unwrap()
  let filtered = index.structure(input, [value])
  assert_eq(
    filtered,
    @json.parse(
      "{\"type\":\"object\",\"properties\":{\"value\":{\"$ref\":\"#/definitions/Value\"}},\"required\":[\"value\"]}",
    ),
  )
  assert_eq(
    index.schema_for_member(value),
    @json.parse("{\"$ref\":\"#/definitions/Value\"}"),
  )
  assert_eq(index.document(), before)
  assert_eq(index.definition("Value"), @smithy.ShapeId::parse("example#Value"))
  for id in ["example#Values$member", "example#Lookup$value"] {
    assert_eq(
      index.schema_for_member(@smithy.ShapeId::parse(id).unwrap()),
      @json.parse("{\"$ref\":\"#/definitions/Value\"}"),
    )
  }
}
