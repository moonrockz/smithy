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
  let ids = ids.copy()
  ids.sort_by((a, b) => a.to_string().compare(b.to_string()))
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
fn Model::export_member(
  self : Model,
  id : ShapeId,
  introduced~ : Bool = false,
) -> Json raise BuildError {
  guard self.shapes.get(id) is Some(shape) && shape.body is Member(target~) else {
    raise InvalidShape(
      "I expected a member shape at \{id} while serializing the model.",
    )
  }
  let fields : Map[String, Json] = {
    "target": Json::string(target.to_string()),
  }
  let traits = if introduced { shape.introduced_traits() } else { shape.traits }
  if !traits.is_empty() {
    fields["traits"] = Json::object(export_traits(traits))
  }
  Json::object(fields)
}

///|
fn export_introduced_body(shape : Shape, fields : Map[String, Json]) -> Unit {
  guard shape.provenance is Some(origin) && !shape.mixins.is_empty() else {
    return
  }
  let introduced = origin.introduced_fields
  let inherited = origin.inherited_fields
  let keys = match shape.body {
    Service(..) => ["operations", "resources", "errors"]
    Operation(..) => ["errors"]
    Resource(..) => ["operations", "resources"]
    _ => []
  }
  for key in keys {
    guard fields.get(key) is Some(Array(current)) else { continue }
    let inherited = match inherited.get(key) {
      Some(Array(values)) => values.map(@json.to_json)
      _ => []
    }
    let introduced = match introduced.get(key) {
      Some(Array(values)) => values.map(@json.to_json)
      _ => []
    }
    let kept = current.filter(value => {
      introduced.contains(value) || !inherited.contains(value)
    })
    if kept.is_empty() {
      fields.remove(key)
    } else {
      fields[key] = Json::array(kept)
    }
  }
  if shape.body is Service(version~, rename~, ..) {
    if version.trim().is_empty() ||
      (
        !introduced.contains("version") &&
        inherited.get("version") == Some(String(version))
      ) {
      fields.remove("version")
    }
    let old = match inherited.get("rename") {
      Some(Object(fields)) => fields
      _ => Map([])
    }
    let local = match introduced.get("rename") {
      Some(Object(fields)) => fields
      _ => Map([])
    }
    let kept : Map[String, Json] = Map([])
    for id, name in rename {
      let key = id.to_string()
      if local.contains(key) || old.get(key) != Some(String(name)) {
        kept[key] = Json::string(name)
      }
    }
    if kept.is_empty() {
      fields.remove("rename")
    } else {
      fields["rename"] = Json::object(kept)
    }
  }
}

///|
/// Serialize the assembled graph to a flattened JSON AST. Mixins remain
/// available as shape provenance in memory; their inherited contents are
/// explicit in this representation. Built-in prelude and contract definitions
/// are omitted unless include_prelude is true.
pub fn Model::to_json_ast(
  self : Model,
  include_prelude~ : Bool = false,
  preserve_mixins~ : Bool = false,
) -> @syntax.JsonAst raise {
  let shapes : Map[String, Json] = Map([])
  for id, shape in self.shapes {
    if id.member is Some(_) || (!include_prelude && shape.source.is_builtin()) {
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
    if preserve_mixins {
      if !shape.mixins.is_empty() {
        fields["mixins"] = Json::array(
          shape.mixins.map(id => reference(id.to_string())),
        )
      }
      export_introduced_body(shape, fields)
      let members = match shape.body {
        List(member_) => [member_]
        Map(key~, value~) => [key, value]
        Structure(members)
        | Union(members)
        | Enum(members)
        | IntEnum(members) => members
        _ => []
      }
      let named = match fields.get("members") {
        Some(Object(members)) => members
        _ => Map([])
      }
      for member_id in members {
        guard self.shapes.get(member_id) is Some(member_) else { continue }
        let name = member_id.member.unwrap_or("")
        if member_.mixins.is_empty() {
          let exported = self.export_member(member_id, introduced=true)
          if shape.body is (List(_) | Map(..)) {
            fields[name] = exported
          } else {
            named[name] = exported
          }
        } else {
          if shape.body is (List(_) | Map(..)) {
            fields.remove(name)
          } else {
            named.remove(name)
          }
          let traits = member_.introduced_traits()
          if !traits.is_empty() {
            shapes[member_id.to_string()] = Json::object({
              "type": "apply",
              "traits": Json::object(export_traits(traits)),
            })
          }
        }
      }
      if shape.body is (Structure(_) | Union(_) | Enum(_) | IntEnum(_)) {
        fields["members"] = Json::object(named)
      }
    }
    let traits = if preserve_mixins {
      shape.introduced_traits()
    } else {
      shape.traits
    }
    if !traits.is_empty() {
      fields["traits"] = Json::object(export_traits(traits))
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
