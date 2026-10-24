///|
/// Rebuild inherited content after removing mixin relationships, without
/// running validation or reintroducing prelude shapes into projected models.
pub fn Model::remove_mixin_relationships(
  self : Model,
  removed : Array[ShapeId],
) -> Model raise {
  if !self.shapes
    .values()
    .any(shape => shape.mixins.iter().any(id => removed.contains(id.root()))) {
    return self
  }
  let document = self.to_json_ast(include_prelude=true, preserve_mixins=true)
  let assembly = Assembly::new()
  for id, shape in self.shapes {
    assembly.kinds[id.to_string()] = if shape.is_legacy_set() {
      "set"
    } else {
      shape.body.keyword()
    }
    assembly.locations[id.to_string()] = shape.source
  }
  for id, entry in document.shapes.unwrap_or(Map([])) {
    let source = self
      .get(id)
      .map(shape => shape.source)
      .unwrap_or(location("<transform>"))
    let fields = copy(object(@json.to_json(entry)))
    if entry.kind is Apply {
      let removed_member = self
        .get(id)
        .map(shape => shape.mixins.iter().any(id => removed.contains(id.root())))
        .unwrap_or(false)
      if !removed_member {
        assembly.applications.push({
          target: id,
          traits: object_field(fields, "traits"),
          source,
        })
      }
    } else {
      if fields.get("mixins") is Some(Array(mixins)) {
        let kept = mixins.filter(value => {
          string_field(object(value), "target")
          .bind(ShapeId::parse)
          .map(id => !removed.contains(id))
          .unwrap_or(true)
        })
        if kept.is_empty() {
          fields.remove("mixins")
        } else {
          fields["mixins"] = Json::array(kept)
        }
      }
      if self.get(id).map(shape => shape.is_legacy_set()).unwrap_or(false) {
        fields["type"] = Json::string("set")
      }
      assembly.raw[id] = { id, fields, source, }
      assembly.known.add(id)
    }
  }
  let flattened = assembly.flatten()
  let shapes : Map[ShapeId, Shape] = Map([])
  for _, raw in flattened {
    assembly.lower(raw, shapes, flattened)
  }
  // Restore the original locations even for member declarations represented as
  // apply entries in the preserved JSON AST.
  for id, shape in shapes {
    if self.shapes.get(id) is Some(original) {
      shapes[id] = { ..shape, source: original.source, }
    }
  }
  { shapes, metadata: self.metadata, }
}

///|
fn node_fields(fields : Map[String, Json]) -> Map[String, NodeValue] raise {
  let out : Map[String, NodeValue] = Map([])
  for key, value in fields {
    out[key] = NodeValue::from_json(value)
  }
  out
}

///|
fn Assembly::inherited_fields(
  _self : Assembly,
  raw : RawShape,
  finished : Map[String, RawShape],
) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([])
  let members : Map[String, Json] = Map([])
  let traits : Map[String, Json] = Map([])
  for reference_ in array_field(raw.fields, "mixins") {
    guard string_field(object(reference_), "target") is Some(id) &&
      finished.get(id) is Some(base) else {
      continue
    }
    let base_traits = object_field(base.fields, "traits")
    let local_traits = array_field(
      object(base_traits.get("smithy.api#mixin").unwrap_or(Json::null())),
      "localTraits",
    )
    for id, value in base_traits {
      if id != "smithy.api#mixin" && !local_traits.contains(Json::string(id)) {
        traits[id] = value
      }
    }
    for name, member_ in raw_members(base.fields) {
      let member_fields = copy(object(member_))
      let member_traits = copy(
        object_field(
          object(members.get(name).unwrap_or(Json::empty_object())),
          "traits",
        ),
      )
      override(member_traits, object_field(member_fields, "traits"))
      if !member_traits.is_empty() {
        member_fields["traits"] = Json::object(member_traits)
      }
      members[name] = Json::object(member_fields)
    }
    for key, value in base.fields {
      if ["type", "traits", "mixins", "members", "member", "key", "value"].contains(
          key,
        ) {
        continue
      }
      match (fields.get(key), value) {
        (Some(Array(a)), Array(b)) => fields[key] = Json::array(unique(a, b))
        (Some(Object(a)), Object(b)) => {
          let out = copy(a)
          override(out, b)
          fields[key] = Json::object(out)
        }
        _ => fields[key] = value
      }
    }
  }
  fields["type"] = raw.fields.get("type").unwrap_or(Json::null())
  set_members(fields, members)
  fields["traits"] = Json::object(traits)
  fields
}

