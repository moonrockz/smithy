///|
fn semantic_sorted(values : Array[String]) -> Array[String] {
  let result = values.copy()
  result.sort_by((a, b) => a.lexical_compare(b))
  result
}

///|
fn semantic_ticked(values : Array[String]) -> String {
  semantic_sorted(values).map(s => "`" + s + "`").join(", ")
}

///|
fn Model::semantic_closure(self : Model, root : ShapeId) -> Array[Shape] {
  let result : Array[Shape] = []
  let pending = [root]
  let seen : Set[ShapeId] = Set([])
  let edges = selector_edges(self)
  while pending.pop() is Some(id) {
    if seen.contains(id) {
      continue
    }
    seen.add(id)
    guard self.shapes.get(id) is Some(shape) else { continue }
    result.push(shape)
    for edge in edges {
      if edge.from == id && edge.label != "trait" {
        pending.push(edge.to)
      }
    }
  }
  result
}

///|
fn Model::authentication_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for _, service in self.shapes {
    guard service.body is Service(..) else { continue }
    let schemes : Set[String] = Set([])
    for trait_id, _ in service.traits {
      if self.shapes.get(trait_id) is Some(definition) &&
        http_trait(definition, "authDefinition") {
        schemes.add(trait_id.to_string())
      }
    }
    if schemes.length() > 1 && !http_trait(service, "auth") {
      events.push(
        validation_event(
          "ServiceAuthDefinitions",
          "WARNING",
          Some(service),
          "This service uses multiple authentication schemes but does not have the `@auth` trait applied. The `@auth` trait defines a priority ordering of auth schemes for a client to use. Without it, the ordering of auth schemes is alphabetical based on the absolute shape ID of the auth schemes.",
        ),
      )
    }
    let shapes = self.http_contained_operations(service)
    shapes.push(service)
    for shape in shapes {
      let invalid : Set[String] = Set([])
      for value in validation_array(shape.trait_value("smithy.api#auth")) {
        if value is String(scheme) && !schemes.contains(scheme) {
          invalid.add(scheme)
        }
      }
      if !invalid.is_empty() {
        events.push(
          validation_event(
            "AuthTrait",
            "DANGER",
            Some(shape),
            "auth trait applies authentication that is not configured on the service shape, `" +
            service.id.to_string() +
            "`: [" +
            semantic_sorted(invalid.iter().to_array()).join(", ") +
            "]",
          ),
        )
      }
    }
    let documents = self
      .semantic_closure(service.id)
      .filter(s => s.body.keyword() == "document")
    if documents.is_empty() {
      continue
    }
    for trait_id, _ in service.traits {
      guard self.shapes.get(trait_id) is Some(definition) &&
        definition.trait_value("smithy.api#protocolDefinition") is Some(config) &&
        validation_field(config, "noInlineDocumentSupport") ==
        Some(Boolean(true)) else {
        continue
      }
      let found = semantic_sorted(
        documents.map(s => s.id.to_string() + " @ " + s.source.file),
      )
      events.push(
        validation_event(
          "NoInlineDocumentSupport",
          "ERROR",
          Some(service),
          "This service uses the `" +
          trait_id.to_string() +
          "` protocol which does not support inline document types, but the following document types were found in the closure of the service: [" +
          found.join(", ") +
          "]",
        ),
      )
    }
  }
  events
}

