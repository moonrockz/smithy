///|
fn value_blob_contract(
  schema : Map[String, Json],
  traits : Map[String, Json],
) -> Unit {
  // Smithy length measures decoded bytes. Applying string minLength/maxLength
  // would reject valid base64, so retain byte bounds explicitly as metadata.
  schema.remove("minLength") |> ignore
  schema.remove("maxLength") |> ignore
  schema["contentEncoding"] = Json::string("base64")
  schema["pattern"] = Json::string(
    "^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}[AEIMQUYcgkosw048]=|[A-Za-z0-9+/][AQgw]==)?(?![\\s\\S])",
  )
  if traits.get("smithy.api#length") is Some(length) {
    schema["x-smithy-byteLength"] = length
  }
}

///|
fn value_overrides(traits : Map[String, Json]) -> Bool {
  [
    "smithy.api#range", "smithy.api#length", "smithy.api#pattern", "smithy.api#enum",
    "smithy.api#uniqueItems", "smithy.api#timestampFormat",
  ]
  .iter()
  .any(key => traits.contains(key))
}

///|
fn value_member_id(active : Array[String], name : String) -> String {
  active.last().unwrap_or("") + "$" + name
}

///|
fn value_member_entries(shapes : Map[String, Json]) -> Array[(String, Json)] {
  let entries = []
  for id, shape in shapes {
    guard shape is Object(fields) else { continue }
    if fields.get("members") is Some(Object(members)) {
      for name, entry in members {
        if member_target(entry) is Some(_) {
          entries.push((id + "$" + name, entry))
        }
      }
    } else {
      for name in ["key", "value", "member"] {
        if fields.get(name) is Some(entry) && member_target(entry) is Some(_) {
          entries.push((id + "$" + name, entry))
        }
      }
    }
  }
  entries.sort_by((a, b) => a.0.lexical_compare(b.0))
  entries
}

///|
/// Give constrained member variants their own definitions so recursion never
/// expands a member contract on the call stack. Allocate against every root
/// name, including user names that resemble a generated variant.
fn value_member_names(
  shapes : Map[String, Json],
  connected : Map[String, Bool],
  names : Map[String, String],
  service : String,
) -> Unit {
  let used : Set[String] = Set([])
  for _, name in names {
    used.add(name)
  }
  for (id, entry) in value_member_entries(shapes) {
    let root = id.split("$").next().unwrap().to_owned()
    if service != "" && !connected.contains(root) {
      continue
    }
    guard entry is { "traits": Object(traits), .. } &&
      value_overrides(traits) &&
      member_target(entry) is Some(target) &&
      shapes.contains(target) else {
      continue
    }
    let base = names.get(root).unwrap_or(root) +
      "_" +
      id.split("$").to_array()[1].to_owned()
    let mut name = base
    let mut suffix = 2
    while used.contains(name) {
      name = base + "_" + suffix.to_string()
      suffix += 1
    }
    names[id] = name
    used.add(name)
  }
}

///|
/// Optional value-contract semantics. The reference-compatible converter keeps
/// its historical defaults unless a protocol exporter explicitly opts in.
fn value_numeric_bounds(schema : Map[String, Json], kind : String) -> Unit {
  let bounds = match kind {
    "byte" => Some(("-128", "127"))
    "short" => Some(("-32768", "32767"))
    "integer" => Some(("-2147483648", "2147483647"))
    "long" => Some(("-9223372036854775808", "9223372036854775807"))
    "float" =>
      Some(
        (
          "-340282346638528859811704183484516925440", "340282346638528859811704183484516925440",
        ),
      )
    "double" =>
      Some(
        (
          "-179769313486231570814527423731704356798070567525844996598917476803157260780028538760589558632766878171540458953514382464234321326889464182768467546703537516986049910576551282076245490090389328944075868508455133942304583236903222948165808559332123348274797826204144723168738177180919299881250404026184124858368",
          "179769313486231570814527423731704356798070567525844996598917476803157260780028538760589558632766878171540458953514382464182768467546703537516986049910576551282076245490090389328944075868508455133942304583236903222948165808559332123348274797826204144723168738177180919299881250404026184124858368",
        ),
      )
    _ => None
  }
  if ["byte", "short", "integer", "long", "bigInteger", "intEnum"].contains(
      kind,
    ) {
    schema["type"] = Json::string("integer")
  }
  if bounds is Some((minimum, maximum)) {
    for
      (key, text, lower) in [
        ("minimum", minimum, true),
        ("maximum", maximum, false),
      ] {
      let bound = @smithy.NodeNumber::parse(text).unwrap()
      let current = schema
        .get(key)
        .bind(value => @smithy.NodeNumber::parse(value.stringify()))
      if current is None ||
        (
          current is Some(value) &&
          (if lower {
            value.numeric_compare(bound) < 0
          } else {
            value.numeric_compare(bound) > 0
          })
        ) {
        schema[key] = bound.to_json()
      }
    }
  }
}

///|
fn value_collection_contract(
  schema : Map[String, Json],
  shape : Json,
  kind : String,
) -> Unit {
  if kind == "structure" || kind == "union" {
    schema["additionalProperties"] = Json::boolean(false)
    if schema.get("properties") is None {
      schema["properties"] = Json::object(Map([]))
    }
  }
  if kind == "union" {
    schema["type"] = Json::string("object")
    schema["minProperties"] = Json::number(1)
    schema["maxProperties"] = Json::number(1)
    // oneOf branches describe cardinality; the outer property table supplies
    // the complete allowed member set for additionalProperties:false.
    let properties : Map[String, Json] = Map([])
    if schema.get("oneOf") is Some(Array(options)) {
      for option in options {
        if option is { "properties": Object(entries), .. } {
          for name, value in entries {
            properties[name] = value
          }
        }
      }
    }
    schema["properties"] = Json::object(properties)
  }
  if shape is { "traits": { "smithy.api#sparse": _, .. }, .. } {
    let keyword = if kind == "list" { "items" } else { "additionalProperties" }
    if schema.get(keyword) is Some(value) {
      schema[keyword] = Json::object({
        "anyOf": Json::array([
          value,
          Json::object({ "type": Json::string("null") }),
        ]),
      })
    }
  }
}

///|
fn value_prelude_kind(target : String) -> String {
  match target {
    "smithy.api#String" => "string"
    "smithy.api#Blob" => "blob"
    "smithy.api#Boolean" | "smithy.api#PrimitiveBoolean" => "boolean"
    "smithy.api#Byte" | "smithy.api#PrimitiveByte" => "byte"
    "smithy.api#Short" | "smithy.api#PrimitiveShort" => "short"
    "smithy.api#Integer" | "smithy.api#PrimitiveInteger" => "integer"
    "smithy.api#Long" | "smithy.api#PrimitiveLong" => "long"
    "smithy.api#Float" | "smithy.api#PrimitiveFloat" => "float"
    "smithy.api#Double" | "smithy.api#PrimitiveDouble" => "double"
    "smithy.api#BigInteger" => "bigInteger"
    "smithy.api#BigDecimal" => "bigDecimal"
    "smithy.api#Timestamp" => "timestamp"
    _ => "document"
  }
}
