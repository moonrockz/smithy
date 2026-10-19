///|
fn metadata_directed_graph(
  model : Model,
  prelude : Bool,
) -> Map[ShapeId, Array[ShapeId]] {
  let graph : Map[ShapeId, Array[ShapeId]] = Map([])
  for edge in selector_edges(model) {
    if edge.label != "trait" && (prelude || edge.to.namespace != "smithy.api") {
      graph.get_or_init(edge.from, () => []).push(edge.to)
    }
  }
  graph
}

///|
fn metadata_reachable(
  graph : Map[ShapeId, Array[ShapeId]],
  roots : Array[ShapeId],
) -> Map[ShapeId, Bool] {
  let visited : Map[ShapeId, Bool] = Map([])
  let pending = roots.copy()
  while pending.pop() is Some(current) {
    if visited.contains(current) {
      continue
    }
    visited[current] = true
    pending.append(graph.get(current).unwrap_or([]))
  }
  visited
}

///|
fn Model::metadata_trait_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let definitions : Map[String, Array[Shape]] = Map([])
  for _, shape in self.shapes {
    if shape.trait_value("smithy.api#metadata") is Some(value) &&
      validation_string(value, "key") is Some(key) {
      definitions.get_or_init(key, () => []).push(shape)
    }
    for trait_id, _ in shape.traits {
      guard self.shapes.get(trait_id) is Some(trait_) else { continue }
      if trait_.trait_value("smithy.api#unstable") is Some(_) {
        events.push(
          validation_event(
            "UnstableTrait." + trait_id.to_string(),
            "WARNING",
            Some(shape),
            "This shape applies a trait that is unstable: " +
            trait_id.to_string(),
          ),
        )
      }
      if shape.id.namespace != "smithy.api" &&
        trait_id.to_string() != "smithy.api#enum" &&
        trait_.trait_value("smithy.api#trait") is Some(_) &&
        trait_.trait_value("smithy.api#deprecated") is Some(config) {
        let message = trait_id.to_string() +
          validation_string(config, "message")
          .map(message => ", " + message)
          .unwrap_or("")
        events.push(
          validation_event(
            "DeprecatedTrait",
            "WARNING",
            Some(shape),
            "This shape applies a trait that is deprecated: " + message,
          ),
        )
      }
    }
  }
  for key, shapes in definitions {
    if ["severityOverrides", "suppressions", "validators"].contains(key) {
      for shape in shapes {
        events.push(
          validation_event(
            "MetadataTrait",
            "ERROR",
            Some(shape),
            "The metadata key `" +
            key +
            "` has been reserved by Smithy and may not be defined elsewhere.",
          ),
        )
      }
    } else if shapes.length() > 1 {
      for shape in shapes {
        let others = shapes
          .filter(other => other.id != shape.id)
          .map(other => other.id.to_string())
        others.sort()
        events.push(
          validation_event(
            "MetadataTrait",
            "ERROR",
            Some(shape),
            "A type has already been defined for the metadata key `" +
            key +
            "`. Conflicts with: [" +
            others.join(", ") +
            "]",
          ),
        )
      }
    }
    if shapes.length() == 1 && self.metadata.get(key) is Some(value) {
      events.append(
        self.node_validation_events(
          value,
          shapes[0].id,
          None,
          "TypedMetadata." + key,
          "ERROR",
        ),
      )
    }
  }
  events.append(self.unstable_feature_events())
  events.append(self.shape_closure_events())
  events
}

