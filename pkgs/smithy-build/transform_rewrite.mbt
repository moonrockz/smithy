///|
fn rewrite_shape_id(text : String) -> @smithy.ShapeId raise BuildError {
  @smithy.ShapeId::parse(text).unwrap_or_else(() => {
    raise InvalidBuildConfig(
      "Expected an absolute shape ID, found `" + text + "`",
    )
  })
}

///|
fn rewrite_bool(args : Json, name : String) -> Bool raise BuildError {
  match config_field(args, name) {
    None => false
    Some(True) => true
    Some(False) => false
    _ => raise InvalidBuildConfig("Expected `" + name + "` to be a boolean")
  }
}

///|
fn rewrite_value(
  value : @smithy.NodeValue,
  renamed : Map[@smithy.ShapeId, @smithy.ShapeId],
) -> @smithy.NodeValue raise BuildError {
  fn text(value : String) -> String {
    @smithy.ShapeId::parse(value)
    .bind(id => renamed.get(id))
    .map(id => id.to_string())
    .unwrap_or(value)
  }
  match value {
    @smithy.String(value) => @smithy.String(text(value))
    @smithy.Array(values) =>
      @smithy.Array(values.map(value => rewrite_value(value, renamed)))
    @smithy.Object(fields) => {
      let out : Map[String, @smithy.NodeValue] = Map([])
      for key, value in fields {
        let key = text(key)
        if out.contains(key) {
          raise InvalidBuildConfig(
            "Renaming shapes produced duplicate object key `" + key + "`",
          )
        }
        out[key] = rewrite_value(value, renamed)
      }
      @smithy.Object(out)
    }
    value => value
  }
}

