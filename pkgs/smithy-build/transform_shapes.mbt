///|
fn shape_tagged(shape : @smithy.Shape, tags : Array[String]) -> Bool {
  match shape.trait_value("smithy.api#tags") {
    Some(@smithy.Array(values)) =>
      values
      .iter()
      .any(v => {
        match v {
          @smithy.String(tag) => tags.contains(tag)
          _ => false
        }
      })
    _ => false
  }
}

///|
fn shape_members(body : @smithy.ShapeBody) -> Array[@smithy.ShapeId] {
  match body {
    @smithy.List(member_) => [member_]
    @smithy.Map(key~, value~) => [key, value]
    @smithy.Structure(m)
    | @smithy.Union(m)
    | @smithy.Enum(m)
    | @smithy.IntEnum(m) => m
    _ => []
  }
}

///|
// Default neighbor relationships exclude traits and include mixins. The stack
// deliberately lives here so closures and detached recursive shapes terminate.
fn shape_targets(shape : @smithy.Shape) -> Array[@smithy.ShapeId] {
  let out = if shape.body is @smithy.Member(..) {
    []
  } else {
    shape.mixins.copy()
  }
  match shape.body {
    @smithy.Member(target~) => out.push(target)
    @smithy.Operation(input~, output~, errors~) => {
      out.push(input)
      out.push(output)
      out.append(errors)
    }
    @smithy.Service(operations~, resources~, errors~, ..) => {
      out.append(operations)
      out.append(resources)
      out.append(errors)
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
    ) => {
      for _, target in identifiers {
        out.push(target)
      }
      for _, target in properties {
        out.push(target)
      }
      for target in [create, put, read, update, delete, list] {
        if target is Some(target) {
          out.push(target)
        }
      }
      out.append(operations)
      out.append(collectionOperations)
      out.append(resources)
    }
    _ => out.append(shape_members(shape.body))
  }
  out
}

///|
fn shape_closure(
  model : @smithy.Model,
  roots : Array[@smithy.ShapeId],
  id_refs~ : Bool = false,
  directed~ : Bool = true,
) -> Map[@smithy.ShapeId, Bool] {
  let seen : Map[@smithy.ShapeId, Bool] = Map([])
  let pending = roots.copy()
  while pending.pop() is Some(id) {
    if seen.contains(id) {
      continue
    }
    seen[id] = true
    if model.shapes.get(id) is Some(shape) {
      let enum_member = id.member is Some(_) &&
        model.shapes
        .get(id.root())
        .map(s => s.body is (@smithy.Enum(_) | @smithy.IntEnum(_)))
        .unwrap_or(false)
      if !enum_member {
        pending.append(shape_targets(shape))
      }
      if !directed && id.member is Some(_) {
        pending.push(id.root())
      }
      if id_refs {
        for trait_id, value in shape.traits {
          pending.append(shape_id_refs(model, trait_id, value))
        }
      }
    }
  }
  seen
}

///|
// Follow the schema and the finite trait value together. Recursive schemas
// consume a value at each aggregate edge, so they cannot create a cycle.
fn shape_id_refs(
  model : @smithy.Model,
  schema : @smithy.ShapeId,
  value : @smithy.NodeValue,
) -> Array[@smithy.ShapeId] {
  let out : Array[@smithy.ShapeId] = []
  let pending : Array[(@smithy.ShapeId, @smithy.NodeValue)] = [(schema, value)]
  while pending.pop() is Some((id, value)) {
    guard model.shapes.get(id) is Some(shape) else { continue }
    if shape.trait_value("smithy.api#idRef") is Some(_) &&
      value is @smithy.String(text) &&
      @smithy.ShapeId::parse(text) is Some(target) {
      out.push(target)
    }
    match (shape.body, value) {
      (@smithy.Member(target~), value) => pending.push((target, value))
      (
        @smithy.Structure(members)
        | @smithy.Union(members),
        @smithy.Object(fields),
      ) =>
        for member_ in members {
          if member_.member is Some(name) && fields.get(name) is Some(value) {
            pending.push((member_, value))
          }
        }
      (@smithy.List(member_), @smithy.Array(values)) =>
        for value in values {
          pending.push((member_, value))
        }
      (@smithy.Map(key~, value=member_), @smithy.Object(fields)) =>
        for name, value in fields {
          pending.push((key, @smithy.String(name)))
          pending.push((member_, value))
        }
      _ => ()
    }
  }
  out
}

