///|
fn found(value : Json) -> String {
  match value {
    Null => "null"
    True | False => "a boolean"
    Number(_, ..) => "a number"
    String(s) => Json::string(s).stringify()
    Array(_) => "an array"
    Object(_) => "an object"
  }
}

///|
fn[T] invalid(
  path : @json.JsonPath,
  message : String,
) -> T raise @json.JsonDecodeError {
  raise @json.JsonDecodeError((path, message))
}

///|
fn object_value(
  value : Json,
  path : @json.JsonPath,
) -> Map[String, Json] raise @json.JsonDecodeError {
  guard value is Object(fields) else {
    invalid(path, "I expected a JSON AST object, but found \{found(value)}.")
  }
  fields
}

///|
fn check_fields(
  fields : Map[String, Json],
  allowed : ArrayView[String],
  path : @json.JsonPath,
) -> Unit raise @json.JsonDecodeError {
  for key, _ in fields {
    if !allowed.contains(key) {
      invalid(
        path.add_key(key),
        "I found the unknown JSON AST property \{Json::string(key).stringify()}.",
      )
    }
  }
}

///|
fn[T : @json.FromJson] required(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
) -> T raise @json.JsonDecodeError {
  let path = path.add_key(key)
  guard fields.get(key) is Some(value) else {
    invalid(
      path,
      "I expected the JSON AST property \{Json::string(key).stringify()}, but found no property.",
    )
  }
  @json.from_json(value, path~)
}

///|
/// Explicit null is not absence: decode the inner type rather than Option.
fn[T : @json.FromJson] optional(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
) -> T? raise @json.JsonDecodeError {
  match fields.get(key) {
    None => None
    Some(value) => Some(@json.from_json(value, path=path.add_key(key)))
  }
}

///|
fn identifier(text : String) -> Bool {
  let mut first = true
  for c in text.iter() {
    let alpha = c == '_' || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
    if !alpha && (first || c < '0' || c > '9') {
      return false
    }
    first = false
  }
  !first
}

///|
fn absolute_id(
  text : String,
  path : @json.JsonPath,
) -> Unit raise @json.JsonDecodeError {
  let parts = text.split("#").to_array()
  let valid = if parts.length() != 2 {
    false
  } else {
    let names = parts[1].split("$").to_array()
    parts[0].split(".").all(s => identifier(s.to_owned())) &&
    names.length() <= 2 &&
    names.iter().all(s => identifier(s.to_owned()))
  }
  if !valid {
    invalid(
      path,
      "I expected an absolute JSON AST shape ID, but found \{Json::string(text).stringify()}.",
    )
  }
}

///|
fn[T] check_ids(
  values : Map[String, T]?,
  path : @json.JsonPath,
) -> Unit raise @json.JsonDecodeError {
  if values is Some(values) {
    for key, _ in values {
      absolute_id(key, path.add_key(key))
    }
  }
}

///|
fn traits(
  fields : Map[String, Json],
  path : @json.JsonPath,
) -> Map[String, Json]? raise @json.JsonDecodeError {
  let values = optional(fields, "traits", path)
  check_ids(values, path.add_key("traits"))
  values
}

///|
fn members(
  fields : Map[String, Json],
  path : @json.JsonPath,
) -> Map[String, JsonMember]? raise @json.JsonDecodeError {
  let values : Map[String, JsonMember]? = optional(fields, "members", path)
  if values is Some(values) {
    for name, _ in values {
      if !identifier(name) {
        invalid(
          path.add_key("members").add_key(name),
          "I expected a JSON AST member name, but found \{Json::string(name).stringify()}.",
        )
      }
    }
  }
  values
}

///|
pub impl @json.FromJson for JsonAst with fn from_json(value, path) {
  let fields = object_value(value, path)
  check_fields(fields, ["smithy", "metadata", "shapes"], path)
  let smithy = required(fields, "smithy", path)
  let metadata = optional(fields, "metadata", path)
  let shapes = optional(fields, "shapes", path)
  check_ids(shapes, path.add_key("shapes"))
  { smithy, metadata, shapes, }
}

///|
pub impl @json.FromJson for JsonReference with fn from_json(value, path) {
  let fields = object_value(value, path)
  check_fields(fields, ["target"], path)
  let target = required(fields, "target", path)
  absolute_id(target, path.add_key("target"))
  { target, }
}