///|
fn rewrite_rename(
  model : @smithy.Model,
  renamed : Map[@smithy.ShapeId, @smithy.ShapeId],
) -> @smithy.Model raise BuildError {
  if renamed.iter().all(pair => pair.0 == pair.1) {
    return model
  }
  fn reference(id : @smithy.ShapeId) -> @smithy.ShapeId {
    renamed.get(id).unwrap_or(id)
  }
  fn own_id(id : @smithy.ShapeId) -> @smithy.ShapeId {
    // Member keys in the JSON AST are relative names. Renaming a container
    // automatically updates its members; a member-only mapping rewrites values.
    let parent = reference(id.root())
    match id.member {
      Some(name) => parent.root().with_member(name).unwrap_or(id)
      None => parent
    }
  }
  fn map_ids(ids : Array[@smithy.ShapeId]) -> Array[@smithy.ShapeId] {
    ids.map(own_id)
  }
  fn map_refs(ids : Array[@smithy.ShapeId]) -> Array[@smithy.ShapeId] {
    ids.map(reference)
  }
  fn optional(id : @smithy.ShapeId?) -> @smithy.ShapeId? {
    id.map(reference)
  }
  fn id_map(
    ids : Map[String, @smithy.ShapeId],
  ) -> Map[String, @smithy.ShapeId] {
    let out : Map[String, @smithy.ShapeId] = Map([])
    for name, id in ids {
      out[name] = reference(id)
    }
    out
  }
  let shapes : Map[@smithy.ShapeId, @smithy.Shape] = Map([])
  for id, shape in model.shapes {
    let updated_id = own_id(id)
    if shapes.contains(updated_id) {
      raise InvalidBuildConfig(
        "Renaming shapes produced duplicate shape `" +
        updated_id.to_string() +
        "`",
      )
    }
    let body = match shape.body {
      @smithy.Simple(_) => shape.body
      @smithy.Member(target~) => @smithy.Member(target=reference(target))
      @smithy.List(member_) => @smithy.List(own_id(member_))
      @smithy.Map(key~, value~) =>
        @smithy.Map(key=own_id(key), value=own_id(value))
      @smithy.Structure(m) => @smithy.Structure(map_ids(m))
      @smithy.Union(m) => @smithy.Union(map_ids(m))
      @smithy.Enum(m) => @smithy.Enum(map_ids(m))
      @smithy.IntEnum(m) => @smithy.IntEnum(map_ids(m))
      @smithy.Operation(input~, output~, errors~) =>
        @smithy.Operation(
          input=reference(input),
          output=reference(output),
          errors=map_refs(errors),
        )
      @smithy.Service(version~, operations~, resources~, errors~, rename~) => {
        let names : Map[@smithy.ShapeId, String] = Map([])
        for id, name in rename {
          names[reference(id)] = name
        }
        let version = @smithy.ShapeId::parse(version)
          .map(reference)
          .map(id => id.to_string())
          .unwrap_or(version)
        @smithy.Service(
          version~,
          operations=map_refs(operations),
          resources=map_refs(resources),
          errors=map_refs(errors),
          rename=names,
        )
      }
      @smithy.Resource(
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
      ) =>
        @smithy.Resource(
          identifiers=id_map(identifiers),
          properties=id_map(properties),
          create=optional(create),
          put=optional(put),
          read=optional(read),
          update=optional(update),
          delete=optional(delete),
          list=optional(list),
          operations=map_refs(operations),
          collectionOperations=map_refs(collectionOperations),
          resources=map_refs(resources),
        )
    }
    let traits : Map[@smithy.ShapeId, @smithy.NodeValue] = Map([])
    for id, value in shape.traits {
      let id = reference(id)
      if traits.contains(id) {
        raise InvalidBuildConfig(
          "Renaming shapes produced duplicate trait `" + id.to_string() + "`",
        )
      }
      traits[id] = rewrite_value(value, renamed)
    }
    fn renamed_traits(
      values : Map[@smithy.ShapeId, @smithy.NodeValue],
    ) -> Map[@smithy.ShapeId, @smithy.NodeValue] raise BuildError {
      let out : Map[@smithy.ShapeId, @smithy.NodeValue] = Map([])
      for id, value in values {
        out[reference(id)] = rewrite_value(value, renamed)
      }
      out
    }
    fn renamed_fields(
      values : Map[String, @smithy.NodeValue],
    ) -> Map[String, @smithy.NodeValue] raise BuildError {
      match rewrite_value(@smithy.Object(values), renamed) {
        @smithy.Object(fields) => fields
        _ => values
      }
    }
    let provenance = match shape.provenance {
      Some(origin) =>
        Some({
          ..origin,
          introduced_traits: renamed_traits(origin.introduced_traits),
          inherited_traits: renamed_traits(origin.inherited_traits),
          introduced_fields: renamed_fields(origin.introduced_fields),
          inherited_fields: renamed_fields(origin.inherited_fields),
        })
      None => None
    }
    shapes[updated_id] = {
      ..shape,
      id: updated_id,
      body,
      traits,
      mixins: shape.mixins.map(own_id),
      provenance,
    }
  }
  let metadata : Map[String, @smithy.NodeValue] = Map([])
  for name, value in model.metadata {
    let name = @smithy.ShapeId::parse(name)
      .map(reference)
      .map(id => id.to_string())
      .unwrap_or(name)
    if metadata.contains(name) {
      raise InvalidBuildConfig(
        "Renaming shapes produced duplicate metadata key `" + name + "`",
      )
    }
    metadata[name] = rewrite_value(value, renamed)
  }
  { shapes, metadata, }
}

///|
fn rewrite_enum_name(value : String) -> String? {
  let out = StringBuilder()
  let mut first = true
  let mut separator = false
  for c in value.iter() {
    let alpha = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
    let digit = c >= '0' && c <= '9'
    let sep = c == '-' ||
      c == '.' ||
      c == ':' ||
      c == '/' ||
      c == ' ' ||
      c == '\t' ||
      c == '\n' ||
      c == '\r' ||
      c.to_int() == 12 ||
      c.to_int() == 11
    if (!alpha && !digit && !sep) || (first && digit) {
      return None
    }
    if sep {
      if !separator {
        out.write_char('_')
      }
    } else {
      out.write_char(c)
    }
    first = false
    separator = sep
  }
  let name = out.to_string()
  if @smithy.ShapeId::parse("enum.name#Enum$" + name) is Some(_) {
    Some(name)
  } else {
    None
  }
}