///|
fn Model::unstable_feature_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let owners : Map[ShapeId, String] = Map([])
  let services : Array[Shape] = []
  for id, shape in self.shapes {
    if shape.body is Service(..) {
      services.push(shape)
    }
    if shape.trait_value("smithy.api#unstable") is Some(value) &&
      validation_string(value, "featureId") is Some(feature_id) {
      owners[id] = feature_id
    }
  }
  let graph = metadata_directed_graph(self, false)
  let stable : Map[ShapeId, Bool] = Map([])
  let containers : Map[ShapeId, Array[ShapeId]] = Map([])
  for service in services {
    for id, _ in metadata_reachable(graph, [service.id]) {
      if owners.contains(id) {
        containers.get_or_init(id, () => []).push(service.id)
      }
    }
    if !owners.contains(service.id) {
      let visited : Map[ShapeId, Bool] = Map([])
      let pending = [service.id]
      while pending.pop() is Some(current) {
        if visited.contains(current) {
          continue
        }
        visited[current] = true
        stable[current] = true
        for neighbor in graph.get(current).unwrap_or([]) {
          if !owners.contains(neighbor) {
            pending.push(neighbor)
          }
        }
      }
    }
  }
  let enclosing : Map[ShapeId, Array[ShapeId]] = Map([])
  for owner, _ in owners {
    let visited : Map[ShapeId, Bool] = Map([])
    let pending = [owner]
    while pending.pop() is Some(current) {
      if visited.contains(current) {
        continue
      }
      visited[current] = true
      for neighbor in graph.get(current).unwrap_or([]) {
        if stable.contains(neighbor) {
          continue
        }
        if owners.contains(neighbor) {
          if neighbor != owner {
            enclosing.get_or_init(neighbor, () => []).push(owner)
          }
        } else {
          pending.push(neighbor)
        }
      }
    }
  }
  let referenced : Map[ShapeId, Map[String, Bool]] = Map([])
  for id, feature in owners {
    guard self.shapes.get(id) is Some(shape) else { continue }
    let containing = containers.get(id).unwrap_or([])
    if containing.is_empty() {
      events.push(
        validation_event(
          "UnstableFeatures.UndefinedFeature",
          "ERROR",
          Some(shape),
          "The `@unstable` trait references featureId `" +
          feature +
          "`, but the shape is bound to no service, so the featureId cannot be resolved against an `@unstableFeatures` trait.",
        ),
      )
    }
    for service_id in containing {
      referenced.get_or_init(service_id, () => Map([]))[feature] = true
      let defined = self.shapes
        .get(service_id)
        .bind(service => service.trait_value("smithy.api#unstableFeatures"))
        .bind(config => validation_field(config, feature))
        is Some(_)
      if !defined {
        events.push(
          validation_event(
            "UnstableFeatures.UndefinedFeature",
            "ERROR",
            Some(shape),
            "The `@unstable` trait references featureId `" +
            feature +
            "`, but that featureId is not defined in the `@unstableFeatures` trait of its enclosing service `" +
            service_id.to_string() +
            "`.",
          ),
        )
      }
    }
    let enclosing = enclosing.get(id).unwrap_or([]).map(id => id.to_string())
    enclosing.sort()
    if !enclosing.is_empty() {
      events.push(
        validation_event(
          "UnstableFeatures.NestedFeature",
          "ERROR",
          Some(shape),
          "The `@unstable` trait references featureId `" +
          feature +
          "`, but this shape is already within the closure of the preview shape(s) [" +
          enclosing.join(", ") +
          "]. Nesting one preview feature inside another is not supported; a shape covered by an enclosing preview shape must not carry its own `@unstable` trait.",
        ),
      )
    }
  }
  for service in services {
    if service.trait_value("smithy.api#unstableFeatures")
      is Some(Object(features)) {
      for feature, _ in features {
        if !referenced
          .get(service.id)
          .map(refs => refs.contains(feature))
          .unwrap_or(false) {
          events.push(
            validation_event(
              "UnstableFeatures.UnreferencedFeature",
              "WARNING",
              Some(service),
              "The `@unstableFeatures` trait defines featureId `" +
              feature +
              "`, but no shape of this service references it with the `@unstable` trait.",
            ),
          )
        }
      }
    }
  }
  events
}

