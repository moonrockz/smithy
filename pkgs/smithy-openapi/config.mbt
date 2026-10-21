///|
/// Settings for one service conversion. Service and protocol IDs, version and
/// omission policy are validated before conversion begins.
pub struct Config {
  service : ServiceId
  protocol : ProtocolId?
  version : OpenApiVersion
  prefix_headers : PrefixHeadersPolicy
  forbid_greedy_labels : Bool
  remove_greedy_parameter_suffix : Bool
  ignore_unsupported_traits : Bool
  tags : Bool
  supported_tags : Array[String]?
  keep_unused_components : Bool
  json_content_type : String
  default_blob_format : String
  external_docs : Array[String]
  disable_integer_format : Bool
  alphanumeric_only_refs : Bool
  use_strings_for_arbitrary_precision : Bool
  combine_error_responses : Bool
  schema : @jsonschema.Config
  substitutions : Map[String, Json]
  json_add : Map[String, Json]
}

///|
pub fn Config::new(
  service : ServiceId,
  protocol~ : ProtocolId? = None,
  version~ : OpenApiVersion = V3_0_2,
  prefix_headers~ : PrefixHeadersPolicy = Fail,
  forbid_greedy_labels~ : Bool = false,
  remove_greedy_parameter_suffix~ : Bool = false,
  ignore_unsupported_traits~ : Bool = false,
  tags~ : Bool = false,
  supported_tags~ : Array[String]? = None,
  keep_unused_components~ : Bool = false,
  json_content_type~ : String = "application/json",
  default_blob_format~ : String = "byte",
  external_docs~ : Array[String] = [
    "Homepage", "API Reference", "User Guide", "Developer Guide", "Reference", "Guide",
  ],
  disable_integer_format~ : Bool = false,
  alphanumeric_only_refs~ : Bool = false,
  use_strings_for_arbitrary_precision~ : Bool = false,
  combine_error_responses~ : Bool = false,
  schema~ : @jsonschema.Config = @jsonschema.Config::new(),
  substitutions~ : Map[String, Json] = Map([]),
  json_add~ : Map[String, Json] = Map([]),
) -> Config {
  {
    service,
    protocol,
    version,
    prefix_headers,
    forbid_greedy_labels,
    remove_greedy_parameter_suffix,
    ignore_unsupported_traits,
    tags,
    supported_tags,
    keep_unused_components,
    json_content_type,
    default_blob_format,
    external_docs,
    disable_integer_format,
    alphanumeric_only_refs,
    use_strings_for_arbitrary_precision,
    combine_error_responses,
    schema,
    substitutions,
    json_add,
  }
}

///|
pub fn Config::service(self : Config) -> ServiceId {
  self.service
}

///|
pub fn Config::version(self : Config) -> OpenApiVersion {
  self.version
}

///|
fn setting_string(
  fields : Map[String, Json],
  key : String,
  fallback : String,
) -> String raise OpenApiError {
  match fields.get(key) {
    None => fallback
    Some(String(value)) => value
    _ =>
      raise InvalidConfiguration(
        "OpenAPI setting `" + key + "` must be a string",
      )
  }
}

///|
fn setting_bool(
  fields : Map[String, Json],
  key : String,
) -> Bool raise OpenApiError {
  match fields.get(key) {
    None | Some(False) => false
    Some(True) => true
    _ =>
      raise InvalidConfiguration(
        "OpenAPI setting `" + key + "` must be a boolean",
      )
  }
}

///|
fn setting_strings(
  fields : Map[String, Json],
  key : String,
  fallback : Array[String],
) -> Array[String] raise OpenApiError {
  match fields.get(key) {
    None => fallback
    Some(Array(values)) => {
      let out : Array[String] = []
      for value in values {
        guard value is String(text) else {
          raise InvalidConfiguration(
            "OpenAPI setting `" + key + "` must contain strings",
          )
        }
        out.push(text)
      }
      out
    }
    _ =>
      raise InvalidConfiguration(
        "OpenAPI setting `" + key + "` must be an array",
      )
  }
}

///|
fn setting_object(
  fields : Map[String, Json],
  key : String,
) -> Map[String, Json] raise OpenApiError {
  match fields.get(key) {
    None => Map([])
    Some(Object(values)) => values
    _ =>
      raise InvalidConfiguration(
        "OpenAPI setting `" + key + "` must be an object",
      )
  }
}

