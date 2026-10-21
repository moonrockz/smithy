///|
test "existing JSON Schema configuration records remain source compatible" {
  let config : @jsonschema.Config = {
    map_strategy: "propertyNames",
    union_strategy: "oneOf",
    enum_strategy: "enum",
    use_json_name: false,
    default_timestamp_format: "date-time",
    support_non_numeric_floats: false,
    schema_document_extensions: Json::object(Map([])),
    definition_pointer: "#/definitions",
    add_reference_descriptions: false,
    disable_default_values: false,
    disable_int_enums: false,
    use_integer_type: false,
    alphanumeric_only_refs: false,
  }
  let loaded = @smithy.Loader::new()
    .add_idl(
      "value.smithy", "$version: \"2\"\nnamespace value\nstructure Value { count: Integer }",
    )
    .assemble()
  let schema = @jsonschema.convert(loaded.model.unwrap(), config~)
  assert_true(
    schema
    is {
      "definitions": {
        "Value": {
          "properties": { "count": { "type": String("number"), .. }, .. },
          ..
        },
        ..
      },
      ..
    },
  )
}
