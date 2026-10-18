///|
priv suberror BuildError {
  InvalidShape(String)
}

///|
fn require_id(text : String) -> ShapeId raise BuildError {
  match ShapeId::parse(text) {
    Some(id) => id
    None =>
      raise InvalidShape("I expected an absolute shape ID, but found \{text}.")
  }
}

///|
fn Assembly::lower_traits(
  self : Assembly,
  traits : Map[String, Json]?,
) -> Map[ShapeId, NodeValue] raise {
  let out : Map[ShapeId, NodeValue] = Map([])
  for id, value in traits.unwrap_or(Map([])) {
    let value = if value is Null {
      match self.kinds.get(id) {
        Some("structure" | "map") => Json::empty_object()
        Some("list" | "set") => Json::array([])
        _ => value
      }
    } else {
      value
    }
    out[require_id(id)] = NodeValue::from_json(value)
  }
  out
}

///|
fn references(
  values : Array[@syntax.JsonReference]?,
) -> Array[ShapeId] raise BuildError {
  values.unwrap_or([]).map(r => require_id(r.target))
}

///|
fn reference_map(
  values : Map[String, @syntax.JsonReference]?,
) -> Map[String, ShapeId] raise BuildError {
  let out : Map[String, ShapeId] = Map([])
  for name, value in values.unwrap_or(Map([])) {
    out[name] = require_id(value.target)
  }
  out
}

///|
fn Assembly::lower_member(
  self : Assembly,
  shapes : Map[ShapeId, Shape],
  raw : RawShape,
  name : String,
  member_ : @syntax.JsonMember,
) -> ShapeId raise {
  let id = require_id(raw.id + "$" + name)
  shapes[id] = {
    id,
    body: Member(target=require_id(member_.target)),
    traits: self.lower_traits(member_.traits),
    mixins: [],
    source: self.locations
    .get(id.to_string())
    .unwrap_or({
      ..raw.source,
      path: raw.source.path + "/members/" + pointer(name),
    }),
  }
  id
}

///|
fn Assembly::lower_members(
  self : Assembly,
  shapes : Map[ShapeId, Shape],
  raw : RawShape,
  members : Map[String, @syntax.JsonMember]?,
) -> Array[ShapeId] raise {
  let out = []
  for name, member_ in members.unwrap_or(Map([])) {
    out.push(self.lower_member(shapes, raw, name, member_))
  }
  out
}

///|
fn Assembly::lower(
  self : Assembly,
  raw : RawShape,
  shapes : Map[ShapeId, Shape],
) -> Unit raise {
  let ast = @syntax.decode_json_ast({
    "smithy": "2.0",
    "shapes": Json::object(Map([(raw.id, Json::object(raw.fields))])),
  })
  let shape = ast.shapes.unwrap().get(raw.id).unwrap()
  let id = require_id(raw.id)
  let body : ShapeBody = match shape.kind {
    Simple(type_) => Simple(type_)
    List(member_) | Set(member_) => {
      guard member_ is Some(member_) else {
        raise InvalidShape(
          "I expected the member of list \{id}, but found no member.",
        )
      }
      List(self.lower_member(shapes, raw, "member", member_))
    }
    Map(key~, value~) => {
      guard key is Some(key) && value is Some(value) else {
        raise InvalidShape(
          "I expected both key and value members of map \{id}.",
        )
      }
      Map(
        key=self.lower_member(shapes, raw, "key", key),
        value=self.lower_member(shapes, raw, "value", value),
      )
    }
    Structure(members) => Structure(self.lower_members(shapes, raw, members))
    Union(members) => Union(self.lower_members(shapes, raw, members))
    Enum(members) => Enum(self.lower_members(shapes, raw, members))
    IntEnum(members) => IntEnum(self.lower_members(shapes, raw, members))
    Operation(operation) =>
      Operation(
        input=require_id(
          operation.input.map(r => r.target).unwrap_or("smithy.api#Unit"),
        ),
        output=require_id(
          operation.output.map(r => r.target).unwrap_or("smithy.api#Unit"),
        ),
        errors=references(operation.errors),
      )
    Service(service) => {
      let rename : Map[ShapeId, String] = Map([])
      for key, value in service.rename.unwrap_or(Map([])) {
        rename[require_id(key)] = value
      }
      Service(
        version=service.version.unwrap_or(""),
        operations=references(service.operations),
        resources=references(service.resources),
        errors=references(service.errors),
        rename~,
      )
    }
    Resource(resource) =>
      Resource(
        identifiers=reference_map(resource.identifiers),
        properties=reference_map(resource.properties),
        create=resource.create.map(r => require_id(r.target)),
        put=resource.put.map(r => require_id(r.target)),
        read=resource.read.map(r => require_id(r.target)),
        update=resource.update.map(r => require_id(r.target)),
        delete=resource.delete.map(r => require_id(r.target)),
        list=resource.list.map(r => require_id(r.target)),
        operations=references(resource.operations),
        collectionOperations=references(resource.collectionOperations),
        resources=references(resource.resources),
      )
    Apply => raise InvalidShape("I found an unprocessed apply entry \{id}.")
  }
  let traits = self.lower_traits(shape.traits)
  if shape.kind is Set(_) {
    traits[require_id("smithy.api#uniqueItems")] = Object(Map([]))
  }
  shapes[id] = {
    id,
    body,
    traits,
    mixins: references(shape.mixins),
    source: raw.source,
  }
}