///|
fn rewrite_upgrade_enum(
  shape : @smithy.Shape,
  synthesize : Bool,
) -> (@smithy.Shape, Array[@smithy.Shape])? {
  guard shape.body is @smithy.Simple(String) &&
    shape.trait_value("smithy.api#enum") is Some(@smithy.Array(definitions)) &&
    !definitions.is_empty() else {
    return None
  }
  let members : Map[@smithy.ShapeId, @smithy.Shape] = Map([])
  let ids : Array[@smithy.ShapeId] = []
  let unit = @smithy.ShapeId::parse("smithy.api#Unit").unwrap()
  for definition in definitions {
    guard definition is @smithy.Object(fields) &&
      fields.get("value") is Some(@smithy.String(value)) else {
      return None
    }
    let name = match fields.get("name") {
      Some(@smithy.String(name)) => Some(name)
      _ => if synthesize { rewrite_enum_name(value) } else { None }
    }
    guard name is Some(name) && shape.id.with_member(name) is Some(id) else {
      return None
    }
    let traits : Map[@smithy.ShapeId, @smithy.NodeValue] = Map([])
    traits[@smithy.ShapeId::parse("smithy.api#enumValue").unwrap()] = @smithy.String(
      value,
    )
    if fields.get("documentation") is Some(value) {
      traits[@smithy.ShapeId::parse("smithy.api#documentation").unwrap()] = value
    }
    if fields.get("tags") is Some(@smithy.Array(tags)) && !tags.is_empty() {
      traits[@smithy.ShapeId::parse("smithy.api#tags").unwrap()] = @smithy.Array(
        tags,
      )
      if tags.contains(@smithy.String("internal")) {
        traits[@smithy.ShapeId::parse("smithy.api#internal").unwrap()] = @smithy.Object(
          Map([]),
        )
      }
    }
    if fields.get("deprecated") == Some(@smithy.Boolean(true)) {
      traits[@smithy.ShapeId::parse("smithy.api#deprecated").unwrap()] = @smithy.Object(
        Map([]),
      )
    }
    if !members.contains(id) {
      ids.push(id)
    }
    members[id] = {
      id,
      body: @smithy.Member(target=unit),
      traits,
      mixins: [],
      provenance: None,
      source: shape.source,
    }
  }
  let traits = shape.traits.copy()
  traits.remove(@smithy.ShapeId::parse("smithy.api#enum").unwrap())
  Some(
    (
      {
        ..shape,
        body: @smithy.Enum(ids),
        traits,
        mixins: [],
        provenance: None,
      },
      ids.map(id => members.get(id).unwrap()),
    ),
  )
}

///|
fn rewrite_legacy_enum(
  model : @smithy.Model,
  members : Array[@smithy.ShapeId],
) -> @smithy.NodeValue {
  let definitions : Array[@smithy.NodeValue] = []
  for id in members {
    guard model.shapes.get(id) is Some(member_) else { continue }
    let fields : Map[String, @smithy.NodeValue] = Map([])
    fields["name"] = @smithy.String(id.member.unwrap_or(""))
    fields["value"] = member_
      .trait_value("smithy.api#enumValue")
      .unwrap_or(@smithy.String(id.member.unwrap_or("")))
    if member_.trait_value("smithy.api#documentation") is Some(value) {
      fields["documentation"] = value
    }
    if member_.trait_value("smithy.api#deprecated") is Some(_) {
      fields["deprecated"] = @smithy.Boolean(true)
    }
    let tags = match member_.trait_value("smithy.api#tags") {
      Some(@smithy.Array(tags)) => tags.copy()
      _ => []
    }
    if member_.trait_value("smithy.api#internal") is Some(_) &&
      !tags.contains(@smithy.String("internal")) {
      tags.push(@smithy.String("internal"))
    }
    if !tags.is_empty() {
      fields["tags"] = @smithy.Array(tags)
    }
    definitions.push(@smithy.Object(fields))
  }
  @smithy.Array(definitions)
}