///|
fn Model::idempotency_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let edges = selector_edges(self)
  for _, shape in self.shapes {
    if shape.body is Operation(errors~, ..) &&
      shape.trait_value("smithy.api#idempotent") is Some(config) {
      if validation_field(config, "exists") is Some(_) &&
        validation_field(config, "notFound") is Some(_) {
        events.push(
          validation_event(
            "IdempotentTrait",
            "ERROR",
            Some(shape),
            "The `exists` and `notFound` properties of the `@idempotent` trait are mutually exclusive. Only one may be specified.",
          ),
        )
      }
      for property in ["exists", "notFound"] {
        for value in validation_array(validation_field(config, property)) {
          if value is String(id) && !errors.iter().any(e => e.to_string() == id) {
            events.push(
              validation_event(
                "IdempotentTrait",
                "ERROR",
                Some(shape),
                "The `" +
                property +
                "` property references error `" +
                id +
                "`, but it is not in the operation's errors list. Expected one of " +
                semantic_ticked(errors.map(e => e.to_string())),
              ),
            )
          }
        }
      }
    }
    guard shape.body is Member(..) &&
      http_trait(shape, "idempotencyToken") &&
      self.shapes.get(shape.id.root()) is Some(container) &&
      container.body is Structure(_) &&
      !http_trait(container, "mixin") else {
      continue
    }
    let ignored : Map[String, Array[String]] = Map([])
    for edge in edges {
      if edge.to == container.id &&
        edge.label != "input" &&
        edge.label != "trait" {
        let label = if edge.label == "" { "member target" } else { edge.label }
        let ids = ignored.get(label).unwrap_or([])
        ids.push(edge.from.to_string())
        ignored[label] = ids
      }
    }
    if !ignored.is_empty() {
      let contexts : Array[String] = []
      for label, ids in ignored {
        contexts.push(label + ": [" + semantic_sorted(ids).join(", ") + "]")
      }
      events.push(
        validation_event(
          "IdempotencyTokenIgnored",
          "WARNING",
          Some(shape),
          "The `idempotencyToken` trait only has an effect when applied to a top-level operation input member, but it was applied and ignored in the following contexts: {" +
          semantic_sorted(contexts).join(", ") +
          "}",
        ),
      )
    }
  }
  events
}

///|
fn semantic_members(shape : Shape) -> Array[ShapeId] {
  match shape.body {
    Structure(members) | Union(members) | Enum(members) | IntEnum(members) =>
      members
    List(member_) => [member_]
    Map(key~, value~) => [key, value]
    _ => []
  }
}

///|
fn Model::breaking_change_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for _, shape in self.shapes {
    guard shape.trait_value("smithy.api#trait") is Some(config) else {
      continue
    }
    for
      index, rule in validation_array(
        validation_field(config, "breakingChanges"),
      ) {
      guard validation_string(rule, "path") is Some(path) && !path.is_empty() else {
        continue
      }
      let mut current = shape
      let parts = path.split("/").to_array()
      for i = 1; i < parts.length(); i = i + 1 {
        let part = parts[i]
          .to_owned()
          .replace(old="~1", new="/")
          .replace(old="~0", new="~")
        let member_ = semantic_members(current)
          .iter()
          .filter_map(id => self.shapes.get(id))
          .find_first(m => m.id.member == Some(part))
        match member_ {
          Some({ body: Member(target~), .. }) if self.shapes.get(target)
            is Some(next) => current = next
          _ => {
            events.push(
              validation_event(
                "TraitBreakingChanges",
                "ERROR",
                Some(shape),
                "Invalid trait breakingChanges element " +
                index.to_string() +
                ", '" +
                path +
                "', at segment '" +
                part +
                "': Evaluated shape `" +
                current.id.to_string() +
                "`, a " +
                current.body.keyword() +
                ", has no member named `" +
                part +
                "`",
              ),
            )
            break
          }
        }
      }
    }
  }
  events
}