///|
fn Model::shape_closure_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let graph = metadata_directed_graph(self, true)
  let seen : Map[String, Bool] = Map([])
  for closure in validation_array(self.metadata.get("shapeClosures")) {
    guard validation_string(closure, "id") is Some(id) else { continue }
    let renames = match validation_field(closure, "rename") {
      Some(Object(renames)) => renames
      _ => Map([])
    }
    if renames.keys().any(id => ShapeId::parse(id) is None) {
      continue
    }
    if seen.contains(id) {
      events.push(
        validation_event(
          "ShapeClosure",
          "ERROR",
          None,
          "Shape closure id `" + id + "` is declared more than once.",
        ),
      )
      continue
    }
    seen[id] = true
    if self.get(id) is Some(_) {
      events.push(
        validation_event(
          "ShapeClosure",
          "ERROR",
          None,
          "Shape closure ids must not match the ids of shapes in the model, but `" +
          id +
          "` does.",
        ),
      )
    }
    let namespaces = validation_array(
      validation_field(closure, "includeNamespaces"),
    ).filter_map(value => {
      match value {
        String(namespace) => Some(namespace)
        _ => None
      }
    })
    let selector_text = validation_string(closure, "includeBySelector")
    if namespaces.is_empty() && selector_text is None {
      events.push(
        validation_event(
          "ShapeClosure",
          "ERROR",
          None,
          "Shape closure `" +
          id +
          "` must define at least one of `includeNamespaces` or `includeBySelector`.",
        ),
      )
    }
    let populated : Map[String, Bool] = Map([])
    let roots : Array[ShapeId] = []
    for namespace in namespaces {
      let mut exists = false
      for shape_id, _ in self.shapes {
        if shape_id.namespace == namespace {
          roots.push(shape_id)
          exists = true
        }
      }
      if exists {
        populated[namespace] = true
      } else {
        events.push(
          validation_event(
            "ShapeClosure.EmptyNamespace." + id,
            "DANGER",
            None,
            "Shape closure `" +
            id +
            "` includes namespace `" +
            namespace +
            "`, which has no shapes in the model.",
          ),
        )
      }
    }
    if selector_text is Some(text) {
      if text.is_empty() {
        continue
      }
      let selector = Selector::parse(text) catch {
        InvalidSelector(message) => {
          events.push(
            validation_event(
              "ShapeClosure",
              "ERROR",
              None,
              "Shape closure `" +
              id +
              "` has an invalid `includeBySelector`: " +
              message,
            ),
          )
          continue
        }
      }
      let selected = selector
        .select_ids(self)
        .filter_map(id => ShapeId::parse(id))
      roots.append(selected)
      if selected.iter().all(id => populated.contains(id.namespace)) {
        let suffix = if populated.is_empty() {
          " in the model."
        } else {
          " in the model that aren't already in an included namespace."
        }
        events.push(
          validation_event(
            "ShapeClosure.EmptySelector." + id,
            "DANGER",
            None,
            "Shape closure `" +
            id +
            "` has an `includeBySelector` that matches no shapes" +
            suffix,
          ),
        )
      }
    }
    let shapes = metadata_reachable(graph, roots)
    let names : Map[String, Array[ShapeId]] = Map([])
    for shape_id, _ in shapes {
      if shape_id.member is None && !renames.contains(shape_id.to_string()) {
        names.get_or_init(shape_id.name.to_lower(), () => []).push(shape_id)
      }
    }
    let renamed : Map[String, ShapeId] = Map([])
    for from, to in renames {
      guard ShapeId::parse(from) is Some(from_id) && to is String(to) else {
        continue
      }
      if to == from_id.name {
        events.push(
          validation_event(
            "ShapeClosure",
            "ERROR",
            None,
            "Shape closure `" +
            id +
            "` rename for `" +
            from +
            "` does not change the name from `" +
            to +
            "`.",
          ),
        )
      }
      if !shapes.contains(from_id) {
        events.push(
          validation_event(
            "ShapeClosure",
            "ERROR",
            None,
            "Shape closure `" +
            id +
            "` attempts to rename `" +
            from +
            "`, which is not in the closure.",
          ),
        )
        continue
      }
      let normalized = to.to_lower()
      if renamed.get(normalized) is Some(previous) {
        events.push(
          validation_event(
            "ShapeClosure",
            "ERROR",
            None,
            "Shape closure `" +
            id +
            "` rename for `" +
            from +
            "` (\"" +
            to +
            "\") case-insensitively conflicts with the rename for `" +
            previous.to_string() +
            "`.",
          ),
        )
      }
      renamed[normalized] = from_id
      if names.get(normalized) is Some(conflicts) && !conflicts.is_empty() {
        events.push(
          validation_event(
            "ShapeClosure",
            "ERROR",
            None,
            "Shape closure `" +
            id +
            "` rename for `" +
            from +
            "` (\"" +
            to +
            "\") case-insensitively conflicts with non-renamed shape `" +
            conflicts[0].to_string() +
            "`.",
          ),
        )
      }
    }
    for _, conflicts in names {
      if conflicts.length() > 1 {
        let names = conflicts.map(id => id.to_string())
        names.sort()
        events.push(
          validation_event(
            "ShapeClosure.NameConflicts." + id,
            "WARNING",
            None,
            "Shape closure `" +
            id +
            "` contains shapes whose names conflict case-insensitively: [" +
            names.join(", ") +
            "]. Shapes in a closure should have case-insensitively unique names regardless of their namespaces. Some code generators or other tools may require this in order to work. The `rename` property may be used to disambiguate them.",
          ),
        )
      }
    }
  }
  events
}
