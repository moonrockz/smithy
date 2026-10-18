///|
fn[K : Show, V] sorted_keys(values : Map[K, V]) -> Array[K] {
  let keys = values.keys().to_array()
  keys.sort_by((a, b) => a.to_string().compare(b.to_string()))
  keys
}

///|
/// JSON node values are also IDL node values. Sort object keys so generated
/// files are stable regardless of the order in which inputs were loaded.
fn idl_value(value : Json) -> String {
  match value {
    Object(fields) => {
      let entries = sorted_keys(fields).map(key => {
        Json::string(key).stringify() +
        ": " +
        idl_value(fields.get(key).unwrap())
      })
      "{ " + entries.join(", ") + " }"
    }
    Array(values) => "[" + values.map(idl_value).join(", ") + "]"
    _ => value.stringify()
  }
}

///|
fn idl_traits(shape : Shape, indent : String) -> String {
  let out = StringBuilder()
  for id in sorted_keys(shape.traits) {
    let value = @json.to_json(shape.traits.get(id).unwrap())
    out.write_string("\{indent}@\{id}(\{idl_value(value)})\n")
  }
  out.to_string()
}

///|
fn Model::idl_member(
  self : Model,
  id : ShapeId,
  enum_ : Bool,
) -> String raise BuildError {
  guard self.shapes.get(id) is Some(shape) &&
    shape.body is Member(target~) &&
    id.member is Some(name) else {
    raise InvalidShape(
      "I expected a member shape at \{id} while serializing IDL.",
    )
  }
  let traits = idl_traits(shape, "    ")
  traits + "    \{name}" + (if enum_ { "" } else { ": \{target}" }) + "\n"
}

///|
fn idl_ids(ids : Array[ShapeId]) -> String {
  "[" + ids.map(id => id.to_string()).join(", ") + "]"
}

///|
fn idl_id_map(ids : Map[String, ShapeId]) -> String {
  "{ " +
  sorted_keys(ids)
  .map(name => {
    Json::string(name).stringify() + ": " + ids.get(name).unwrap().to_string()
  })
  .join(", ") +
  " }"
}

///|
fn Model::idl_shape(self : Model, shape : Shape) -> String raise BuildError {
  let out = StringBuilder()
  out.write_string(idl_traits(shape, ""))
  out.write_string("\{shape.body.keyword()} \{shape.id.name}")
  if shape.body is Simple(_) {
    out.write_string("\n")
    return out.to_string()
  }
  out.write_string(" {\n")
  fn property(name : String, value : String) {
    out.write_string("    \{name}: \{value}\n")
  }
  fn references(name : String, ids : Array[ShapeId]) {
    if !ids.is_empty() {
      property(name, idl_ids(ids))
    }
  }
  match shape.body {
    Simple(_) | Member(..) => ()
    List(member_) => out.write_string(self.idl_member(member_, false))
    Map(key~, value~) => {
      out.write_string(self.idl_member(key, false))
      out.write_string(self.idl_member(value, false))
    }
    Structure(members) | Union(members) =>
      for member_ in members {
        out.write_string(self.idl_member(member_, false))
      }
    Enum(members) | IntEnum(members) =>
      for member_ in members {
        out.write_string(self.idl_member(member_, true))
      }
    Operation(input~, output~, errors~) => {
      property("input", input.to_string())
      property("output", output.to_string())
      references("errors", errors)
    }
    Service(version~, operations~, resources~, errors~, rename~) => {
      property("version", Json::string(version).stringify())
      references("operations", operations)
      references("resources", resources)
      references("errors", errors)
      if !rename.is_empty() {
        let entries = sorted_keys(rename).map(id => {
          Json::string(id.to_string()).stringify() +
          ": " +
          Json::string(rename.get(id).unwrap()).stringify()
        })
        property("rename", "{ " + entries.join(", ") + " }")
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
        property("identifiers", idl_id_map(identifiers))
      }
      if !properties.is_empty() {
        property("properties", idl_id_map(properties))
      }
      for
        (name, value) in [
          ("create", create),
          ("put", put),
          ("read", read),
          ("update", update),
          ("delete", delete),
          ("list", list),
        ] {
        if value is Some(id) {
          property(name, id.to_string())
        }
      }
      references("operations", operations)
      references("collectionOperations", collectionOperations)
      references("resources", resources)
    }
  }
  out.write_string("}\n")
  out.to_string()
}

///|
/// Serialize an assembled model to Smithy 2 IDL, keyed by namespace. Built-in
/// definitions are omitted and inherited contents are flattened, as in to_json_ast.
/// Metadata appears exactly once, in the first namespace. A metadata-only or
/// empty model uses the empty namespace key. References are absolute, so names
/// cannot collide with local definitions or implicit prelude names.
pub fn Model::to_idl(self : Model) -> Map[String, String] raise {
  let groups : Map[String, Array[Shape]] = Map([])
  for id in sorted_keys(self.shapes) {
    let shape = self.shapes.get(id).unwrap()
    if id.member is Some(_) || is_builtin_source(shape.source.file) {
      continue
    }
    let group = groups.get_or_init(id.namespace, () => [])
    group.push(shape)
  }
  if groups.is_empty() {
    groups[""] = []
  }
  let files : Map[String, String] = Map([])
  for index, namespace in sorted_keys(groups) {
    let out = StringBuilder()
    out.write_string("$version: \"2\"\n")
    if index == 0 && !self.metadata.is_empty() {
      out.write_string("\n")
      for key in sorted_keys(self.metadata) {
        out.write_string(
          "metadata \{Json::string(key).stringify()} = \{idl_value(@json.to_json(self.metadata.get(key).unwrap()))}\n",
        )
      }
    }
    if namespace != "" {
      out.write_string("\nnamespace \{namespace}\n")
    }
    for shape in groups.get(namespace).unwrap() {
      out.write_string("\n")
      out.write_string(self.idl_shape(shape))
    }
    files[namespace] = out.to_string()
  }
  files
}
