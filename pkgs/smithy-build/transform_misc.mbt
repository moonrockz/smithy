///|
fn misc_args(
  transform : TransformConfig,
  key : String,
) -> Json raise BuildError {
  let out : Map[String, Json] = Map([])
  match transform.args {
    Array(values) => out[key] = Json::array(values)
    Object(fields) => {
      for name, value in fields {
        if name != "__args" {
          out[name] = value
        }
      }
      if fields.get("__args") is Some(value) {
        out[key] = value
      }
    }
    _ =>
      raise InvalidBuildConfig("Expected transform arguments to be an object")
  }
  Json::object(out)
}

///|
fn misc_validator_ids(model : @smithy.Model) -> Array[String] {
  let out : Array[String] = []
  if model.metadata.get("validators") is Some(@smithy.Array(values)) {
    for value in values {
      if value is @smithy.Object(fields) {
        let value = match fields.get("id") {
          Some(value) => Some(value)
          None => fields.get("name")
        }
        match value {
          Some(@smithy.String(name)) => out.push(name)
          _ => ()
        }
      }
    }
  }
  out
}

///|
fn misc_filter_suppressions(
  model : @smithy.Model,
  args : Json,
  original : @smithy.Model,
  original_events : Array[@smithy.ValidationEvent],
) -> @smithy.Model raise BuildError {
  let events_allow = config_strings(args, "eventIdAllowList")
  let events_deny = config_strings(args, "eventIdDenyList")
  let namespaces_allow = config_strings(args, "namespaceAllowList")
  let namespaces_deny = config_strings(args, "namespaceDenyList")
  if !events_allow.is_empty() && !events_deny.is_empty() {
    raise InvalidBuildConfig(
      "filterSuppressions cannot set both eventIdAllowList and eventIdDenyList",
    )
  }
  if !namespaces_allow.is_empty() && !namespaces_deny.is_empty() {
    raise InvalidBuildConfig(
      "filterSuppressions cannot set both namespaceAllowList and namespaceDenyList",
    )
  }
  let remove_unused = rewrite_bool(args, "removeUnused")
  let remove_reasons = rewrite_bool(args, "removeReasons")
  let current_validators = misc_validator_ids(model)
  let removed_validators = misc_validator_ids(original).filter(id => {
    !current_validators.contains(id)
  })
  let events = original_events.filter(event => {
    event.severity == "SUPPRESSED" && !removed_validators.contains(event.id)
  })
  fn allowed(
    value : String,
    allow : Array[String],
    deny : Array[String],
  ) -> Bool {
    (allow.is_empty() || allow.contains(value)) && !deny.contains(value)
  }
  let suppress_id = @smithy.ShapeId::parse("smithy.api#suppress").unwrap()
  let shapes = model.shapes.copy()
  for id, shape in model.shapes {
    guard shape.traits.get(suppress_id) is Some(@smithy.Array(values)) else {
      continue
    }
    let kept = values.filter(value => {
      match value {
        @smithy.String(rule) =>
          allowed(rule, events_allow, events_deny) &&
          (
            !remove_unused ||
            events
            .iter()
            .any(event => {
              event.shape == Some(id) &&
              @smithy.suppression_matches(rule, event.id)
            })
          )
        _ => false
      }
    })
    let traits = shape.traits.copy()
    if kept.is_empty() {
      traits.remove(suppress_id)
    } else {
      traits[suppress_id] = @smithy.Array(kept)
    }
    shapes[id] = { ..shape, traits, }
  }
  let metadata = model.metadata.copy()
  if model.metadata.get("suppressions") is Some(@smithy.Array(values)) {
    let kept : Array[@smithy.NodeValue] = []
    for value in values {
      guard value is @smithy.Object(fields) else {
        raise InvalidBuildConfig(
          "Expected metadata suppressions to contain objects",
        )
      }
      guard fields.get("id") is Some(@smithy.String(id)) &&
        fields.get("namespace") is Some(@smithy.String(scope)) else {
        raise InvalidBuildConfig(
          "Expected suppression id and namespace strings",
        )
      }
      if !allowed(id, events_allow, events_deny) ||
        !allowed(scope, namespaces_allow, namespaces_deny) {
        continue
      }
      if remove_unused &&
        !events
        .iter()
        .any(event => {
          @smithy.suppression_matches(id, event.id) &&
          (
            scope == "*" ||
            event.shape.map(id => id.namespace == scope).unwrap_or(false)
          )
        }) {
        continue
      }
      let fields = fields.copy()
      if remove_reasons {
        fields.remove("reason")
      }
      kept.push(@smithy.Object(fields))
    }
    if kept != values {
      if kept.is_empty() {
        metadata.remove("suppressions")
      } else {
        metadata["suppressions"] = @smithy.Array(kept)
      }
    }
  }
  { shapes, metadata, }
}

