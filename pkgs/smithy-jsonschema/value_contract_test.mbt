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

///|
test "value schemas constrain every primitive prelude scalar and its intrinsic bounds" {
  let loaded = @smithy.Loader::new()
    .add_idl(
      "primitives.smithy",
      (
        #|$version: "2"
        #|namespace primitives
        #|structure Input {
        #| @default(false) flag: PrimitiveBoolean
        #| @default(0) byte: PrimitiveByte
        #| @default(0) short: PrimitiveShort
        #| @default(0) integer: PrimitiveInteger
        #| @default(0) long: PrimitiveLong
        #| @default(0) float: PrimitiveFloat
        #| @default(0) double: PrimitiveDouble
        #| @default(0) @range(min: 1) bounded: PrimitiveInteger
        #|}
      ),
    )
    .assemble()
  assert_false(loaded.has_errors())
  let index = @jsonschema.SchemaIndex::for_values(loaded.model.unwrap())
  for
    (name, expected) in [
      ("flag", "boolean"),
      ("byte", "integer"),
      ("short", "integer"),
      ("integer", "integer"),
      ("long", "integer"),
      ("float", "number"),
      ("double", "number"),
    ] {
    let schema = index.schema_for_member(
      @smithy.ShapeId::parse("primitives#Input$" + name).unwrap(),
    )
    assert_true(
      schema is Object(fields) &&
      fields.get("type") == Some(Json::string(expected)),
    )
    if name != "flag" {
      assert_true(
        schema is Object(fields) &&
        fields.contains("minimum") &&
        fields.contains("maximum"),
      )
    }
  }
  assert_true(
    index.schema_for_member(
      @smithy.ShapeId::parse("primitives#Input$bounded").unwrap(),
    )
    is { "minimum": Number(1, ..), "maximum": Number(2147483647, ..), .. },
  )
}

///|
test "value schemas explicitly reject union strategies that discard member contracts" {
  let model = @smithy.Loader::new()
  .add_idl(
    "union.smithy",
    (
      #|$version: "2"
      #|namespace choices
      #|union Choice { text: String, count: Integer }
    ),
  )
  .assemble().model.unwrap()
  for strategy in ["structure", "object"] {
    let settings = @jsonschema.Config::new(union_strategy=strategy)
    let mut rejected = false
    ignore(@jsonschema.SchemaIndex::for_values(model, config=settings)) catch {
      @jsonschema.InvalidConfiguration(message) => {
        rejected = true
        assert_true(message.contains("oneOf"))
      }
      _ => fail("Expected unsupported value profile option")
    }
    assert_true(rejected)
    // The reference-compatible API still supports its existing strategies.
    assert_true(@jsonschema.convert(model, config=settings) is Object(_))
  }
}