///|
fn override(fields : Map[String, Json], incoming : Map[String, Json]) -> Unit {
  for key, value in incoming {
    fields[key] = value
  }
}

///|
fn unique(values : Array[Json], incoming : Array[Json]) -> Array[Json] {
  let out = values.copy()
  for value in incoming {
    if !out.contains(value) {
      out.push(value)
    }
  }
  out
}

///|
fn raw_members(fields : Map[String, Json]) -> Map[String, Json] {
  let kind = string_field(fields, "type").unwrap_or("")
  if kind == "list" || kind == "set" || kind == "map" {
    let out : Map[String, Json] = Map([])
    for key in ["member", "key", "value"] {
      if fields.get(key) is Some(value) {
        out[key] = value
      }
    }
    out
  } else {
    copy(object_field(fields, "members"))
  }
}

///|
fn set_members(fields : Map[String, Json], members : Map[String, Json]) -> Unit {
  let kind = string_field(fields, "type").unwrap_or("")
  if kind == "list" || kind == "set" || kind == "map" {
    for key, value in members {
      fields[key] = value
    }
  } else if ["structure", "union", "enum", "intEnum"].contains(kind) {
    fields["members"] = Json::object(members)
  }
}

///|
fn Assembly::merge_member(
  self : Assembly,
  out : Map[String, Json],
  name : String,
  incoming : Json,
  source : SourceLocation,
  parent : String,
) -> Unit {
  let fields = copy(object(incoming))
  if out.get(name) is Some(Object(old)) {
    if string_field(old, "target") is Some(a) &&
      string_field(fields, "target") is Some(b) &&
      a != b {
      self.problem(
        "SM-MODEL-008",
        "I found conflicting targets for member \{parent}$\{name}: \{a} and \{b}.",
        source,
        shape=parent + "$" + name,
      )
    }
    let merged = copy(old)
    override(merged, fields)
    let traits = copy(object_field(old, "traits"))
    override(traits, object_field(fields, "traits"))
    if !traits.is_empty() {
      merged["traits"] = Json::object(traits)
    }
    out[name] = Json::object(merged)
  } else {
    out[name] = incoming
  }
}

///|
fn Assembly::apply_roots(self : Assembly) -> Unit {
  for application in self.applications {
    guard ShapeId::parse(application.target) is Some(id) else {
      self.problem(
        "SM-MODEL-002",
        "I expected an absolute apply target, but found \{application.target}.",
        application.source,
      )
      continue
    }
    let builtin = self.raw
      .get(id.root().to_string())
      .map(r => r.source.is_builtin())
      .unwrap_or(false)
    if (id.namespace == "smithy.api" || builtin) &&
      !application.source.is_builtin() {
      self.problem(
        "SM-MODEL-014",
        "I cannot apply traits to the built-in shape \{id}.",
        application.source,
        shape=application.target,
      )
      continue
    }
    if id.member is Some(_) {
      if !self.raw.contains(id.root().to_string()) {
        self.problem(
          "SM-MODEL-013",
          "I could not resolve the apply target \{application.target}.",
          application.source,
          shape=application.target,
        )
      }
      continue
    }
    guard self.raw.get(application.target) is Some(raw) else {
      self.problem(
        "SM-MODEL-013",
        "I could not resolve the apply target \{application.target}.",
        application.source,
        shape=application.target,
      )
      continue
    }
    let traits = copy(object_field(raw.fields, "traits"))
    self.merge_traits(traits, application.traits, application.source, raw.id)
    if !traits.is_empty() {
      raw.fields["traits"] = Json::object(traits)
    }
  }
}