///|
fn rewrite_types(
  model : @smithy.Model,
  types : Map[@smithy.ShapeId, String],
  synthesize : Bool,
) -> @smithy.Model raise BuildError {
  let shapes = model.shapes.copy()
  let unique = @smithy.ShapeId::parse("smithy.api#uniqueItems").unwrap()
  for id, target in types {
    guard model.shapes.get(id) is Some(shape) else { continue }
    let current_type = if shape.is_legacy_set() {
      "set"
    } else {
      shape.body.keyword()
    }
    if current_type == target {
      continue
    }
    let traits = shape.traits.copy()
    let mut replacement : @smithy.Shape? = None
    match (shape.body, target) {
      (@smithy.Simple(String), "enum") => {
        guard rewrite_upgrade_enum(shape, synthesize)
          is Some((updated, members)) else {
          raise InvalidBuildConfig(
            "Cannot convert string shape `" +
            id.to_string() +
            "` to enum without valid named enum definitions",
          )
        }
        for member_ in members {
          shapes[member_.id] = member_
        }
        replacement = Some(updated)
      }
      (@smithy.Structure(members), "union") =>
        replacement = Some({
          ..shape,
          body: @smithy.Union(members),
          mixins: [],
          provenance: None,
        })
      (@smithy.Union(members), "structure") =>
        replacement = Some({
          ..shape,
          body: @smithy.Structure(members),
          mixins: [],
          provenance: None,
        })
      (@smithy.List(_), "set") => {
        traits[unique] = @smithy.Object(Map([]))
        replacement = Some({
          ..shape,
          traits,
          mixins: [],
          provenance: Some({
            introduced_traits: traits,
            inherited_traits: Map([]),
            introduced_fields: Map([]),
            inherited_fields: Map([]),
            legacy_set: true,
          }),
        })
      }
      (@smithy.List(_), "list") if shape.is_legacy_set() =>
        replacement = Some({ ..shape, mixins: [], provenance: None, })
      (@smithy.Simple(_), target)
      | (@smithy.Enum(_), target)
      | (@smithy.IntEnum(_), target) =>
        if @smithy.SimpleType::of(target) is Some(kind) {
          if shape.body is @smithy.Enum(members) && target == "string" {
            traits[@smithy.ShapeId::parse("smithy.api#enum").unwrap()] = rewrite_legacy_enum(
              model, members,
            )
          }
          for member_ in shape_members(shape.body) {
            shapes.remove(member_)
          }
          traits.remove(
            @smithy.ShapeId::parse("smithy.synthetic#enum").unwrap(),
          )
          replacement = Some({
            ..shape,
            body: @smithy.Simple(kind),
            traits,
            mixins: [],
            provenance: None,
          })
        }
      _ => ()
    }
    guard replacement is Some(updated) else {
      raise InvalidBuildConfig(
        "Cannot convert `" +
        id.to_string() +
        "` from " +
        shape.body.keyword() +
        " to " +
        target,
      )
    }
    for member_id in shape_members(updated.body) {
      if shapes.get(member_id) is Some(member_) {
        shapes[member_id] = { ..member_, mixins: [], provenance: None, }
      }
    }
    shapes[id] = updated
  }
  { shapes, metadata: model.metadata, }
}