///|
fn Model::references_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for _, shape in self.shapes {
    for
      reference in validation_array(shape.trait_value("smithy.api#references")) {
      let reference_text = "Reference" + @json.to_json(reference).stringify()
      let ids : Map[String, String] = Map([])
      if validation_field(reference, "ids") is Some(Object(values)) {
        for name, value in values {
          if value is String(member_) {
            ids[name] = member_
          }
        }
      }
      let is_string = ["string", "enum"].contains(shape.body.keyword())
      if is_string && !ids.is_empty() {
        events.push(
          validation_event(
            "ReferencesTrait",
            "ERROR",
            Some(shape),
            "References applied to string shapes cannot contain 'ids': " +
            reference_text,
          ),
        )
      }
      guard validation_string(reference, "resource") is Some(resource_id) &&
        self.get(resource_id) is Some(resource) else {
        continue
      }
      guard resource.body is Resource(identifiers~, ..) else {
        events.push(
          validation_event(
            "ReferencesTrait",
            "ERROR",
            Some(shape),
            "`references` trait reference targets a " +
            resource.body.keyword() +
            " shape not a resource: " +
            reference_text,
          ),
        )
        continue
      }
      if is_string {
        if identifiers.length() != 1 {
          events.push(
            validation_event(
              "ReferencesTrait",
              "ERROR",
              Some(shape),
              "This string shape contains an invalid reference to " +
              resource_id +
              ": " +
              reference_text +
              ". References on a string shape can only refer to resource shapes with exactly one entry in its identifiers property, but this shape has the following identifiers: [" +
              semantic_ticked(identifiers.keys().to_array()) +
              "]",
            ),
          )
        }
        continue
      }
      guard shape.body is Structure(_) else { continue }
      let implicit = ids.is_empty() && !identifiers.is_empty()
      if ids.is_empty() {
        for name, _ in identifiers {
          ids[name] = name
        }
      } else {
        if ids.length() != identifiers.length() {
          events.push(
            validation_event(
              "ReferencesTrait",
              "ERROR",
              Some(shape),
              (if ids.length() > identifiers.length() {
                "Too many identifiers"
              } else {
                "Not enough identifiers"
              }) +
              " were provided in the `ids` properties of " +
              reference_text +
              ". Expected " +
              identifiers.length().to_string() +
              " identifiers(s), but found " +
              ids.length().to_string() +
              ". This resource requires bindings for the following identifiers: [" +
              semantic_ticked(identifiers.keys().to_array()) +
              "].",
            ),
          )
        }
        let extra = ids
          .keys()
          .filter(name => !identifiers.contains(name))
          .to_array()
        if !extra.is_empty() {
          events.push(
            validation_event(
              "ReferencesTrait",
              "ERROR",
              Some(shape),
              "`references` trait " +
              reference_text +
              " contains extraneous resource identifier bindings, [" +
              semantic_ticked(extra) +
              "], that are not actually identifier names of the resource, `" +
              resource_id +
              "`. This resource has the following identifier names: [" +
              semantic_ticked(identifiers.keys().to_array()) +
              "]",
            ),
          )
        }
      }
      let reasons : Set[String] = Set([])
      let members = self.http_members(shape.id)
      for _, name in ids {
        match members.iter().find_first(m => m.id.member == Some(name)) {
          None =>
            reasons.add(
              if implicit {
                "implicit binding of `" +
                name +
                "` is not part of the structure (set \"rel\" to \"collection\" to create a collection binding)"
              } else {
                "`" +
                name +
                "` refers to a member that is not part of the structure"
              },
            )
          Some({ body: Member(target~), .. }) =>
            if self.shapes.get(target) is Some(target_shape) &&
              !["string", "enum"].contains(target_shape.body.keyword()) {
              reasons.add(
                "`" +
                name +
                "` refers to a member that does not target a string shape",
              )
            }
          _ => ()
        }
      }
      if !reasons.is_empty() {
        events.push(
          validation_event(
            "ReferencesTrait",
            "ERROR",
            Some(shape),
            "`references` trait " +
            reference_text +
            " is invalid for the following reasons: " +
            semantic_sorted(reasons.iter().to_array()).join("; "),
          ),
        )
      }
    }
  }
  events
}

///|
fn Model::semantic_trait_events(self : Model) -> Array[ValidationEvent] {
  let events = self.authentication_events()
  events.append(self.idempotency_events())
  events.append(self.references_events())
  events.append(self.breaking_change_events())
  events
}