///|
/// Compare duplicate shape definitions independent of traits and empty maps,
/// after inheritance has supplied each definition's structural properties.
fn structural(fields : Map[String, Json]) -> Json {
  let out = copy(fields)
  out.remove("traits") |> ignore
  out.remove("mixins") |> ignore
  let members = raw_members(fields)
  let cleaned : Map[String, Json] = Map([])
  for name, member_ in members {
    let value = copy(object(member_))
    value.remove("traits") |> ignore
    cleaned[name] = Json::object(value)
  }
  set_members(out, cleaned)
  for
    key in [
      "errors", "operations", "resources", "collectionOperations", "identifiers",
      "properties", "rename",
    ] {
    if out.get(key) == Some(Json::array([])) ||
      out.get(key) == Some(Json::empty_object()) {
      out.remove(key) |> ignore
    }
  }
  if string_field(out, "type") == Some("operation") {
    if !out.contains("input") {
      out["input"] = reference("smithy.api#Unit")
    }
    if !out.contains("output") {
      out["output"] = reference("smithy.api#Unit")
    }
  }
  Json::object(out)
}

///|
fn Assembly::finish(self : Assembly) -> LoadResult {
  self.apply_roots()
  let flattened = self.flatten()
  for (a, b) in self.duplicates {
    let a = flattened.get(a.id).unwrap_or(a)
    let b = self.flatten_one(b, flattened)
    if is_builtin_source(a.source.file) && !is_builtin_source(b.source.file) {
      let shape_traits_equal = try
        NodeValue::from_json(Json::object(object_field(a.fields, "traits"))) ==
        NodeValue::from_json(Json::object(object_field(b.fields, "traits")))
      catch {
        _ => false
      }
      let a_members = raw_members(a.fields)
      let b_members = raw_members(b.fields)
      let member_traits_equal = a_members
        .iter()
        .all(entry => {
          let left = object_field(object(entry.1), "traits")
          let right = object_field(
            object(b_members.get(entry.0).unwrap_or(Json::null())),
            "traits",
          )
          try
            NodeValue::from_json(Json::object(left)) ==
            NodeValue::from_json(Json::object(right))
          catch {
            _ => false
          }
        })
      if structural(a.fields) != structural(b.fields) ||
        !shape_traits_equal ||
        !member_traits_equal {
        self.problem(
          "SM-MODEL-014",
          "I cannot redefine the built-in shape \{b.id}.",
          b.source,
          shape=b.id,
        )
      }
      continue
    }
    if structural(a.fields) != structural(b.fields) {
      self.problem(
        "SM-MODEL-003",
        "I found conflicting definitions of shape \{b.id}.",
        b.source,
        shape=b.id,
      )
    }
  }
  let shapes : Map[ShapeId, Shape] = Map([])
  for _, raw in flattened {
    self.lower(raw, shapes) catch {
      InvalidShape(message) =>
        self.problem("SM-MODEL-010", message, raw.source, shape=raw.id)
      @json.JsonDecodeError((path, message)) =>
        self.problem(
          "SM-MODEL-010",
          message,
          { ..raw.source, path: path.to_string(), },
          shape=raw.id,
        )
      InvalidNode(message) =>
        self.problem("SM-MODEL-001", message, raw.source, shape=raw.id)
      error =>
        self.problem(
          "SM-MODEL-001",
          "I could not assemble \{raw.id}: \{error}.",
          raw.source,
          shape=raw.id,
        )
    }
  }
  let model : Model = { shapes, metadata: self.metadata, }
  self.validate(model)
  let failed = self.diagnostics.iter().any(d => d.severity == Error)
  {
    model: if failed {
      None
    } else {
      Some(model)
    },
    diagnostics: self.diagnostics,
  }
}
