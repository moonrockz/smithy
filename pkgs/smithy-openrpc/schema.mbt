///|
fn schema_policy(
  schema : Json,
  subject : @smithy.ShapeId,
  config : Config,
  warnings : Array[ConversionWarning],
) -> Unit raise OpenRpcError {
  let pending = [schema]
  while pending.pop() is Some(node) {
    match node {
      Object(entries) => {
        let limitations : Array[(String, String)] = []
        if entries.contains("x-smithy-byteLength") {
          limitations.push(
            (
              "x-smithy-byteLength", "I cannot encode decoded blob byte lengths with standard string length keywords; x-smithy-byteLength records that contract.",
            ),
          )
        }
        if entries.get("format") == Some(Json::string("date-time")) {
          entries["x-smithy-timestamp-policy"] = Json::string(
            "recorded-leap-seconds",
          )
          limitations.push(
            (
              "x-smithy-timestamp-policy", "I cannot encode the recorded leap-second policy with generic date-time validation; x-smithy-timestamp-policy names that runtime policy.",
            ),
          )
        }
        for (key, message) in limitations {
          if config.extensions == Fail {
            raise UnsupportedMapping(
              subject,
              message + " Use extensions=preserve.",
            )
          }
          if config.extensions == Omit {
            entries.remove(key) |> ignore
          }
          if !warnings
            .iter()
            .any(w => w.shape == subject && w.message == message) {
            warnings.push({ code: SchemaLimitation, shape: subject, message, })
          }
        }
        pending.append(schema_children(entries))
      }
      Array(values) => pending.append(values)
      _ => ()
    }
  }
}

///|
/// Schema keywords distinguish schemas from property-name dictionaries and
/// literal data. A property can have any name, including a schema keyword.
fn schema_children(entries : Map[String, Json]) -> Array[Json] {
  let children : Array[Json] = []
  for key in ["properties", "patternProperties", "definitions", "$defs"] {
    if entries.get(key) is Some(Object(schemas)) {
      for _, schema in schemas {
        children.push(schema)
      }
    }
  }
  for
    key in [
      "additionalProperties", "additionalItems", "contains", "not", "if", "then",
      "else", "propertyNames", "items",
    ] {
    if entries.get(key) is Some(schema) {
      children.push(schema)
    }
  }
  for key in ["allOf", "anyOf", "oneOf"] {
    if entries.get(key) is Some(Array(schemas)) {
      children.append(schemas)
    }
  }
  if entries.get("dependencies") is Some(Object(dependencies)) {
    for _, schema in dependencies {
      if schema is Object(_) || schema is False || schema is True {
        children.push(schema)
      }
    }
  }
  children
}

///|
fn fields(value : Json) -> Map[String, Json] {
  match value {
    Object(fields) => fields
    _ => Map([])
  }
}

///|
fn trait_text(shape : @smithy.Shape, name : String) -> String? {
  match shape.trait_value(name) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn member_name(shape : @smithy.Shape, config : Config) -> String {
  let name = shape.id.member_name().unwrap()
  if config.member_names == @validation.JsonName {
    trait_text(shape, "smithy.api#jsonName").unwrap_or(name)
  } else {
    name
  }
}

///|
fn value_schema(
  index : @jsonschema.SchemaIndex,
  id : @smithy.ShapeId,
  config : Config,
  warnings : Array[ConversionWarning],
) -> Json raise OpenRpcError {
  let schema = try {
    if id.member_name() is Some(_) {
      index.schema_for_member(id)
    } else {
      index.shape(id)
    }
  } catch {
    @jsonschema.ConflictingShapeName(message)
    | @jsonschema.InvalidConfiguration(message) =>
      raise SchemaConversion(id, message)
  }
  schema_policy(schema, id, config, warnings)
  schema
}

///|
fn descriptor(
  model : @smithy.Model,
  index : @jsonschema.SchemaIndex,
  id : @smithy.ShapeId,
  name : String,
  required : Bool,
  config : Config,
  warnings : Array[ConversionWarning],
) -> Json raise OpenRpcError {
  if name.is_empty() {
    raise UnsupportedMapping(
      id, "I cannot export an empty OpenRPC content descriptor name; use a nonempty jsonName or select Smithy member naming.",
    )
  }
  let out : Map[String, Json] = {
    "name": Json::string(name),
    "required": Json::boolean(required),
    "schema": value_schema(index, id, config, warnings),
  }
  if model.shapes.get(id) is Some(shape) {
    if trait_text(shape, "smithy.api#documentation") is Some(text) {
      out["description"] = Json::string(text)
    }
    if shape.trait_value("smithy.api#deprecated") is Some(_) {
      out["deprecated"] = Json::boolean(true)
    }
  }
  Json::object(out)
}

///|
/// Traverse generated value schemas. Defaults and literal schema examples are
/// disabled in this profile; method examples are selected separately as data.
fn collect_refs(value : Json) -> Array[String] {
  let pending = [value]
  let refs : Array[String] = []
  while pending.pop() is Some(node) {
    match node {
      Object(entries) => {
        if entries.get("$ref") is Some(String(reference)) {
          refs.push(reference)
        }
        pending.append(schema_children(entries))
      }
      Array(values) => pending.append(values)
      _ => ()
    }
  }
  refs
}

///|
fn used_schemas(
  index : @jsonschema.SchemaIndex,
  methods : Array[Json],
  service : @smithy.ShapeId,
) -> Map[String, Json] raise OpenRpcError {
  let available = fields(
    fields(fields(index.document()).get("components").unwrap_or(Json::null()))
    .get("schemas")
    .unwrap_or(Json::null()),
  )
  let selected : Map[String, Json] = Map([])
  let roots : Array[Json] = []
  for method_ in methods {
    let method_ = fields(method_)
    if method_.get("params") is Some(Array(params)) {
      for param in params {
        if fields(param).get("schema") is Some(schema) {
          roots.push(schema)
        }
      }
    }
    if method_.get("result") is Some(result) &&
      fields(result).get("schema") is Some(schema) {
      roots.push(schema)
    }
    if method_.get("x-smithy-error-data") is Some(Array(errors)) {
      for error in errors {
        if fields(error).get("schema") is Some(schema) {
          roots.push(schema)
        }
      }
    }
  }
  let pending = collect_refs(Json::array(roots))
  let prefix = "#/components/schemas/"
  while pending.pop() is Some(reference) {
    guard reference.has_prefix(prefix) else {
      raise SchemaConversion(
        service,
        "I found unsupported schema reference `" + reference + "`.",
      )
    }
    let name = reference[prefix.length():].to_owned()
    if selected.contains(name) {
      continue
    }
    guard available.get(name) is Some(schema) else {
      raise SchemaConversion(
        service,
        "I could not resolve schema reference `" + reference + "`.",
      )
    }
    selected[name] = schema
    pending.append(collect_refs(schema))
  }
  selected
}
