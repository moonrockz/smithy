///|
/// Conversion settings shared with the JSON Schema build plugin.
pub(all) struct Config {
  map_strategy : String
  union_strategy : String
  enum_strategy : String
  use_json_name : Bool
  default_timestamp_format : String
  support_non_numeric_floats : Bool
  schema_document_extensions : Json
  definition_pointer : String
  add_reference_descriptions : Bool
  disable_default_values : Bool
  disable_int_enums : Bool
  use_integer_type : Bool
  alphanumeric_only_refs : Bool
}

///|
pub fn Config::new(
  map_strategy~ : String = "propertyNames",
  union_strategy~ : String = "oneOf",
  enum_strategy~ : String = "enum",
  use_json_name~ : Bool = false,
  default_timestamp_format~ : String = "date-time",
  support_non_numeric_floats~ : Bool = false,
  schema_document_extensions~ : Json = Json::object(Map([])),
  definition_pointer~ : String = "#/definitions",
  add_reference_descriptions~ : Bool = false,
  disable_default_values~ : Bool = false,
  disable_int_enums~ : Bool = false,
  use_integer_type~ : Bool = false,
  alphanumeric_only_refs~ : Bool = false,
) -> Config {
  {
    map_strategy,
    union_strategy,
    enum_strategy,
    use_json_name,
    default_timestamp_format,
    support_non_numeric_floats,
    schema_document_extensions,
    definition_pointer,
    add_reference_descriptions,
    disable_default_values,
    disable_int_enums,
    use_integer_type,
    alphanumeric_only_refs,
  }
}