///|
fn shape_remove(
  model : @smithy.Model,
  removed : Map[@smithy.ShapeId, Bool],
) -> @smithy.Model raise BuildError {
  let removed_mixins : Array[@smithy.ShapeId] = []
  for id, shape in model.shapes {
    if removed.contains(id) && shape.trait_value("smithy.api#mixin") is Some(_) {
      removed_mixins.push(id)
    }
  }
  let model = model.remove_mixin_relationships(removed_mixins) catch {
    _ =>
      raise InvalidBuildConfig("Could not rebuild shapes after removing mixins")
  }
  // Removing an aggregate also removes its member shapes. Removing a target
  // removes structure/union members, while collection members are preserved,
  // as in the reference FilterShapes and CleanStructureAndUnionMembers.
  let mut changed = true
  while changed {
    changed = false
    for id, shape in model.shapes {
      if removed.contains(id) {
        continue
      }
      let remove = if id.member is Some(_) && removed.contains(id.root()) {
        true
      } else if shape.body is @smithy.Member(target~) &&
        removed.contains(target) {
        model.shapes
        .get(id.root())
        .map(parent => parent.body is (@smithy.Structure(_) | @smithy.Union(_)))
        .unwrap_or(false)
      } else {
        false
      }
      if remove {
        removed[id] = true
        changed = true
      }
    }
  }
  let shapes : Map[@smithy.ShapeId, @smithy.Shape] = Map([])
  let unit = @smithy.ShapeId::parse("smithy.api#Unit").unwrap()
  fn keep(ids : Array[@smithy.ShapeId]) -> Array[@smithy.ShapeId] {
    ids.filter(id => !removed.contains(id))
  }
  fn keep_opt(id : @smithy.ShapeId?) -> @smithy.ShapeId? {
    id.bind(id => if removed.contains(id) { None } else { Some(id) })
  }
  for id, shape in model.shapes {
    if removed.contains(id) {
      continue
    }
    let traits : Map[@smithy.ShapeId, @smithy.NodeValue] = Map([])
    for trait_id, value in shape.traits {
      if !removed.contains(trait_id) ||
        !model.shapes
        .get(trait_id)
        .map(s => s.trait_value("smithy.api#trait") is Some(_))
        .unwrap_or(false) {
        if shape_clean_trait(shape, trait_id.to_string(), value, removed)
          is Some(cleaned) {
          traits[trait_id] = cleaned
        }
      }
    }
    let enum_value = @smithy.ShapeId::parse("smithy.api#enumValue").unwrap()
    if shape.body is @smithy.Member(..) &&
      !traits.contains(enum_value) &&
      model.shapes
      .get(id.root())
      .map(parent => parent.body is @smithy.Enum(_))
      .unwrap_or(false) {
      traits[enum_value] = @smithy.String(id.member.unwrap_or(""))
    }
    let body = match shape.body {
      @smithy.Structure(m) => @smithy.Structure(keep(m))
      @smithy.Union(m) => @smithy.Union(keep(m))
      @smithy.Enum(m) => @smithy.Enum(keep(m))
      @smithy.IntEnum(m) => @smithy.IntEnum(keep(m))
      @smithy.Operation(input~, output~, errors~) =>
        @smithy.Operation(
          input=if removed.contains(input) { unit } else { input },
          output=if removed.contains(output) { unit } else { output },
          errors=keep(errors),
        )
      @smithy.Service(version~, operations~, resources~, errors~, rename~) => {
        let names : Map[@smithy.ShapeId, String] = Map([])
        for target, name in rename {
          if !removed.contains(target) {
            names[target] = name
          }
        }
        @smithy.Service(
          version~,
          operations=keep(operations),
          resources=keep(resources),
          errors=keep(errors),
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
          identifiers~,
          properties~,
          create=keep_opt(create),
          put=keep_opt(put),
          read=keep_opt(read),
          update=keep_opt(update),
          delete=keep_opt(delete),
          list=keep_opt(list),
          operations=keep(operations),
          collectionOperations=keep(collectionOperations),
          resources=keep(resources),
        )
      other => other
    }
    shapes[id] = { ..shape, body, traits, mixins: keep(shape.mixins), }
  }
  { shapes, metadata: model.metadata, }
}

///|
fn shape_clean_trait(
  shape : @smithy.Shape,
  trait_id : String,
  value : @smithy.NodeValue,
  removed : Map[@smithy.ShapeId, Bool],
) -> @smithy.NodeValue? {
  fn is_removed(value : @smithy.NodeValue) -> Bool {
    if value is @smithy.String(text) && @smithy.ShapeId::parse(text) is Some(id) {
      removed.contains(id)
    } else {
      false
    }
  }
  if shape.body is @smithy.Structure(_) &&
    ["smithy.api#authDefinition", "smithy.api#protocolDefinition"].contains(
      trait_id,
    ) &&
    value is @smithy.Object(fields) &&
    fields.get("traits") is Some(@smithy.Array(values)) {
    let out = fields.copy()
    out["traits"] = @smithy.Array(values.filter(value => !is_removed(value)))
    return Some(@smithy.Object(out))
  }
  let references = shape.body is @smithy.Structure(_) &&
    trait_id == "smithy.api#references"
  let lifecycle = shape.body is @smithy.Operation(..) &&
    [
      "smithy.api#createsResources", "smithy.api#putsResources", "smithy.api#readsResources",
      "smithy.api#updatesResources", "smithy.api#deletesResources",
    ].contains(trait_id)
  if (references || lifecycle) && value is @smithy.Array(values) {
    let kept = values.filter(value => {
      match value {
        @smithy.Object(fields) =>
          !fields.get("resource").map(is_removed).unwrap_or(false)
        _ => true
      }
    })
    if lifecycle && kept.is_empty() && !values.is_empty() {
      return None
    }
    return Some(@smithy.Array(kept))
  }
  Some(value)
}

///|
fn shape_filter(
  model : @smithy.Model,
  predicate : (@smithy.Shape) -> Bool,
) -> @smithy.Model raise BuildError {
  let removed : Map[@smithy.ShapeId, Bool] = Map([])
  for id, shape in model.shapes {
    if id.namespace == "smithy.api" {
      continue
    }
    if id.member is Some(_) {
      let eligible = model.shapes
        .get(id.root())
        .map(s => {
          s.body
          is (@smithy.Structure(_)
          | @smithy.Union(_)
          | @smithy.Enum(_)
          | @smithy.IntEnum(_))
        })
        .unwrap_or(false)
      if !eligible {
        continue
      }
    }
    if !predicate(shape) {
      removed[id] = true
    }
  }
  shape_remove(model, removed)
}

///|
fn shape_select(
  model : @smithy.Model,
  text : String,
) -> Array[String] raise BuildError {
  let selector = @smithy.Selector::parse(text) catch {
    _ => raise InvalidBuildConfig("Invalid projection selector `" + text + "`")
  }
  selector.select_ids(model)
}

///|
fn shape_date(text : String) -> String? {
  let digits = text.replace_all(old="-", new="")
  if digits.length() != 8 ||
    (text.length() != 8 && text.length() != 10) ||
    !digits.iter().all(c => c >= '0' && c <= '9') {
    return None
  }
  if text.length() == 10 && (text[4] != 45 || text[7] != 45) {
    return None
  }
  let month = digits[4:6].to_owned()
  let day = digits[6:8].to_owned()
  if month < "01" || month > "12" || day < "01" || day > "31" {
    None
  } else {
    Some(digits)
  }
}

///|
fn shape_semver(text : String) -> Array[String]? {
  let build = text.split("+").to_array()
  if build.length() > 2 {
    return None
  }
  fn valid_ident(s : String) -> Bool {
    s != "" &&
    s
    .iter()
    .all(c => {
      (c >= '0' && c <= '9') ||
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      c == '-'
    })
  }
  if build.length() == 2 &&
    !build[1].split(".").all(s => valid_ident(s.to_owned())) {
    return None
  }
  let main = build[0].to_owned()
  let parts = main.split("-").to_array()
  let core = parts[0].split(".").to_array()
  if core.length() != 3 ||
    !core
    .iter()
    .all(s => {
      s.length() > 0 &&
      s.iter().all(c => c >= '0' && c <= '9') &&
      (s.length() == 1 || s[0] != 48)
    }) {
    return None
  }
  if parts.length() > 1 {
    let suffix = main[core[0].length() + core[1].length() + core[2].length() + 3:].to_owned()
    if !suffix
      .split(".")
      .all(s => {
        valid_ident(s.to_owned()) &&
        !(s.length() > 1 &&
        s[0] == 48 &&
        s.iter().all(c => c >= '0' && c <= '9'))
      }) {
      return None
    }
  }
  // Match the Java transform's component-wise lexical comparison, including
  // prerelease and build suffixes, rather than substituting numeric SemVer.
  Some(text.split(".").map(s => s.to_owned()).to_array())
}

///|
fn shape_version_after(a : Array[String], b : Array[String]) -> Bool {
  let count = if a.length() > b.length() { a.length() } else { b.length() }
  for i in 0..<count {
    let left = a.get(i).unwrap_or("0")
    let right = b.get(i).unwrap_or("0")
    if left != right {
      return left > right
    }
  }
  false
}

///|
fn transform_shape_filter(
  model : @smithy.Model,
  transform : TransformConfig,
) -> @smithy.Model? raise BuildError {
  let legacy_key = match transform.name {
    "includeShapesByTag" | "excludeShapesByTag" => Some("tags")
    "includeNamespaces" => Some("namespaces")
    "includeServices" => Some("services")
    "includeClosures" => Some("closures")
    "removeUnusedShapes" => Some("exportTagged")
    _ => None
  }
  let args = if legacy_key is Some(key) {
    match transform.args {
      Array(values) => {
        let out : Map[String, Json] = Map([])
        out[key] = Json::array(values)
        Json::object(out)
      }
      Object(fields) =>
        if fields.get("__args") is Some(values) {
          let out = fields.copy()
          out.remove("__args")
          out[key] = values
          Json::object(out)
        } else {
          transform.args
        }
      _ => transform.args
    }
  } else {
    transform.args
  }
  match transform.name {
    "includeShapesBySelector" | "excludeShapesBySelector" => {
      guard config_string(args, "selector") is Some(text) else {
        raise InvalidBuildConfig("Expected `selector` to be a string")
      }
      let selected = shape_select(model, text)
      Some(
        shape_filter(model, s => {
          selected.contains(s.id.to_string()) ==
          (transform.name == "includeShapesBySelector")
        }),
      )
    }
    "includeShapesByTag" | "excludeShapesByTag" => {
      let tags = config_strings(args, "tags")
      Some(
        shape_filter(model, s => {
          shape_tagged(s, tags) == (transform.name == "includeShapesByTag")
        }),
      )
    }
    "excludeShapesByTrait" => {
      let names = config_strings(args, "traits").map(transform_trait_id)
      for name in names {
        if @smithy.ShapeId::parse(name) is None {
          raise InvalidBuildConfig("Invalid trait shape ID `" + name + "`")
        }
      }
      Some(
        shape_filter(model, s => {
          !names.iter().any(name => s.trait_value(name) is Some(_))
        }),
      )
    }
    "includeNamespaces" => {
      let names = config_strings(args, "namespaces")
      Some(shape_filter(model, s => names.contains(s.id.namespace)))
    }
    "includeServices" => {
      let names = config_strings(args, "services")
      for name in names {
        if @smithy.ShapeId::parse(name) is None {
          raise InvalidBuildConfig("Invalid service shape ID `" + name + "`")
        }
      }
      Some(
        shape_filter(model, s => {
          !(s.body is @smithy.Service(..)) || names.contains(s.id.to_string())
        }),
      )
    }
    "includeClosures" => {
      let names = config_strings(args, "closures")
      if names.is_empty() {
        raise InvalidBuildConfig("Expected non-empty `closures`")
      }
      let roots : Array[@smithy.ShapeId] = []
      let closures = model.metadata
        .get("shapeClosures")
        .map(@json.to_json)
        .unwrap_or(Json::array([]))
      for name in names {
        let mut found : Json? = None
        if closures is Array(entries) {
          for entry in entries {
            if config_string(entry, "id") == Some(name) {
              found = Some(entry)
            }
          }
        }
        guard found is Some(closure) else {
          raise InvalidBuildConfig(
            "No shape closure named `" + name + "` is defined in the model",
          )
        }
        let namespaces = config_strings(closure, "includeNamespaces")
        for id, _ in model.shapes {
          if namespaces.contains(id.namespace) {
            roots.push(id)
          }
        }
        if config_string(closure, "includeBySelector") is Some(text) {
          for text in shape_select(model, text) {
            if @smithy.ShapeId::parse(text) is Some(id) {
              roots.push(id)
            }
          }
        }
      }
      let included = shape_closure(model, roots)
      Some(shape_filter(model, s => included.contains(s.id)))
    }
    "removeDeprecatedShapes" => {
      let date = config_string(args, "relativeDate")
      let version = config_string(args, "relativeVersion")
      for key in ["relativeDate", "relativeVersion"] {
        if config_field(args, key) is Some(value) &&
          !(value is String(_)) &&
          value != Json::null() {
          raise InvalidBuildConfig("Expected `" + key + "` to be a string")
        }
      }
      let date = match date {
        Some(text) =>
          Some(
            shape_date(text).unwrap_or_else(() => {
              raise InvalidBuildConfig("Invalid relativeDate `" + text + "`")
            }),
          )
        None => None
      }
      let version = match version {
        Some(text) =>
          Some(
            shape_semver(text).unwrap_or_else(() => {
              raise InvalidBuildConfig("Invalid relativeVersion `" + text + "`")
            }),
          )
        None => None
      }
      let removed : Map[@smithy.ShapeId, Bool] = Map([])
      for id, shape in model.shapes {
        if shape.trait_value("smithy.api#deprecated") is Some(value) &&
          config_string(@json.to_json(value), "since") is Some(since) {
          let old_date = match (date, shape_date(since)) {
            (Some(limit), Some(value)) => value < limit
            _ => false
          }
          let old_version = match (version, shape_semver(since)) {
            (Some(limit), Some(value)) => shape_version_after(limit, value)
            _ => false
          }
          if old_date || old_version {
            removed[id] = true
          }
        }
      }
      Some(shape_remove(model, removed))
    }
    "flattenAndRemoveMixins" => {
      let shapes : Map[@smithy.ShapeId, @smithy.Shape] = Map([])
      for id, shape in model.shapes {
        if model.shapes
          .get(id.root())
          .map(s => s.trait_value("smithy.api#mixin") is Some(_))
          .unwrap_or(false) {
          continue
        }
        shapes[id] = {
          ..shape,
          mixins: [],
          provenance: if shape.is_legacy_set() {
            shape.provenance
          } else {
            None
          },
        }
      }
      Some({ shapes, metadata: model.metadata, })
    }
    "removeUnusedShapes" =>
      Some(shape_remove_unused(model, config_strings(args, "exportTagged")))
    "removeTraitDefinitions" =>
      Some(
        shape_remove_trait_definitions(
          model,
          config_strings(args, "exportTagged"),
        ),
      )
    _ => None
  }
}

///|
fn shape_remove_unused(
  model : @smithy.Model,
  tags : Array[String],
) -> @smithy.Model raise BuildError {
  let mut result = model
  while true {
    let count = result.shapes.length()
    let roots : Array[@smithy.ShapeId] = []
    for id, shape in result.shapes {
      if shape.body is @smithy.Service(..) ||
        shape.trait_value("smithy.api#trait") is Some(_) ||
        shape.trait_value("smithy.api#metadata") is Some(_) {
        roots.push(id)
      }
    }
    let connected = shape_closure(result, roots, id_refs=true, directed=false)
    let removed : Map[@smithy.ShapeId, Bool] = Map([])
    for id, shape in result.shapes {
      if id.member is None &&
        id.namespace != "smithy.api" &&
        !connected.contains(id) &&
        !shape_tagged(shape, tags) {
        removed[id] = true
      }
    }
    result = shape_remove(result, removed)
    let services : Array[@smithy.ShapeId] = []
    for id, shape in result.shapes {
      if shape.body is @smithy.Service(..) {
        services.push(id)
      }
    }
    let connected = shape_closure(result, services, directed=false)
    let used : Map[@smithy.ShapeId, Bool] = Map([])
    let pending : Array[@smithy.ShapeId] = []
    for id, shape in result.shapes {
      if connected.contains(id) {
        for trait_id, _ in shape.traits {
          pending.push(trait_id)
        }
      }
    }
    while pending.pop() is Some(id) {
      if used.contains(id) {
        continue
      }
      used[id] = true
      if result.shapes.get(id) is Some(shape) {
        for trait_id, _ in shape.traits {
          if trait_id.to_string() != "smithy.api#trait" {
            pending.push(trait_id)
          }
        }
      }
    }
    let removed : Map[@smithy.ShapeId, Bool] = Map([])
    for id, shape in result.shapes {
      if id.namespace != "smithy.api" &&
        shape.trait_value("smithy.api#trait") is Some(_) &&
        (!used.contains(id) || shape_tagged(shape, tags)) {
        removed[id] = true
      }
    }
    result = shape_remove(result, removed)
    if result.shapes.length() == count {
      break
    }
  }
  result
}

///|
fn shape_remove_trait_definitions(
  model : @smithy.Model,
  tags : Array[String],
) -> @smithy.Model {
  let removed : Map[@smithy.ShapeId, Bool] = Map([])
  for id, shape in model.shapes {
    if (
        shape.trait_value("smithy.api#trait") is Some(_) &&
        !shape_tagged(shape, tags)
      ) ||
      (
        id.namespace == "smithy.api" &&
        shape.trait_value("smithy.api#private") is Some(_)
      ) {
      removed[id] = true
      for member_ in shape_members(shape.body) {
        removed[member_] = true
      }
    }
  }
  // Mark and sweep only shapes whose incoming directed relationships all
  // originate in the removed graph. Self-recursive members do not count.
  let mut changed = true
  while changed {
    changed = false
    for id, shape in model.shapes {
      if removed.contains(id) ||
        id.member is Some(_) ||
        (
          id.namespace == "smithy.api" &&
          shape.trait_value("smithy.api#trait") is None &&
          shape.trait_value("smithy.api#private") is None
        ) {
        continue
      }
      let mut incoming = false
      let mut alive = false
      for from, parent in model.shapes {
        if from.root() == id && from.member is Some(_) {
          continue
        }
        if shape_targets(parent).contains(id) &&
          !shape_members(parent.body).contains(id) {
          incoming = true
          if !removed.contains(from) {
            alive = true
            break
          }
        }
      }
      if incoming && !alive {
        removed[id] = true
        for member_ in shape_members(shape.body) {
          removed[member_] = true
        }
        changed = true
      }
    }
  }
  let shapes : Map[@smithy.ShapeId, @smithy.Shape] = Map([])
  for id, shape in model.shapes {
    if !removed.contains(id) {
      shapes[id] = shape
    }
  }
  // getModelWithoutTraitShapes intentionally restores the original shapes and
  // omits metadata, preserving applications of removed trait definitions.
  { shapes, metadata: Map([]), }
}