///|
fn Assembly::flatten_one(
  self : Assembly,
  raw : RawShape,
  finished : Map[String, RawShape],
) -> RawShape {
  let fields : Map[String, Json] = {
    "type": raw.fields.get("type").unwrap_or(Json::null()),
  }
  let traits : Map[String, Json] = Map([])
  let members : Map[String, Json] = Map([])
  let kind = string_field(raw.fields, "type").unwrap_or("")
  let mixin_ids = array_field(raw.fields, "mixins")
  let seen : Set[String] = Set([])
  for mixin in mixin_ids {
    guard string_field(object(mixin), "target") is Some(id) else { continue }
    if seen.contains(id) {
      self.problem(
        "SM-MODEL-008",
        "I found the duplicate mixin \{id} on \{raw.id}.",
        raw.source,
        shape=raw.id,
      )
    }
    seen.add(id)
    guard finished.get(id) is Some(base) else { continue }
    let base_traits = object_field(base.fields, "traits")
    if !base_traits.contains("smithy.api#mixin") {
      self.problem(
        "SM-MODEL-008",
        "I expected a \{kind} mixin for \{raw.id}, but found \{id}.",
        raw.source,
        shape=raw.id,
        event_id="Target",
      )
      continue
    }
    if string_field(base.fields, "type") != Some(kind) {
      self.problem(
        "SM-MODEL-008",
        "I expected a \{kind} mixin for \{raw.id}, but found \{id}.",
        raw.source,
        shape=raw.id,
      )
      continue
    }
    let local_traits = array_field(
      object(base_traits.get("smithy.api#mixin").unwrap_or(Json::null())),
      "localTraits",
    )
    for key, value in base_traits {
      if key != "smithy.api#mixin" && !local_traits.contains(Json::string(key)) {
        traits[key] = value
      }
    }
    for name, member_ in raw_members(base.fields) {
      self.merge_member(members, name, member_, raw.source, raw.id)
    }
    for key, value in base.fields {
      if ["type", "traits", "mixins", "members", "member", "key", "value"].contains(
          key,
        ) {
        continue
      }
      match (fields.get(key), value) {
        (Some(Array(a)), Array(b)) => fields[key] = Json::array(unique(a, b))
        (Some(Object(a)), Object(b)) => {
          let merged = copy(a)
          override(merged, b)
          fields[key] = Json::object(merged)
        }
        _ => fields[key] = value
      }
    }
  }
  let locals = raw_members(raw.fields)
  let resource = self.bindings.get(raw.id).bind(id => finished.get(id))
  if self.bindings.get(raw.id) is Some(id) && resource is None {
    self.problem(
      "SM-MODEL-012",
      "I could not resolve resource binding \{id} for \{raw.id}.",
      raw.source,
      shape=raw.id,
    )
  }
  if resource is Some(resource) &&
    string_field(resource.fields, "type") != Some("resource") {
    self.problem(
      "SM-MODEL-005",
      "I expected a resource binding for \{raw.id}, but found \{resource.id}.",
      raw.source,
      shape=raw.id,
    )
  }
  for name, value in locals {
    let member_ = copy(object(value))
    if resource is Some(resource) &&
      string_field(member_, "target") is Some(explicit) {
      let candidate = match
        object_field(resource.fields, "identifiers").get(name) {
        Some(value) => Some(value)
        None => object_field(resource.fields, "properties").get(name)
      }
      if candidate.bind(v => string_field(object(v), "target"))
        is Some(expected) &&
        explicit != expected {
        self.problem(
          "SM-MODEL-012",
          "I expected resource-bound member \{raw.id}$\{name} to target \{expected}, but found \{explicit}.",
          raw.source,
          shape=raw.id,
        )
      }
    }
    if !member_.contains("target") {
      let inherited = members
        .get(name)
        .bind(v => string_field(object(v), "target"))
      let bound = resource.bind(r => {
        let value = match object_field(r.fields, "identifiers").get(name) {
          Some(value) => Some(value)
          None => object_field(r.fields, "properties").get(name)
        }
        value.bind(v => string_field(object(v), "target"))
      })
      if inherited is Some(a) && bound is Some(b) && a != b {
        self.problem(
          "SM-MODEL-012",
          "I found conflicting mixin and resource targets for \{raw.id}$\{name}.",
          raw.source,
          shape=raw.id,
        )
      }
      match (if bound is Some(_) { bound } else { inherited }) {
        Some(target) => member_["target"] = Json::string(target)
        None =>
          self.problem(
            "SM-MODEL-012",
            "I could not infer a target for the elided member \{raw.id}$\{name}.",
            self.locations.get(raw.id + "$" + name).unwrap_or(raw.source),
            shape=raw.id,
          )
      }
    }
    self.merge_member(members, name, Json::object(member_), raw.source, raw.id)
  }
  // External applications override inherited traits, and conflict with direct
  // local applications exactly as traits written on the member do.
  let external : Map[String, Map[String, Json]] = Map([])
  for application in self.applications {
    guard ShapeId::parse(application.target) is Some(id) &&
      id.root().to_string() == raw.id &&
      id.member is Some(name) else {
      continue
    }
    if raw.source.is_builtin() && !application.source.is_builtin() {
      continue
    }
    guard members.get(name) is Some(Object(member_)) else {
      self.problem(
        "SM-MODEL-013",
        "I could not resolve the apply target \{application.target}.",
        application.source,
        shape=application.target,
      )
      continue
    }
    let direct = external
      .get(name)
      .unwrap_or_else(() => {
        copy(
          object_field(
            object(locals.get(name).unwrap_or(Json::null())),
            "traits",
          ),
        )
      })
    self.merge_traits(
      direct,
      application.traits,
      application.source,
      application.target,
    )
    external[name] = direct
    let ts = copy(object_field(member_, "traits"))
    override(ts, direct)
    let member_ = copy(member_)
    member_["traits"] = Json::object(ts)
    members[name] = Json::object(member_)
  }
  override(traits, object_field(raw.fields, "traits"))
  for key, value in raw.fields {
    if ["type", "traits", "members", "member", "key", "value"].contains(key) {
      continue
    }
    match (fields.get(key), value) {
      (Some(Array(a)), Array(b)) if key != "mixins" =>
        fields[key] = Json::array(unique(a, b))
      (Some(Object(a)), Object(b)) => {
        let merged = copy(a)
        override(merged, b)
        fields[key] = Json::object(merged)
      }
      _ => fields[key] = value
    }
  }
  if !traits.is_empty() {
    fields["traits"] = Json::object(traits)
  }
  if kind == "enum" {
    for name, value in members {
      let m = copy(object(value))
      let ts = copy(object_field(m, "traits"))
      if !ts.contains("smithy.api#enumValue") {
        ts["smithy.api#enumValue"] = Json::string(name)
      }
      m["traits"] = Json::object(ts)
      members[name] = Json::object(m)
    }
  }
  set_members(fields, members)
  { ..raw, fields, }
}

