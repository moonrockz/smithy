///|
/// A prepared conversion context for protocol converters that need the complete
/// schema document plus schemas for individual members or filtered structures.
/// The encoded model and contextual names are prepared once, not per binding.
pub struct SchemaIndex {
  shapes : Map[String, Json]
  names : Map[String, String]
  config : Config
  document : Json
  definitions : Map[String, @smithy.ShapeId]
}

///|
pub fn SchemaIndex::new(
  model : @smithy.Model,
  service~ : String = "",
  config~ : Config = Config::new(),
) -> SchemaIndex raise {
  let document = convert(model, service~, config~)
  let ast = @syntax.encode_json_ast(model.to_json_ast())
  guard ast is { "shapes": Object(shapes), .. } else {
    raise InvalidConfiguration("Model has no shape table")
  }
  let names = schema_names(shapes, service)
  let connected = connected_shapes(service, shapes)
  if service == "" {
    for id, _ in shapes {
      connected[id] = true
    }
  }
  deconflict_names(shapes, connected, names, service, config)
  let definitions : Map[String, @smithy.ShapeId] = Map([])
  for id, _ in connected {
    if @smithy.ShapeId::parse(id) is Some(shape_id) &&
      names.get(id) is Some(name) &&
      shapes.get(id) is Some(shape) &&
      is_definition_shape(shape, config) {
      definitions[name] = shape_id
    }
  }
  { shapes, names, config, document, definitions, }
}

///|
/// Resolve a contextual component name within the selected service closure.
pub fn SchemaIndex::definition(
  self : SchemaIndex,
  name : String,
) -> @smithy.ShapeId? {
  self.definitions.get(name)
}

///|
pub fn SchemaIndex::document(self : SchemaIndex) -> Json {
  self.document
}

///|
pub fn SchemaIndex::name(self : SchemaIndex, id : @smithy.ShapeId) -> String {
  self.names.get(id.root().to_string()).unwrap_or(id.name())
}

///|
/// Convert a value shape inline, retaining the shared contextual references.
pub fn SchemaIndex::shape(
  self : SchemaIndex,
  id : @smithy.ShapeId,
  config~ : Config? = None,
) -> Json raise JsonSchemaError {
  guard self.shapes.get(id.to_string()) is Some(shape) else {
    raise InvalidConfiguration("Unknown schema shape `" + id.to_string() + "`")
  }
  shape_schema(
    shape,
    self.shapes,
    [id.to_string()],
    config.unwrap_or(self.config),
    self.names,
  )
}

///|
/// Convert a member using the same inline/reference rules as a full document.
pub fn SchemaIndex::schema_for_member(
  self : SchemaIndex,
  id : @smithy.ShapeId,
  config~ : Config? = None,
) -> Json raise JsonSchemaError {
  guard id.member_name() is Some(name) &&
    self.shapes.get(id.root().to_string()) is Some(Object(parent)) else {
    raise InvalidConfiguration("Unknown schema member `" + id.to_string() + "`")
  }
  let entries = match parent.get("members") {
    Some(Object(members)) => members
    _ => parent
  }
  guard entries.get(name) is Some(entry) && member_target(entry) is Some(_) else {
    raise InvalidConfiguration("Unknown schema member `" + id.to_string() + "`")
  }
  member_schema(
    entry,
    self.shapes,
    [],
    config.unwrap_or(self.config),
    self.names,
  )
}

///|
/// Convert only the selected members of a structure. Filtering occurs before
/// required/property generation, so omitted HTTP bindings cannot leave stale
/// required properties in synthesized document payloads.
pub fn SchemaIndex::structure(
  self : SchemaIndex,
  id : @smithy.ShapeId,
  selected : Array[@smithy.ShapeId],
) -> Json raise JsonSchemaError {
  guard self.shapes.get(id.to_string()) is Some(Object(fields)) &&
    fields.get("type") == Some(Json::string("structure")) else {
    raise InvalidConfiguration(
      "Expected schema structure `" + id.to_string() + "`",
    )
  }
  let original = match fields.get("members") {
    Some(Object(members)) => members
    _ => Map([])
  }
  let members : Map[String, Json] = Map([])
  for selected_id in selected {
    guard selected_id.root() == id &&
      selected_id.member_name() is Some(name) &&
      original.get(name) is Some(value) else {
      raise InvalidConfiguration(
        "Selected member does not belong to `" + id.to_string() + "`",
      )
    }
    members[name] = value
  }
  let filtered : Map[String, Json] = Map([])
  for key, value in fields {
    filtered[key] = value
  }
  filtered["members"] = Json::object(members)
  shape_schema(
    Json::object(filtered),
    self.shapes,
    [id.to_string()],
    self.config,
    self.names,
  )
}
