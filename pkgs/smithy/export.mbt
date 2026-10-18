///|
fn export_traits(traits : Map[ShapeId, NodeValue]) -> Map[String, Json] {
  let out : Map[String, Json] = Map([])
  for id, value in traits {
    out[id.to_string()] = @json.to_json(value)
  }
  out
}

///|
fn export_references(ids : Array[ShapeId]) -> Json {
  Json::array(ids.map(id => reference(id.to_string())))
}

///|
fn export_reference_map(ids : Map[String, ShapeId]) -> Json {
  let out : Map[String, Json] = Map([])
  for name, id in ids {
    out[name] = reference(id.to_string())
  }
  Json::object(out)
}

///|
fn Model::export_member(self : Model, id : ShapeId) -> Json raise BuildError {
  guard self.shapes.get(id) is Some(shape) && shape.body is Member(target~) else {
    raise InvalidShape(
      "I expected a member shape at \{id} while serializing the model.",
    )
  }
  let fields : Map[String, Json] = {
    "target": Json::string(target.to_string()),
  }
  if !shape.traits.is_empty() {
    fields["traits"] = Json::object(export_traits(shape.traits))
  }
  Json::object(fields)
}

///|
/// Serialize the assembled graph to a flattened JSON AST. Mixins remain
/// available as shape provenance in memory; their inherited contents are
/// explicit in this representation. Built-in prelude and contract definitions
/// are omitted unless include_prelude is true.
pub fn Model::to_json_ast(
  self : Model,
  include_prelude~ : Bool = false,
) -> @syntax.JsonAst raise {
  let shapes : Map[String, Json] = Map([])
  for id, shape in self.shapes {
    if id.member is Some(_) ||
      (!include_prelude && is_builtin_source(shape.source.file)) {
      continue
    }
    let fields : Map[String, Json] = {
      "type": Json::string(shape.body.keyword()),
    }
    match shape.body {
      Simple(_) => ()
      Member(..) => continue
      List(member_) => fields["member"] = self.export_member(member_)
      Map(key~, value~) => {
        fields["key"] = self.export_member(key)
        fields["value"] = self.export_member(value)
      }
      Structure(members) | Union(members) | Enum(members) | IntEnum(members) => {
        let ms : Map[String, Json] = Map([])
        for member_ in members {
          if member_.member is Some(name) {
            ms[name] = self.export_member(member_)
          }
        }
        fields["members"] = Json::object(ms)
      }
      Operation(input~, output~, errors~) => {
        fields["input"] = reference(input.to_string())
        fields["output"] = reference(output.to_string())
        if !errors.is_empty() {
          fields["errors"] = export_references(errors)
        }
      }
      Service(version~, operations~, resources~, errors~, rename~) => {
        fields["version"] = Json::string(version)
        if !operations.is_empty() {
          fields["operations"] = export_references(operations)
        }
        if !resources.is_empty() {
          fields["resources"] = export_references(resources)
        }
        if !errors.is_empty() {
          fields["errors"] = export_references(errors)
        }
        if !rename.is_empty() {
          let names : Map[String, Json] = Map([])
          for id, name in rename {
            names[id.to_string()] = Json::string(name)
          }
          fields["rename"] = Json::object(names)
        }
      }
      Resource(
        identifiers~,
        properties~,
        create~,
        put~,
        read~,
        update~,
        delete~,
        list~,
        operations~,
        collectionOperations~,
        resources~
      ) => {
        if !identifiers.is_empty() {
          fields["identifiers"] = export_reference_map(identifiers)
        }
        if !properties.is_empty() {
          fields["properties"] = export_reference_map(properties)
        }
        for
          (key, value) in [
            ("create", create),
            ("put", put),
            ("read", read),
            ("update", update),
            ("delete", delete),
            ("list", list),
          ] {
          if value is Some(id) {
            fields[key] = reference(id.to_string())
          }
        }
        if !operations.is_empty() {
          fields["operations"] = export_references(operations)
        }
        if !collectionOperations.is_empty() {
          fields["collectionOperations"] = export_references(
            collectionOperations,
          )
        }
        if !resources.is_empty() {
          fields["resources"] = export_references(resources)
        }
      }
    }
    if !shape.traits.is_empty() {
      fields["traits"] = Json::object(export_traits(shape.traits))
    }
    shapes[id.to_string()] = Json::object(fields)
  }
  let fields : Map[String, Json] = {
    "smithy": "2.0",
    "shapes": Json::object(shapes),
  }
  if !self.metadata.is_empty() {
    let metadata : Map[String, Json] = Map([])
    for key, value in self.metadata {
      metadata[key] = @json.to_json(value)
    }
    fields["metadata"] = Json::object(metadata)
  }
  @syntax.decode_json_ast(Json::object(fields))
}