///|
/// Parse the settings of the `openapi` build plugin. This performs no I/O.
pub fn Config::from_json(settings : Json) -> Config raise OpenApiError {
  guard settings is Object(fields) else {
    raise InvalidConfiguration("OpenAPI settings must be an object")
  }
  let service_text = setting_string(fields, "service", "")
  guard ServiceId::parse(service_text) is Some(service) else {
    raise InvalidConfiguration(
      "OpenAPI requires a valid root `service` shape ID",
    )
  }
  let protocol = match fields.get("protocol") {
    None => None
    Some(String(value)) => {
      guard ProtocolId::parse(value) is Some(id) else {
        raise InvalidConfiguration(
          "OpenAPI requires a valid root `protocol` trait ID",
        )
      }
      Some(id)
    }
    _ =>
      raise InvalidConfiguration("OpenAPI setting `protocol` must be a string")
  }
  guard OpenApiVersion::parse(setting_string(fields, "version", "3.0.2"))
    is Some(version) else {
    raise InvalidConfiguration("OpenAPI supports versions 3.0.2 and 3.1.0")
  }
  let prefix_headers = match
    setting_string(fields, "onHttpPrefixHeaders", "FAIL") {
    "FAIL" => Fail
    "WARN" => Warn
    _ => raise InvalidConfiguration("onHttpPrefixHeaders must be FAIL or WARN")
  }
  let combine_error_responses = match fields.get("onErrorStatusConflict") {
    None => false
    Some(String("oneOf")) => true
    _ => raise InvalidConfiguration("onErrorStatusConflict must be oneOf")
  }
  let schema = @jsonschema.Config::new(
    map_strategy=setting_string(fields, "mapStrategy", "propertyNames"),
    union_strategy=setting_string(fields, "unionStrategy", "oneOf"),
    enum_strategy=setting_string(fields, "enumStrategy", "enum"),
    use_json_name=setting_bool(fields, "useJsonName"),
    default_timestamp_format=setting_string(
      fields, "defaultTimestampFormat", "date-time",
    ),
    support_non_numeric_floats=setting_bool(fields, "supportNonNumericFloats"),
    schema_document_extensions=Json::object(
      setting_object(fields, "schemaDocumentExtensions"),
    ),
    definition_pointer="#/components/schemas",
    add_reference_descriptions=setting_bool(fields, "addReferenceDescriptions"),
    disable_default_values=setting_bool(fields, "disableDefaultValues"),
    disable_int_enums=setting_bool(fields, "disableIntEnums"),
    use_integer_type=setting_bool(fields, "useIntegerType"),
  )
  Config::new(
    service,
    protocol~,
    version~,
    prefix_headers~,
    schema~,
    forbid_greedy_labels=setting_bool(fields, "forbidGreedyLabels"),
    remove_greedy_parameter_suffix=setting_bool(
      fields, "removeGreedyParameterSuffix",
    ),
    ignore_unsupported_traits=setting_bool(fields, "ignoreUnsupportedTraits"),
    tags=setting_bool(fields, "tags"),
    supported_tags=if fields.contains("supportedTags") {
      Some(setting_strings(fields, "supportedTags", []))
    } else {
      None
    },
    keep_unused_components=setting_bool(fields, "keepUnusedComponents"),
    json_content_type=setting_string(
      fields, "jsonContentType", "application/json",
    ),
    default_blob_format=setting_string(fields, "defaultBlobFormat", "byte"),
    external_docs=setting_strings(fields, "externalDocs", [
      "Homepage", "API Reference", "User Guide", "Developer Guide", "Reference",
      "Guide",
    ]),
    disable_integer_format=setting_bool(fields, "disableIntegerFormat"),
    alphanumeric_only_refs=setting_bool(fields, "alphanumericOnlyRefs"),
    use_strings_for_arbitrary_precision=setting_bool(
      fields, "useStringsForArbitraryPrecision",
    ),
    combine_error_responses~,
    substitutions=setting_object(fields, "substitutions"),
    json_add=setting_object(fields, "jsonAdd"),
  )
}
