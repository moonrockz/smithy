///|
test "value schemas preserve member replacement constraints and closed union cardinality" {
  let loaded = @smithy.Loader::new()
    .add_idl(
      "values.smithy",
      (
        #|$version: "2"
        #|namespace values
        #|service Api { version: "1", operations: [Op] }
        #|operation Op { input: Input }
        #|structure Input {
        #|  @required @range(min: 0) count: Count
        #|  @length(max: 8) text: Text
        #|  choice: Choice
        #|  @documentation("Recursive member") recursive: Input
        #|  entries: Entries
        #|  loops: Loops
        #|  @range(min: -9999999999, max: 9999999999) wide: Integer
        #|}
        #|@range(min: 2, max: 5)
        #|integer Count
        #|@length(min: 3, max: 5)
        #|string Text
        #|union Choice { first: String, second: Integer }
        #|@sparse
        #|list Entries { member: Integer }
        #|list Loops { @length(min: 1) member: Loops }
      ),
    )
    .assemble()
  assert_false(loaded.has_errors())
  let index = @jsonschema.SchemaIndex::for_values(
    loaded.model.unwrap(),
    service="values#Api",
    config=@jsonschema.Config::new(
      use_integer_type=true,
      disable_default_values=true,
    ),
  )
  assert_eq(
    index.schema_for_member(
      @smithy.ShapeId::parse("values#Input$count").unwrap(),
    ),
    @json.parse("{\"type\":\"integer\",\"minimum\":0,\"maximum\":2147483647}"),
  )
  assert_eq(
    index.schema_for_member(
      @smithy.ShapeId::parse("values#Input$text").unwrap(),
    ),
    @json.parse("{\"type\":\"string\",\"maxLength\":8}"),
  )
  guard index.shape(@smithy.ShapeId::parse("values#Input").unwrap())
    is Object(input) else {
    fail("Expected input schema")
  }
  assert_eq(input["additionalProperties"], Json::boolean(false))
  assert_true(
    input["properties"]
    is { "recursive": { "$ref": String("#/definitions/Input"), .. }, .. },
  )
  guard index.shape(@smithy.ShapeId::parse("values#Choice").unwrap())
    is Object(choice) else {
    fail("Expected union schema")
  }
  assert_eq(choice["maxProperties"], Json::number(1))
  assert_eq(choice["minProperties"], Json::number(1))
  assert_eq(choice["additionalProperties"], Json::boolean(false))
  guard index.shape(@smithy.ShapeId::parse("values#Entries").unwrap())
    is Object(entries) else {
    fail("Expected list schema")
  }
  assert_true(
    entries["items"] is { "anyOf": Array(options), .. } && options.length() == 2,
  )
  assert_eq(
    index.schema_for_member(
      @smithy.ShapeId::parse("values#Input$wide").unwrap(),
    ),
    @json.parse(
      "{\"type\":\"integer\",\"minimum\":-2147483648,\"maximum\":2147483647}",
    ),
  )
  guard index.shape(@smithy.ShapeId::parse("values#Loops").unwrap())
    is Object(loops) else {
    fail("Expected recursive list schema")
  }
  assert_true(
    loops["items"] is { "$ref": String("#/definitions/Loops_member"), .. },
  )
  assert_true(
    index.document()
    is {
      "definitions": {
        "Loops_member": {
          "minItems": Number(1, ..),
          "items": { "$ref": String("#/definitions/Loops_member"), .. },
          ..
        },
        ..
      },
      ..
    },
  )
}