///|
pub impl @json.FromJson for JsonMember with fn from_json(value, path) {
  let fields = object_value(value, path)
  check_fields(fields, ["target", "traits"], path)
  let target = required(fields, "target", path)
  absolute_id(target, path.add_key("target"))
  { target, traits: traits(fields, path), }
}

///|
pub impl @json.FromJson for JsonShape with fn from_json(value, path) {
  let fields = object_value(value, path)
  let type_ : String = required(fields, "type", path)
  let common : Array[String] = if type_ == "apply" {
    ["type", "traits"]
  } else {
    ["type", "traits", "mixins"]
  }
  let extra : Array[String] = match type_ {
    "list" | "set" => ["member"]
    "map" => ["key", "value"]
    "structure" | "union" | "enum" | "intEnum" => ["members"]
    "operation" => ["input", "output", "errors"]
    "service" => ["version", "operations", "resources", "errors", "rename"]
    "resource" =>
      [
        "identifiers", "properties", "create", "put", "read", "update", "delete",
        "list", "operations", "collectionOperations", "resources",
      ]
    "apply" => []
    _ => {
      if @ast.SimpleType::of(type_) is None {
        invalid(
          path.add_key("type"),
          "I expected a JSON AST shape type, but found \{Json::string(type_).stringify()}.",
        )
      }
      []
    }
  }
  common.append(extra)
  check_fields(fields, common[:], path)
  let kind : JsonShapeKind = match type_ {
    "list" => List(optional(fields, "member", path))
    "set" => Set(optional(fields, "member", path))
    "map" =>
      Map(
        key=optional(fields, "key", path),
        value=optional(fields, "value", path),
      )
    "structure" => Structure(members(fields, path))
    "union" => Union(members(fields, path))
    "enum" => Enum(members(fields, path))
    "intEnum" => IntEnum(members(fields, path))
    "operation" => Operation(decode_operation(fields, path))
    "service" => Service(decode_service(fields, path))
    "resource" => Resource(decode_resource(fields, path))
    "apply" => Apply
    _ =>
      match @ast.SimpleType::of(type_) {
        Some(t) => Simple(t)
        None =>
          invalid(
            path.add_key("type"),
            "I found an unknown JSON AST shape type.",
          )
      }
  }
  {
    kind,
    traits: traits(fields, path),
    mixins: optional(fields, "mixins", path),
  }
}

///|
fn decode_operation(
  fields : Map[String, Json],
  path : @json.JsonPath,
) -> JsonOperation raise @json.JsonDecodeError {
  {
    input: optional(fields, "input", path),
    output: optional(fields, "output", path),
    errors: optional(fields, "errors", path),
  }
}

///|
fn decode_service(
  fields : Map[String, Json],
  path : @json.JsonPath,
) -> JsonService raise @json.JsonDecodeError {
  let rename : Map[String, String]? = optional(fields, "rename", path)
  check_ids(rename, path.add_key("rename"))
  if rename is Some(rename) {
    for id, name in rename {
      if !identifier(name) {
        invalid(
          path.add_key("rename").add_key(id),
          "I expected a JSON AST service rename identifier, but found \{Json::string(name).stringify()}.",
        )
      }
    }
  }
  {
    version: optional(fields, "version", path),
    operations: optional(fields, "operations", path),
    resources: optional(fields, "resources", path),
    errors: optional(fields, "errors", path),
    rename,
  }
}

///|
fn decode_resource(
  fields : Map[String, Json],
  path : @json.JsonPath,
) -> JsonResource raise @json.JsonDecodeError {
  {
    identifiers: optional(fields, "identifiers", path),
    properties: optional(fields, "properties", path),
    create: optional(fields, "create", path),
    put: optional(fields, "put", path),
    read: optional(fields, "read", path),
    update: optional(fields, "update", path),
    delete: optional(fields, "delete", path),
    list: optional(fields, "list", path),
    operations: optional(fields, "operations", path),
    collectionOperations: optional(fields, "collectionOperations", path),
    resources: optional(fields, "resources", path),
  }
}

///|
/// Decode a core JSON value. Errors carry a JSON Pointer to the bad field.
pub fn decode(value : Json) -> JsonAst raise @json.JsonDecodeError {
  @json.from_json(value)
}

///|
/// Parse JSON text and decode its document. JSON syntax errors and AST
/// structure errors retain their standard core error types. The JSON parser
/// bounds nesting before decoding; this codec does not recurse through values.
pub fn parse(text : String) -> JsonAst raise {
  decode(parse_exact(text))
}