///|
fn Assembly::flatten(self : Assembly) -> Map[String, RawShape] {
  let finished : Map[String, RawShape] = Map([])
  let active : Set[String] = Set([])
  for root, _ in self.raw {
    let stack = [(root, false)]
    while stack.pop() is Some((id, leaving)) {
      if finished.contains(id) {
        continue
      }
      guard self.raw.get(id) is Some(raw) else { continue }
      if leaving {
        finished[id] = self.flatten_one(raw, finished)
        active.remove(id)
        continue
      }
      if active.contains(id) {
        self.problem(
          "SM-MODEL-009",
          "I found a cycle while resolving mixins or resource bindings at \{id}.",
          raw.source,
          shape=id,
        )
        continue
      }
      active.add(id)
      stack.push((id, true))
      let dependencies : Array[String] = []
      for mixin in array_field(raw.fields, "mixins") {
        if string_field(object(mixin), "target") is Some(target) {
          dependencies.push(target)
        }
      }
      if self.bindings.get(id) is Some(resource) {
        dependencies.push(resource)
      }
      for dependency in dependencies.rev() {
        if !self.raw.contains(dependency) {
          self.problem(
            "SM-MODEL-004",
            "I could not resolve dependency \{dependency} of \{id}.",
            raw.source,
            shape=id,
          )
        } else if !finished.contains(dependency) {
          stack.push((dependency, false))
        }
      }
    }
  }
  finished
}
