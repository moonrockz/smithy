///|
pub(all) suberror JsonSchemaError {
  ConflictingShapeName(String)
  InvalidConfiguration(String)
} derive(Debug)

///|
fn member_target(entry : Json) -> String? {
  guard entry is Object(fields) && fields.get("target") is Some(String(id)) else {
    return None
  }
  Some(id)
}

///|
fn property_name(
  name : String,
  entry : Json,
  config : ConversionConfig,
) -> String {
  if config.settings.use_json_name &&
    entry is Object(fields) &&
    fields.get("traits") is Some(Object(traits)) &&
    traits.get("smithy.api#jsonName") is Some(String(value)) {
    value
  } else {
    name
  }
}

///|
fn schema_description(traits : Map[String, Json]) -> Json? {
  let mut description = match traits.get("smithy.api#documentation") {
    Some(String(text)) => text
    _ => ""
  }
  if traits.get("smithy.api#deprecated") is Some(Object(deprecated)) {
    let since = match deprecated.get("since") {
      Some(String(text)) => " since " + text
      _ => ""
    }
    let message = match deprecated.get("message") {
      Some(String(text)) => ": " + text
      _ => "."
    }
    description += "\nThis shape is deprecated" + since + message
  }
  let description = description.trim().to_owned()
  if description.is_empty() {
    None
  } else {
    Some(Json::string(description))
  }
}

///|
fn apply_traits(
  schema : Map[String, Json],
  traits : Map[String, Json],
  kind : String,
  config : ConversionConfig,
) -> Unit {
  for
    (trait_id, keyword) in [
      ("smithy.api#title", "title"),
      ("smithy.api#pattern", "pattern"),
      ("smithy.api#mediaType", "contentMediaType"),
    ] {
    if traits.get(trait_id) is Some(value) {
      schema[keyword] = value
    }
  }
  if schema_description(traits) is Some(description) {
    schema["description"] = description
  }
  if traits.get("smithy.api#length") is Some(Object(length)) {
    let prefix = if kind == "list" {
      "Items"
    } else if kind == "map" {
      "Properties"
    } else {
      "Length"
    }
    for (bound, word) in [("min", "min"), ("max", "max")] {
      if length.get(bound) is Some(value) {
        schema[word + prefix] = value
      }
    }
  }
  if traits.get("smithy.api#range") is Some(Object(range)) {
    for (bound, word) in [("min", "minimum"), ("max", "maximum")] {
      if range.get(bound) is Some(value) {
        schema[word] = value
      }
    }
  }
  if traits.get("smithy.api#uniqueItems") is Some(_) {
    schema["uniqueItems"] = Json::boolean(true)
  }
  if !config.settings.disable_default_values &&
    traits.get("smithy.api#default") is Some(value) {
    schema["default"] = value
  }
  if kind == "string" && traits.get("smithy.api#enum") is Some(Array(entries)) {
    let values : Array[Json] = []
    for entry in entries {
      if entry is Object(fields) && fields.get("value") is Some(value) {
        values.push(value)
      }
    }
    schema["enum"] = Json::array(values)
  }
}

///|
fn type_schema(kind : String, config : ConversionConfig) -> Json {
  let fields : Map[String, Json] = Map([])
  match kind {
    "string" | "blob" | "timestamp" => fields["type"] = Json::string("string")
    "boolean" => fields["type"] = Json::string("boolean")
    "byte" | "short" | "integer" | "long" =>
      fields["type"] = Json::string(
        if config.settings.use_integer_type {
          "integer"
        } else {
          "number"
        },
      )
    "float" | "double" | "bigInteger" | "bigDecimal" =>
      fields["type"] = Json::string("number")
    "list" => fields["type"] = Json::string("array")
    "map" | "structure" => fields["type"] = Json::string("object")
    "enum" => fields["type"] = Json::string("string")
    "intEnum" => fields["type"] = Json::string("number")
    _ => ()
  }
  if config.value_contracts {
    value_numeric_bounds(fields, kind)
    if kind == "blob" {
      value_blob_contract(fields, Map([]))
    }
  }
  Json::object(fields)
}