///|
fn transform_rewrite(
  model : @smithy.Model,
  transform : TransformConfig,
) -> @smithy.Model? raise BuildError {
  match transform.name {
    "renameShapes" => {
      let entries = config_object(transform.args, "renamed")
      if entries.is_empty() {
        raise InvalidBuildConfig("Expected non-empty `renamed` on renameShapes")
      }
      let renamed : Map[@smithy.ShapeId, @smithy.ShapeId] = Map([])
      for from, to in entries {
        let from = rewrite_shape_id(from)
        guard model.shapes.contains(from) else {
          raise InvalidBuildConfig(
            "Shape `" + from.to_string() + "` to rename does not exist",
          )
        }
        guard to is String(to) else {
          raise InvalidBuildConfig("Expected rename target to be a string")
        }
        renamed[from] = rewrite_shape_id(to)
      }
      Some(rewrite_rename(model, renamed))
    }
    "flattenNamespaces" => {
      guard config_string(transform.args, "service") is Some(service) &&
        config_string(transform.args, "namespace") is Some(target_namespace) else {
        raise InvalidBuildConfig(
          "Expected `service` and `namespace` on flattenNamespaces",
        )
      }
      let service_id = rewrite_shape_id(service)
      guard model.shapes.get(service_id) is Some(shape) &&
        shape.body is @smithy.Service(rename~, ..) else {
        raise InvalidBuildConfig(
          "Expected a service shape at `" + service + "`",
        )
      }
      let closure = shape_closure(model, [service_id], directed=false)
      let renamed : Map[@smithy.ShapeId, @smithy.ShapeId] = Map([])
      for id, _ in model.shapes {
        if id.namespace == "smithy.api" || !closure.contains(id) {
          continue
        }
        let root_name = rename.get(id).unwrap_or(id.name)
        let target = target_namespace +
          "#" +
          root_name +
          id.member.map(name => "$" + name).unwrap_or("")
        renamed[id] = rewrite_shape_id(target)
      }
      let tags = config_strings(transform.args, "includeTagged")
      for id, shape in model.shapes {
        if id.namespace == "smithy.api" || !shape_tagged(shape, tags) {
          continue
        }
        let target = rewrite_shape_id(
          target_namespace +
          "#" +
          id.name +
          id.member.map(name => "$" + name).unwrap_or(""),
        )
        if !renamed.values().any(existing => existing == target) {
          renamed[id] = target
        }
      }
      let result = rewrite_rename(model, renamed)
      let updated_id = renamed.get(service_id).unwrap_or(service_id)
      let shapes = result.shapes.copy()
      if shapes.get(updated_id) is Some(updated) &&
        updated.body
        is @smithy.Service(version~, operations~, resources~, errors~, ..) {
        shapes[updated_id] = {
          ..updated,
          body: @smithy.Service(
            version~,
            operations~,
            resources~,
            errors~,
            rename=Map([]),
          ),
        }
      }
      Some({ shapes, metadata: result.metadata, })
    }
    "changeTypes" => {
      let entries = config_object(transform.args, "shapeTypes")
      if entries.is_empty() {
        raise InvalidBuildConfig(
          "Expected non-empty `shapeTypes` on changeTypes",
        )
      }
      let types : Map[@smithy.ShapeId, String] = Map([])
      for id, target in entries {
        let id = rewrite_shape_id(id)
        guard target is String(target) &&
          (
            @smithy.SimpleType::of(target) is Some(_) ||
            [
              "enum", "intEnum", "list", "set", "map", "structure", "union", "operation",
              "resource", "service", "member",
            ].contains(target)
          ) else {
          raise InvalidBuildConfig(
            "Expected a valid shape type in `shapeTypes`",
          )
        }
        types[id] = target
      }
      Some(
        rewrite_types(
          model,
          types,
          rewrite_bool(transform.args, "synthesizeEnumNames"),
        ),
      )
    }
    "changeStringEnumsToEnumShapes" => {
      let synthesize = rewrite_bool(transform.args, "synthesizeNames")
      let shapes = model.shapes.copy()
      for id, shape in model.shapes {
        if rewrite_upgrade_enum(shape, synthesize) is Some((updated, members)) {
          shapes[id] = updated
          for member_ in members {
            shapes[member_.id] = member_
          }
        }
      }
      Some({ shapes, metadata: model.metadata, })
    }
    _ => None
  }
}
