///|
fn fixture(name : String) -> String raise {
  @fs.read_file_to_string("../../tests/tck/jsonschema/" + name)
}

///|
test "vendored test-service document matches reference" {
  let source = fixture("test-service.json")
  let expected = @json.parse(fixture("test-service.jsonschema.v07.json"))
  let result = @smithy.Loader::new()
    .add_json("test-service.json", source)
    .assemble()
  guard result.model is Some(model) else {
    fail(result.diagnostics.map(d => d.code + ": " + d.message).join("\n"))
  }
  let actual = @jsonschema.convert(model)
  assert_eq(actual, expected)
}

///|
test "vendored title-added document matches reference" {
  let source = fixture("title-added.smithy")
  let expected = @json.parse(fixture("title-added.jsonschema.v07.json"))
  let result = @smithy.Loader::new()
    .add_idl("title-added.smithy", source)
    .assemble()
  guard result.model is Some(model) else {
    fail(result.diagnostics.map(d => d.code + ": " + d.message).join("\n"))
  }
  assert_eq(@jsonschema.convert(model), expected)
}

///|
fn check_idl_case(
  source_name : String,
  expected_name : String,
  config : @jsonschema.Config,
) -> Unit raise {
  let source = fixture(source_name)
  let expected = @json.parse(fixture(expected_name))
  let result = @smithy.Loader::new().add_idl(source_name, source).assemble()
  guard result.model is Some(model) else {
    fail(result.diagnostics.map(d => d.code + ": " + d.message).join("\n"))
  }
  assert_eq(@jsonschema.convert(model, config~), expected, msg=expected_name)
}

///|
test "vendored default-values document matches reference" {
  check_idl_case(
    "default-values.smithy",
    "default-values.jsonschema.v07.json",
    @jsonschema.Config::new(),
  )
}

///|
test "vendored int-enums document matches reference" {
  check_idl_case(
    "int-enums.smithy",
    "int-enums.jsonschema.v07.json",
    @jsonschema.Config::new(),
  )
}

///|
test "vendored non-numeric-floats document matches reference" {
  let source = fixture("non-numeric-floats.json")
  let expected = @json.parse(fixture("non-numeric-floats.jsonschema.v07.json"))
  let result = @smithy.Loader::new()
    .add_json("non-numeric-floats.json", source)
    .assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let config = @jsonschema.Config::new(support_non_numeric_floats=true)
  assert_eq(@jsonschema.convert(model, config~), expected)
}

///|
test "vendored member-documentation document matches reference" {
  check_idl_case(
    "member-documentation.smithy",
    "member-documentation.jsonschema.json",
    @jsonschema.Config::new(add_reference_descriptions=true),
  )
}

///|
test "vendored default-values-disabled document matches reference" {
  check_idl_case(
    "default-values.smithy",
    "default-values-disabled.jsonschema.v07.json",
    @jsonschema.Config::new(disable_default_values=true),
  )
}

///|
test "vendored int-enums-disabled document matches reference" {
  check_idl_case(
    "int-enums.smithy",
    "int-enums-disabled.jsonschema.v07.json",
    @jsonschema.Config::new(disable_int_enums=true),
  )
}

///|
test "vendored integer-types document matches reference" {
  check_idl_case(
    "integer-types.smithy",
    "integer-types.jsonschema.v07.json",
    @jsonschema.Config::new(use_integer_type=true),
  )
}

///|
test "vendored string-enums-one-of document matches reference" {
  check_idl_case(
    "string-enums.smithy",
    "string-enums-one-of.jsonschema.v07.json",
    @jsonschema.Config::new(enum_strategy="oneOf"),
  )
}

///|
test "vendored draft 2020-12 document matches reference" {
  let source = fixture("test-service.json")
  let expected = @json.parse(fixture("test-service.jsonschema.v2020.json"))
  let result = @smithy.Loader::new()
    .add_json("test-service.json", source)
    .assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let config = @jsonschema.Config::new(definition_pointer="#/$defs")
  assert_eq(@jsonschema.convert(model, config~), expected)
}

///|
test "vendored recursive document terminates and retains self reference" {
  let source = fixture("recursive.json")
  let result = @smithy.Loader::new()
    .add_json("recursive.json", source)
    .assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let converted = @jsonschema.convert(model)
  guard converted is Object(document) &&
    document.get("definitions") is Some(Object(definitions)) &&
    definitions.get("Foo") is Some(Object(foo)) &&
    foo.get("properties") is Some(Object(properties)) &&
    properties.get("foo") is Some(Object(reference)) else {
    fail("recursive structure is missing")
  }
  assert_eq(reference.get("$ref"), Some(Json::string("#/definitions/Foo")))
}

///|
test "vendored mixin is flattened and omitted" {
  let source = fixture("model-with-mixins.smithy")
  let result = @smithy.Loader::new()
    .add_idl("model-with-mixins.smithy", source)
    .assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let converted = @jsonschema.convert(model)
  guard converted is Object(document) &&
    document.get("definitions") is Some(Object(definitions)) else {
    fail("definitions are missing")
  }
  assert_true(definitions.get("Mixin") is None)
  guard definitions.get("UsesMixin") is Some(Object(shape)) &&
    shape.get("properties") is Some(Object(properties)) else {
    fail("flattened structure is missing")
  }
  assert_true(properties.get("foo") is Some(_))
  assert_true(properties.get("baz") is Some(_))
}

///|
test "vendored service rename is used in definitions and references" {
  let source = fixture("service-renames.json")
  let result = @smithy.Loader::new()
    .add_json("service-renames.json", source)
    .assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let converted = @jsonschema.convert(model, service="smithy.example#MyService")
  guard converted is Object(document) &&
    document.get("definitions") is Some(Object(definitions)) &&
    definitions.get("GetSomethingOutput") is Some(Object(output)) &&
    output.get("properties") is Some(Object(properties)) else {
    fail("service output is missing")
  }
  assert_true(definitions.get("Widget") is Some(_))
  assert_true(definitions.get("FooWidget") is Some(_))
  assert_eq(
    properties.get("fooWidget"),
    Some(Json::object({ "$ref": Json::string("#/definitions/FooWidget") })),
  )
}
