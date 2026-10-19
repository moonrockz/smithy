///|
fn member_target(entry : Json) -> String? {
  guard entry is Object(fields) && fields.get("target") is Some(String(id)) else {
    return None
  }
  Some(id)
}

///|
fn type_schema(kind : String) -> Json {
  let fields : Map[String, Json] = Map([])
  match kind {
    "string" | "blob" | "timestamp" => fields["type"] = Json::string("string")
    "boolean" => fields["type"] = Json::string("boolean")
    "byte"
    | "short"
    | "integer"
    | "long"
    | "float"
    | "double"
    | "bigInteger"
    | "bigDecimal" => fields["type"] = Json::string("number")
    "list" => fields["type"] = Json::string("array")
    "map" | "structure" => fields["type"] = Json::string("object")
    "enum" => fields["type"] = Json::string("string")
    "intEnum" => fields["type"] = Json::string("number")
    _ => ()
  }
  Json::object(fields)
}

///|
fn target_schema(
  target : String,
  shapes : Map[String, Json],
  active : Array[String],
) -> Json {
  if target.has_prefix("smithy.api#") {
    let parts = target.split("#").to_array()
    let kind = if parts.length() == 2 { parts[1].to_owned() } else { "" }
    let keyword = match kind {
      "String" => "string"
      "Blob" => "blob"
      "Boolean" => "boolean"
      "Byte" => "byte"
      "Short" => "short"
      "Integer" => "integer"
      "Long" => "long"
      "Float" => "float"
      "Double" => "double"
      "BigInteger" => "bigInteger"
      "BigDecimal" => "bigDecimal"
      "Timestamp" => "timestamp"
      _ => "document"
    }
    return type_schema(keyword)
  }
  if shapes.get(target) is Some(shape) {
    if !active.contains(target) &&
      shape is Object(body) &&
      body.get("type") is Some(String(kind)) &&
      (
        kind == "list" ||
        kind == "string" ||
        kind == "blob" ||
        kind == "boolean" ||
        kind == "byte" ||
        kind == "short" ||
        kind == "integer" ||
        kind == "long" ||
        kind == "float" ||
        kind == "double" ||
        kind == "bigInteger" ||
        kind == "bigDecimal" ||
        kind == "timestamp" ||
        kind == "document"
      ) {
      return shape_schema(shape, shapes, active + [target])
    }
    let parts = target.split("#").to_array()
    let name = if parts.length() == 2 { parts[1].to_owned() } else { target }
    return Json::object({ "$ref": Json::string("#/definitions/" + name) })
  }
  Json::object(Map([]))
}

///|
fn shape_schema(
  shape : Json,
  shapes : Map[String, Json],
  active : Array[String],
) -> Json {
  guard shape is Object(fields) && fields.get("type") is Some(String(kind)) else {
    return Json::object(Map([]))
  }
  let schema = match type_schema(kind) {
    Object(fields) => fields
    _ => Map([])
  }
  if (kind == "enum" || kind == "intEnum") &&
    fields.get("members") is Some(Object(members)) {
    let values : Array[Json] = []
    for name, entry in members {
      let value = match entry {
        Object(entry_fields) =>
          match entry_fields.get("traits") {
            Some(Object(traits)) =>
              traits.get("smithy.api#enumValue").unwrap_or(Json::string(name))
            _ => Json::string(name)
          }
        _ => Json::string(name)
      }
      values.push(value)
    }
    schema["enum"] = Json::array(values)
  }
  if fields.get("traits") is Some(Object(traits)) &&
    traits.get("smithy.api#documentation") is Some(description) {
    schema["description"] = description
  }
  if kind == "list" &&
    fields.get("member") is Some(entry) &&
    member_target(entry) is Some(target) {
    schema["items"] = target_schema(target, shapes, active)
  }
  if kind == "structure" && fields.get("members") is Some(Object(members)) {
    let properties : Map[String, Json] = Map([])
    for name, entry in members {
      if member_target(entry) is Some(target) {
        properties[name] = target_schema(target, shapes, active)
      }
    }
    schema["properties"] = Json::object(properties)
  }
  Json::object(schema)
}

///|
fn connected_shapes(
  service : String,
  shapes : Map[String, Json],
) -> Map[String, Bool] {
  let seen : Map[String, Bool] = Map([])
  let pending = [service]
  while !pending.is_empty() {
    let id = pending.pop().unwrap()
    if seen.get(id) is Some(_) {
      continue
    }
    guard shapes.get(id) is Some(shape) else { continue }
    seen[id] = true
    let nodes = [shape]
    while !nodes.is_empty() {
      let node = nodes.pop().unwrap()
      match node {
        Object(fields) => {
          if fields.get("target") is Some(String(target)) &&
            shapes.get(target) is Some(_) {
            pending.push(target)
          }
          for key, value in fields {
            if key != "traits" && key != "rename" {
              nodes.push(value)
            }
          }
        }
        Array(values) =>
          for value in values {
            nodes.push(value)
          }
        _ => ()
      }
    }
  }
  seen
}

///|
/// Convert value shapes in an assembled model to a JSON Schema document.
pub fn convert(model : @smithy.Model, service~ : String = "") -> Json raise {
  let ast = @syntax.encode_json_ast(model.to_json_ast())
  guard ast is Object(fields) && fields.get("shapes") is Some(Object(shapes)) else {
    return Json::object(Map([]))
  }
  let definitions : Map[String, Json] = Map([])
  let connected = connected_shapes(service, shapes)
  for id, shape in shapes {
    if service != "" && connected.get(id) is None {
      continue
    }
    guard shape is Object(body) && body.get("type") is Some(String(kind)) else {
      continue
    }
    if kind == "service" || kind == "resource" || kind == "operation" {
      continue
    }
    let parts = id.split("#").to_array()
    guard parts.length() == 2 else { continue }
    definitions[parts[1].to_owned()] = shape_schema(shape, shapes, [id])
  }
  Json::object({ "definitions": Json::object(definitions) })
}