///|
fn has_enum_trait(shape : Json) -> Bool {
  shape is Object(fields) &&
  fields.get("traits") is Some(Object(traits)) &&
  traits.get("smithy.api#enum") is Some(_)
}

///|
fn target_schema(
  target : String,
  shapes : Map[String, Json],
  active : Array[String],
  config : ConversionConfig,
  names : Map[String, String],
) -> Json {
  if target == "smithy.api#Unit" {
    return Json::object({
      "$ref": Json::string(config.settings.definition_pointer + "/Unit"),
    })
  }
  if target.has_prefix("smithy.api#") {
    let parts = target.split("#").to_array()
    let kind = if parts.length() == 2 { parts[1].to_owned() } else { "" }
    let keyword = if config.value_contracts {
      value_prelude_kind(target)
    } else {
      match kind {
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
    }
    if keyword == "timestamp" {
      if config.settings.default_timestamp_format == "date-time" {
        return Json::object({
          "type": Json::string("string"),
          "format": Json::string("date-time"),
        })
      }
      if config.settings.default_timestamp_format.has_prefix("epoch-") {
        return Json::object({ "type": Json::string("number") })
      }
    }
    if (keyword == "float" || keyword == "double") &&
      config.settings.support_non_numeric_floats {
      return Json::object({
        "oneOf": Json::array([
          Json::object({ "type": Json::string("number") }),
          Json::object({
            "type": Json::string("string"),
            "enum": Json::array([
              Json::string("NaN"),
              Json::string("Infinity"),
              Json::string("-Infinity"),
            ]),
          }),
        ]),
      })
    }
    return type_schema(keyword, config)
  }
  if shapes.get(target) is Some(shape) {
    if !config.value_contracts &&
      !active.contains(target) &&
      shape is Object(body) &&
      body.get("type") is Some(String(kind)) &&
      (
        kind == "list" ||
        (kind == "string" && !has_enum_trait(shape)) ||
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
        kind == "document" ||
        (kind == "intEnum" && config.settings.disable_int_enums)
      ) {
      return shape_schema(shape, shapes, active + [target], config, names)
    }
    let parts = target.split("#").to_array()
    let name = names
      .get(target)
      .unwrap_or(if parts.length() == 2 { parts[1].to_owned() } else { target })
    return Json::object({
      "$ref": Json::string(config.settings.definition_pointer + "/" + name),
    })
  }
  Json::object(Map([]))
}

///|
fn member_schema(
  entry : Json,
  shapes : Map[String, Json],
  active : Array[String],
  config : ConversionConfig,
  names : Map[String, String],
  member_id~ : String = "",
) -> Json {
  guard member_target(entry) is Some(target) else {
    return Json::object(Map([]))
  }
  if config.value_contracts && names.get(member_id) is Some(name) {
    return Json::object({
      "$ref": Json::string(config.settings.definition_pointer + "/" + name),
    })
  }
  if config.value_contracts &&
    entry is Object(member_fields) &&
    member_fields.get("traits") is Some(Object(overrides)) &&
    value_overrides(overrides) &&
    shapes.get(target) is Some(Object(target_fields)) {
    let effective = target_fields.copy()
    let traits = match target_fields.get("traits") {
      Some(Object(traits)) => traits.copy()
      _ => Map([])
    }
    for key, value in overrides {
      traits[key] = value
    }
    effective["traits"] = Json::object(traits)
    // Inline the selected top-level contract. Nested structures still use
    // the index's shared references and recursive targets remain bounded.
    return shape_schema(
      Json::object(effective),
      shapes,
      active + [target],
      config,
      names,
    )
  }
  let base = target_schema(target, shapes, active, config, names)
  guard base is Object(schema) else { return base }
  if entry is Object(entry_fields) &&
    entry_fields.get("traits") is Some(Object(traits)) {
    let kind = match schema.get("type") {
      Some(String("array")) => "list"
      Some(String("object")) => "map"
      Some(String("string")) => "string"
      _ => ""
    }
    if schema.get("$ref") is None {
      apply_traits(schema, traits, kind, config)
    }
    if schema.get("$ref") is None &&
      traits.get("smithy.api#timestampFormat") is Some(String(format)) {
      schema["type"] = Json::string(
        if format.has_prefix("epoch-") {
          "number"
        } else {
          "string"
        },
      )
      if format == "date-time" {
        schema["format"] = Json::string("date-time")
      }
      if format == "epoch-seconds" {
        ignore(schema.remove("format"))
      }
    }
    if schema_description(traits) is Some(description) &&
      (schema.get("$ref") is None || config.settings.add_reference_descriptions) {
      schema["description"] = description
    } else if schema.get("$ref") is Some(_) {
      schema.remove("description") |> ignore
    }
    if !config.settings.disable_default_values &&
      schema.get("$ref") is Some(_) &&
      traits.get("smithy.api#default") is Some(value) {
      schema.remove("default") |> ignore
      return Json::object({
        "allOf": Json::array([
          Json::object(schema),
          Json::object({ "default": value }),
        ]),
      })
    }
  }
  if config.value_contracts && target.has_prefix("smithy.api#") {
    let kind = value_prelude_kind(target)
    value_numeric_bounds(schema, kind)
    if kind == "blob" {
      let traits = match entry {
        { "traits": Object(traits), .. } => traits
        _ => Map([])
      }
      value_blob_contract(schema, traits)
    }
  }
  Json::object(schema)
}

///|
fn shape_schema(
  shape : Json,
  shapes : Map[String, Json],
  active : Array[String],
  config : ConversionConfig,
  names : Map[String, String],
) -> Json {
  guard shape is Object(fields) && fields.get("type") is Some(String(kind)) else {
    return Json::object(Map([]))
  }
  let schema = match type_schema(kind, config) {
    Object(fields) => fields
    _ => Map([])
  }
  if (kind == "float" || kind == "double") &&
    config.settings.support_non_numeric_floats {
    schema.remove("type") |> ignore
    schema["oneOf"] = Json::array([
      Json::object({ "type": Json::string("number") }),
      Json::object({
        "type": Json::string("string"),
        "enum": Json::array([
          Json::string("NaN"),
          Json::string("Infinity"),
          Json::string("-Infinity"),
        ]),
      }),
    ])
  }
  if (
      kind == "enum" ||
      (kind == "intEnum" && !config.settings.disable_int_enums)
    ) &&
    fields.get("members") is Some(Object(members)) {
    let values : Array[Json] = []
    let options : Array[Json] = []
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
      if kind == "enum" && config.settings.enum_strategy == "oneOf" {
        let option : Map[String, Json] = { "const": value }
        if entry is Object(entry_fields) &&
          entry_fields.get("traits") is Some(Object(traits)) {
          if traits.get("smithy.api#documentation") is Some(description) {
            option["description"] = description
          }
          if traits.get("smithy.api#title") is Some(title) {
            option["title"] = title
          }
        }
        options.push(Json::object(option))
      }
    }
    if kind == "enum" && config.settings.enum_strategy == "oneOf" {
      schema["oneOf"] = Json::array(options)
    } else {
      schema["enum"] = Json::array(values)
    }
  }
  if fields.get("traits") is Some(Object(traits)) {
    apply_traits(schema, traits, kind, config)
  }
  if kind == "timestamp" {
    let mut format = config.settings.default_timestamp_format
    if fields.get("traits") is Some(Object(traits)) &&
      traits.get("smithy.api#timestampFormat") is Some(String(value)) {
      format = value
    }
    if format == "date-time" {
      schema["format"] = Json::string("date-time")
    } else if format.has_prefix("epoch-") {
      schema["type"] = Json::string("number")
    }
  }
  if kind == "map" &&
    fields.get("key") is Some(key_entry) &&
    fields.get("value") is Some(value_entry) &&
    member_target(key_entry) is Some(_) &&
    member_target(value_entry) is Some(_) {
    let value_schema = member_schema(
      value_entry,
      shapes,
      active,
      config,
      names,
      member_id=value_member_id(active, "value"),
    )
    if config.settings.map_strategy == "patternProperties" {
      let mut pattern = ".+"
      if member_target(key_entry) is Some(target) &&
        shapes.get(target)
        is Some({ "traits": { "smithy.api#pattern": String(value), .. }, .. }) {
        pattern = value
      }
      if key_entry is Object(key_fields) &&
        key_fields.get("traits") is Some(Object(traits)) &&
        traits.get("smithy.api#pattern") is Some(String(value)) {
        pattern = value
      }
      let patterns : Map[String, Json] = Map([])
      patterns[pattern] = value_schema
      schema["patternProperties"] = Json::object(patterns)
    } else {
      schema["propertyNames"] = member_schema(
        key_entry,
        shapes,
        active,
        config,
        names,
        member_id=value_member_id(active, "key"),
      )
      schema["additionalProperties"] = value_schema
    }
  }
  if kind == "list" &&
    fields.get("member") is Some(entry) &&
    member_target(entry) is Some(_) {
    schema["items"] = member_schema(
      entry,
      shapes,
      active,
      config,
      names,
      member_id=value_member_id(active, "member"),
    )
  }
  if (
      kind == "structure" ||
      (kind == "union" && config.settings.union_strategy == "structure")
    ) &&
    fields.get("members") is Some(Object(members)) {
    let properties : Map[String, Json] = Map([])
    let required : Array[String] = []
    for name, entry in members {
      if member_target(entry) is Some(_) {
        let property = property_name(name, entry, config)
        properties[property] = member_schema(
          entry,
          shapes,
          active,
          config,
          names,
          member_id=value_member_id(active, name),
        )
        if entry is Object(entry_fields) &&
          entry_fields.get("traits") is Some(Object(traits)) &&
          traits.get("smithy.api#required") is Some(_) {
          required.push(property)
        }
      }
    }
    if !properties.is_empty() {
      schema["properties"] = Json::object(properties)
    }
    if !required.is_empty() {
      required.sort_by((a, b) => a.lexical_compare(b))
      schema["required"] = Json::array(required.map(Json::string))
    }
    if kind == "union" {
      schema["type"] = Json::string("object")
    }
  }
  if kind == "union" && config.settings.union_strategy == "object" {
    schema["type"] = Json::string("object")
  }
  if kind == "union" &&
    config.settings.union_strategy == "oneOf" &&
    fields.get("members") is Some(Object(members)) {
    let options : Array[Json] = []
    for name, entry in members {
      if member_target(entry) is Some(_) {
        let semantic_name = name
        let name = property_name(name, entry, config)
        let properties : Map[String, Json] = Map([])
        properties[name] = member_schema(
          entry,
          shapes,
          active,
          config,
          names,
          member_id=value_member_id(active, semantic_name),
        )
        options.push(
          Json::object({
            "type": Json::string("object"),
            "title": Json::string(name),
            "required": Json::array([Json::string(name)]),
            "properties": Json::object(properties),
          }),
        )
      }
    }
    schema["oneOf"] = Json::array(options)
  }
  if config.value_contracts {
    value_numeric_bounds(schema, kind)
    value_collection_contract(schema, shape, kind)
    if kind == "blob" {
      let traits = match shape {
        { "traits": Object(traits), .. } => traits
        _ => Map([])
      }
      value_blob_contract(schema, traits)
    }
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
fn schema_names(
  shapes : Map[String, Json],
  service : String,
  config : ConversionConfig,
) -> Map[String, String] {
  let names : Map[String, String] = Map([])
  let renames = match shapes.get(service) {
    Some(Object(fields)) =>
      match fields.get("rename") {
        Some(Object(values)) => values
        _ => Map([])
      }
    _ => Map([])
  }
  for id, _ in shapes {
    let parts = id.split("#").to_array()
    if parts.length() == 2 {
      let name = match renames.get(id) {
        Some(String(name)) => name
        _ => parts[1].to_owned()
      }
      names[id] = if config.settings.alphanumeric_only_refs {
        let out = StringBuilder()
        for ch in name {
          if (ch >= 'a' && ch <= 'z') ||
            (ch >= 'A' && ch <= 'Z') ||
            (ch >= '0' && ch <= '9') {
            out.write_char(ch)
          }
        }
        out.to_string()
      } else {
        name
      }
    }
  }
  names
}

///|
fn is_definition_shape(shape : Json, config : ConversionConfig) -> Bool {
  guard shape is Object(body) && body.get("type") is Some(String(kind)) else {
    return false
  }
  if body.get("traits") is Some(Object(traits)) &&
    traits.get("smithy.api#mixin") is Some(_) {
    return false
  }
  if config.value_contracts {
    return !["service", "resource", "operation"].contains(kind)
  }
  !(kind == "service" ||
  kind == "resource" ||
  kind == "operation" ||
  kind == "list" ||
  (kind == "string" && !has_enum_trait(shape)) ||
  [
    "blob", "boolean", "byte", "short", "integer", "long", "float", "double", "bigInteger",
    "bigDecimal", "timestamp", "document",
  ].contains(kind) ||
  (kind == "intEnum" && config.settings.disable_int_enums))
}

///|
fn namespace_suffix(id : String) -> String {
  let parts = id.split("#").to_array()
  let mut suffix = ""
  for part in parts[0].split(".") {
    let word = part.to_owned()
    if !word.is_empty() {
      suffix += word[:1].to_owned().to_upper() + word[1:].to_owned()
    }
  }
  suffix
}

///|
fn deconflict_names(
  shapes : Map[String, Json],
  connected : Map[String, Bool],
  names : Map[String, String],
  service : String,
  config : ConversionConfig,
) -> Unit raise JsonSchemaError {
  let claimed : Map[String, String] = Map([])
  let ids = shapes.keys().to_array()
  // ShapeId.compareTo in the reference compares ASCII IDs without case first.
  ids.sort_by((a, b) => {
    let order = a.to_lower().lexical_compare(b.to_lower())
    if order == 0 {
      a.lexical_compare(b)
    } else {
      order
    }
  })
  for id in ids {
    if service != "" && connected.get(id) is None {
      continue
    }
    guard shapes.get(id) is Some(shape) &&
      is_definition_shape(shape, config) &&
      names.get(id) is Some(name) else {
      continue
    }
    let mut resolved = name
    if claimed.get(name) is Some(other) {
      let kind = match shape {
        Object(body) => body.get("type")
        _ => None
      }
      if kind != Some(Json::string("map")) {
        raise ConflictingShapeName(
          "Shape " +
          id +
          " conflicts with " +
          other +
          " using JSON Schema name " +
          name,
        )
      }
      resolved = name + namespace_suffix(id)
      if claimed.get(resolved) is Some(other) {
        raise ConflictingShapeName(
          "Shape " +
          id +
          " conflicts with " +
          other +
          " using JSON Schema name " +
          resolved,
        )
      }
      names[id] = resolved
    }
    claimed[resolved] = id
  }
}

///|
/// Convert value shapes in an assembled model to a JSON Schema document.
pub fn convert(
  model : @smithy.Model,
  service~ : String = "",
  config~ : Config = Config::new(),
) -> Json raise {
  convert_with_profile(model, service~, config~, value_contracts=false)
}

///|
/// Convert with runtime value-contract semantics while retaining the existing
/// reference-compatible convert signature and Config record.
pub fn convert_values(
  model : @smithy.Model,
  service~ : String = "",
  config~ : Config = Config::new(),
) -> Json raise {
  convert_with_profile(model, service~, config~, value_contracts=true)
}

///|
fn convert_with_profile(
  model : @smithy.Model,
  service~ : String = "",
  config~ : Config = Config::new(),
  value_contracts~ : Bool = false,
) -> Json raise {
  let config : ConversionConfig = { settings: config, value_contracts, }
  validate_value_config(config)
  if !["propertyNames", "patternProperties"].contains(
      config.settings.map_strategy,
    ) ||
    !["oneOf", "object", "structure"].contains(config.settings.union_strategy) ||
    !["enum", "oneOf"].contains(config.settings.enum_strategy) {
    raise InvalidConfiguration("Unknown JSON Schema strategy")
  }
  if !["date-time", "http-date", "epoch-seconds"].contains(
      config.settings.default_timestamp_format,
    ) {
    raise InvalidConfiguration(
      "Unknown timestamp format: " + config.settings.default_timestamp_format,
    )
  }
  if !config.settings.definition_pointer.has_prefix("#/") {
    raise InvalidConfiguration("definitionPointer must start with #/")
  }
  if !(config.settings.schema_document_extensions is Object(_)) {
    raise InvalidConfiguration("schemaDocumentExtensions must be an object")
  }
  if service != "" &&
    !(model.get(service) is Some({ body: @smithy.Service(..), .. })) {
    raise InvalidConfiguration("Unknown service shape: " + service)
  }
  let ast = @syntax.encode_json_ast(model.to_json_ast())
  guard ast is Object(fields) && fields.get("shapes") is Some(Object(shapes)) else {
    return Json::object(Map([]))
  }
  let definitions : Map[String, Json] = Map([])
  let mut unit_targeted = false
  let connected = connected_shapes(service, shapes)
  let names = schema_names(shapes, service, config)
  deconflict_names(shapes, connected, names, service, config)
  if config.value_contracts {
    value_member_names(shapes, connected, names, service)
  }
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
    if body.get("traits") is Some(Object(traits)) &&
      traits.get("smithy.api#mixin") is Some(_) {
      continue
    }
    if kind == "union" && body.get("members") is Some(Object(members)) {
      for _, entry in members {
        if member_target(entry) == Some("smithy.api#Unit") {
          unit_targeted = true
        }
      }
    }
    if !config.value_contracts &&
      (
        kind == "list" ||
        (kind == "string" && !has_enum_trait(shape)) ||
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
        kind == "document" ||
        (kind == "intEnum" && config.settings.disable_int_enums)
      ) {
      continue
    }
    guard names.get(id) is Some(name) else { continue }
    definitions[name] = shape_schema(shape, shapes, [id], config, names)
  }
  if config.value_contracts {
    for (member_id, entry) in value_member_entries(shapes) {
      if names.get(member_id) is Some(name) {
        definitions[name] = member_schema(entry, shapes, [], config, names)
      }
    }
  }
  if unit_targeted {
    if config.value_contracts && definitions.contains("Unit") {
      raise ConflictingShapeName(
        "A contextual data shape conflicts with smithy.api#Unit using schema name Unit; rename that shape in the service.",
      )
    }
    definitions["Unit"] = if config.value_contracts {
      Json::object({
        "type": Json::string("object"),
        "properties": Json::object(Map([])),
        "additionalProperties": Json::boolean(false),
      })
    } else {
      Json::object({ "type": Json::string("object") })
    }
  }
  let document : Map[String, Json] = Map([])
  if config.settings.schema_document_extensions is Object(extensions) {
    for key, value in extensions {
      document[key] = value
    }
  }
  let pointer = config.settings.definition_pointer.split("/").to_array()
  let mut nested = Json::object(definitions)
  for index = pointer.length() - 1; index >= 1; index = index - 1 {
    let parent : Map[String, Json] = Map([])
    parent[pointer[index].to_owned()] = nested
    nested = Json::object(parent)
  }
  if nested is Object(fields) {
    for key, value in fields {
      document[key] = value
    }
  }
  Json::object(document)
}