///|
fn misc_flatten_closure(
  model : @smithy.Model,
  args : Json,
) -> @smithy.Model raise BuildError {
  guard config_string(args, "namespace") is Some(target_namespace) &&
    config_string(args, "closure") is Some(name) else {
    raise InvalidBuildConfig(
      "Expected `closure` and `namespace` on flattenClosureNamespaces",
    )
  }
  let mut declared : Json? = None
  if model.metadata.get("shapeClosures") is Some(@smithy.Array(entries)) {
    for entry in entries {
      let entry = @json.to_json(entry)
      if config_string(entry, "id") == Some(name) {
        declared = Some(entry)
      }
    }
  }
  guard declared is Some(declared) else {
    raise InvalidBuildConfig(
      "No shape closure named `" + name + "` is defined in the model",
    )
  }
  let namespaces = config_strings(declared, "includeNamespaces")
  let roots : Array[@smithy.ShapeId] = []
  for id, _ in model.shapes {
    if namespaces.contains(id.namespace) {
      roots.push(id)
    }
  }
  if config_string(declared, "includeBySelector") is Some(selector) {
    let ids = shape_select(model, selector) catch { _ => [] }
    for id in ids {
      if @smithy.ShapeId::parse(id) is Some(id) {
        roots.push(id)
      }
    }
  }
  let closure = shape_closure(model, roots)
  let names = config_object(declared, "rename")
  let renamed : Map[@smithy.ShapeId, @smithy.ShapeId] = Map([])
  for id, _ in model.shapes {
    if id.member is Some(_) ||
      id.namespace == "smithy.api" ||
      !closure.contains(id) {
      continue
    }
    let name = match names.get(id.to_string()) {
      None => id.name
      Some(String(name)) => name
      _ =>
        raise InvalidBuildConfig(
          "Expected shape closure rename names to be strings",
        )
    }
    let target = rewrite_shape_id(target_namespace + "#" + name)
    if id != target {
      renamed[id] = target
    }
  }
  rewrite_rename(model, renamed)
}

///|
fn transform_misc(
  model : @smithy.Model,
  transform : TransformConfig,
  original_model~ : @smithy.Model? = None,
  original_events~ : Array[@smithy.ValidationEvent]? = None,
) -> @smithy.Model? raise BuildError {
  match transform.name {
    "includeTags" | "excludeTags" => {
      let tags = config_strings(misc_args(transform, "tags"), "tags")
      let tag_id = @smithy.ShapeId::parse("smithy.api#tags").unwrap()
      let shapes = model.shapes.copy()
      for id, shape in model.shapes {
        guard shape.traits.get(tag_id) is Some(@smithy.Array(values)) else {
          continue
        }
        let kept : Array[@smithy.NodeValue] = []
        for value in values {
          if value is @smithy.String(tag) &&
            tags.contains(tag) == (transform.name == "includeTags") &&
            !kept.contains(value) {
            kept.push(value)
          }
        }
        let traits = shape.traits.copy()
        traits[tag_id] = @smithy.Array(kept)
        shapes[id] = { ..shape, traits, }
      }
      Some({ shapes, metadata: model.metadata, })
    }
    "includeTraitsByTag" | "excludeTraitsByTag" => {
      let tags = config_strings(misc_args(transform, "tags"), "tags")
      Some(
        shape_filter(model, shape => {
          shape.trait_value("smithy.api#trait") is None ||
          shape_tagged(shape, tags) == (transform.name == "includeTraitsByTag")
        }),
      )
    }
    "includeTraits" | "excludeTraits" => {
      let patterns = config_strings(misc_args(transform, "traits"), "traits")
      let names : Array[String] = []
      let namespaces : Array[String] = []
      for pattern in patterns {
        if pattern.has_suffix("#") {
          namespaces.push(pattern[:pattern.length() - 1].to_owned())
        } else {
          names.push(rewrite_shape_id(transform_trait_id(pattern)).to_string())
        }
      }
      if transform.name == "includeTraits" {
        names.push("smithy.api#trait")
      }
      let removed : Map[@smithy.ShapeId, Bool] = Map([])
      for id, shape in model.shapes {
        let matched = names.contains(id.to_string()) ||
          namespaces.contains(id.namespace)
        if shape.trait_value("smithy.api#trait") is Some(_) &&
          matched == (transform.name == "excludeTraits") {
          removed[id] = true
        }
      }
      Some(shape_remove(model, removed))
    }
    "includeMetadata" | "excludeMetadata" => {
      let keys = config_strings(misc_args(transform, "keys"), "keys")
      let metadata : Map[String, @smithy.NodeValue] = Map([])
      for name, value in model.metadata {
        if keys.contains(name) == (transform.name == "includeMetadata") {
          metadata[name] = value
        }
      }
      Some({ shapes: model.shapes, metadata, })
    }
    "makeIdempotencyTokensClientOptional" => {
      let shapes = model.shapes.copy()
      let client_optional = @smithy.ShapeId::parse("smithy.api#clientOptional").unwrap()
      for id, shape in model.shapes {
        if shape.body is @smithy.Member(..) &&
          shape.trait_value("smithy.api#required") is Some(_) &&
          shape.trait_value("smithy.api#idempotencyToken") is Some(_) &&
          !shape.traits.contains(client_optional) {
          let traits = shape.traits.copy()
          traits[client_optional] = @smithy.Object(Map([]))
          shapes[id] = { ..shape, traits, }
        }
      }
      Some({ shapes, metadata: model.metadata, })
    }
    "flattenClosureNamespaces" =>
      Some(misc_flatten_closure(model, transform.args))
    "filterSuppressions" => {
      let original = original_model.unwrap_or(model)
      let events = match original_events {
        Some(events) => events
        None => original.validation_events()
      }
      Some(misc_filter_suppressions(model, transform.args, original, events))
    }
    _ => None
  }
}
