///|
fn Model::pagination_path(
  self : Model,
  root : ShapeId,
  path : String,
) -> Shape? {
  let mut container = root
  let mut result : Shape? = None
  for part in path.split(".") {
    guard self.shapes.get(container) is Some({ body: Structure(members), .. }) else {
      return None
    }
    let member_ = members
      .iter()
      .filter_map(id => self.shapes.get(id))
      .find_first(m => m.id.member == Some(part.to_owned()))
    guard member_ is Some(member_) && member_.body is Member(target~) else {
      return None
    }
    result = Some(member_)
    container = target
  }
  result
}

///|
fn Model::pagination_properties(
  self : Model,
  operation : Shape,
  config : NodeValue,
  service : Shape?,
) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  guard operation.body is Operation(input~, output~, ..) else { return events }
  let prefix = match service {
    Some(s) => "When bound within the `" + s.id.to_string() + "` service, "
    None => ""
  }
  for property in ["inputToken", "pageSize", "outputToken", "items"] {
    guard validation_string(config, property) is Some(path) else {
      if service is Some(_) && ["inputToken", "outputToken"].contains(property) {
        events.push(
          validation_event(
            "PaginatedTrait",
            "ERROR",
            Some(operation),
            prefix + "paginated trait `" + property + "` is not configured",
          ),
        )
      }
      continue
    }
    let paths_allowed = ["outputToken", "items"].contains(property)
    if !paths_allowed && path.contains(".") {
      events.push(
        validation_event(
          "PaginatedTrait",
          "ERROR",
          Some(operation),
          prefix +
          "paginated trait `" +
          property +
          "` does not allow path values",
        ),
      )
      continue
    }
    let root = if paths_allowed { output } else { input }
    guard self.pagination_path(root, path) is Some(member_) &&
      member_.body is Member(target~) else {
      events.push(
        validation_event(
          "PaginatedTrait",
          "ERROR",
          Some(operation),
          prefix +
          "paginated trait `" +
          property +
          "` targets a member `" +
          path +
          "` that does not exist",
        ),
      )
      continue
    }
    let name = member_.id.member.unwrap()
    let description = prefix +
      "paginated trait `" +
      property +
      "` member `" +
      name +
      "`"
    if http_trait(member_, "required") {
      if property == "inputToken" {
        events.push(
          validation_event(
            "PaginatedTrait",
            "ERROR",
            Some(operation),
            description + " must not be required",
          ),
        )
      } else if property == "outputToken" || property == "pageSize" {
        events.push(
          validation_event(
            "PaginatedTrait.ShouldNotBeRequired." + property,
            if property == "pageSize" {
              "WARNING"
            } else {
              "DANGER"
            },
            Some(operation),
            description + " should not be required",
          ),
        )
      }
    }
    if self.shapes.get(target) is Some(target_shape) {
      let kind = target_shape.body.keyword()
      let valid = match property {
        "items" => ["list", "map"]
        "pageSize" => ["byte", "integer", "long", "short"]
        _ => ["map", "string"]
      }
      if !valid.contains(kind) {
        events.push(
          validation_event(
            "PaginatedTrait",
            "ERROR",
            Some(operation),
            description +
            " targets a " +
            kind +
            " shape, but must target one of the following: [" +
            http_ticked(valid) +
            "]",
          ),
        )
      }
      let discouraged = if property == "pageSize" {
        ["byte", "short", "long"].contains(kind)
      } else {
        property != "items" && kind == "map"
      }
      if discouraged {
        events.push(
          validation_event(
            "PaginatedTrait.WrongShapeType." + property,
            "DANGER",
            Some(operation),
            description +
            " targets a " +
            kind +
            " shape, but this is not recommended. One of [`" +
            (if property == "pageSize" { "integer" } else { "string" }) +
            "`] SHOULD be targeted.",
          ),
        )
      }
    }
    if paths_allowed && path.split(".").count() > 2 {
      events.push(
        validation_event(
          "PaginatedTrait.DeeplyNested." + property,
          "WARNING",
          Some(operation),
          prefix +
          "paginated trait `" +
          property +
          "` contains a path with more than two parts, which can make your API cumbersome to use",
        ),
      )
    }
  }
  events
}

///|
fn Model::pagination_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for _, operation in self.shapes {
    guard operation.body is Operation(..) &&
      operation.trait_value("smithy.api#paginated") is Some(config) else {
      continue
    }
    let local = self.pagination_properties(operation, config, None)
    events.append(local)
    if !local.is_empty() {
      continue
    }
    for _, service in self.shapes {
      guard service.body is Service(..) &&
        self
        .http_contained_operations(service)
        .iter()
        .any(op => op.id == operation.id) else {
        continue
      }
      let merged : Map[String, NodeValue] = Map([])
      let fallback = service
        .trait_value("smithy.api#paginated")
        .unwrap_or(Object(Map([])))
      for property in ["inputToken", "outputToken", "items", "pageSize"] {
        let value = match validation_field(config, property) {
          Some(v) => Some(v)
          None => validation_field(fallback, property)
        }
        if value is Some(value) {
          merged[property] = value
        }
      }
      events.append(
        self.pagination_properties(operation, Object(merged), Some(service)),
      )
    }
  }
  events
}

///|
fn Model::compression_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for _, operation in self.shapes {
    guard operation.body is Operation(input~, ..) &&
      operation.trait_value("smithy.api#requestCompression") is Some(config) else {
      continue
    }
    if input.to_string() == "smithy.api#Unit" {
      events.push(
        validation_event(
          "RequestCompressionTrait",
          "ERROR",
          Some(operation),
          "The `requestCompression` trait can only be applied to operations which have an input shape defined",
        ),
      )
    } else {
      for member_ in self.http_members(input) {
        if member_.body is Member(target~) &&
          self.shapes.get(target) is Some(target_shape) &&
          http_trait(target_shape, "streaming") &&
          http_trait(target_shape, "requiresLength") {
          events.push(
            validation_event(
              "RequestCompressionTrait",
              "ERROR",
              Some(operation),
              "The `requestCompression` trait can only be applied to operations which do not have input members that target shapes with both the `streaming` and `requiresLength` traits applied, but found member `" +
              member_.id.to_string() +
              "` targeting `" +
              target.to_string() +
              "`",
            ),
          )
        }
      }
    }
    let encodings = validation_array(validation_field(config, "encodings"))
    if encodings.is_empty() {
      events.push(
        validation_event(
          "RequestCompressionTrait",
          "ERROR",
          Some(operation),
          "There must be at least one compression algorithm in `encodings` for the `requestCompression` trait applied to `" +
          operation.id.to_string() +
          "`",
        ),
      )
    } else {
      let invalid = encodings
        .iter()
        .filter_map(v => {
          match v {
            String(s) if s.to_lower() != "gzip" => Some(s)
            _ => None
          }
        })
        .to_array()
      if !invalid.is_empty() {
        events.push(
          validation_event(
            "RequestCompressionTrait",
            "ERROR",
            Some(operation),
            "Invalid compression algorithm" +
            (if invalid.length() == 1 { "" } else { "s" }) +
            " found in `requestCompression` trait applied to `" +
            operation.id.to_string() +
            "`: " +
            http_ticked(invalid),
          ),
        )
      }
    }
  }
  events
}

///|
fn Model::protocol_events(self : Model) -> Array[ValidationEvent] {
  let events = self.pagination_events()
  events.append(self.compression_events())
  events.append(self.streaming_events())
  events.append(self.event_payload_events())
  events
}

///|
fn Model::streaming_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let edges = selector_edges(self)
  for _, member_ in self.shapes {
    guard member_.body is Member(target~) &&
      self.shapes.get(target) is Some(stream) &&
      http_trait(stream, "streaming") else {
      continue
    }
    if stream.body.keyword() == "blob" &&
      !http_trait(member_, "required") &&
      !http_trait(member_, "default") {
      events.push(
        validation_event(
          "StreamingTrait",
          "ERROR",
          Some(member_),
          "Members that target blobs marked with the `streaming` trait MUST also be marked with the `required` or `default` trait.",
        ),
      )
    }
    guard self.shapes.get(member_.id.root()) is Some(container) else {
      continue
    }
    for edge in edges {
      if edge.to != container.id {
        continue
      }
      guard self.shapes.get(edge.from) is Some(owner) else { continue }
      if edge.label == "input" || edge.label == "mixin" || edge.label == "trait" {
        continue
      }
      if edge.label == "output" {
        if http_trait(stream, "requiresLength") {
          events.push(
            validation_event(
              "StreamingTrait",
              "ERROR",
              Some(container),
              "Structures that contain a reference to a stream marked with the @requiresLength trait can only be used as operation inputs, but this structure is referenced from `" +
              owner.id.to_string() +
              "` as output",
            ),
          )
        }
      } else if edge.label == "" {
        events.push(
          validation_event(
            "StreamingTrait",
            "ERROR",
            Some(owner),
            "Members cannot target structures that contain a stream, but this member targets " +
            container.id.to_string(),
          ),
        )
      } else {
        events.push(
          validation_event(
            "StreamingTrait",
            "ERROR",
            Some(owner),
            "This shape has an invalid `" +
            edge.label.to_upper() +
            "` relationship to a structure, `" +
            container.id.to_string() +
            "`, that contains a stream",
          ),
        )
      }
    }
  }
  for _, shape in self.shapes {
    if shape.body is Union(members) && http_trait(shape, "streaming") {
      let invalid : Array[String] = []
      for id in members {
        if self.shapes.get(id) is Some({ body: Member(target~), .. }) &&
          self.shapes.get(target) is Some(target_shape) &&
          !(target_shape.body is Structure(_)) {
          invalid.push(id.member.unwrap())
        }
      }
      if !invalid.is_empty() {
        events.push(
          validation_event(
            "StreamingTrait",
            "ERROR",
            Some(shape),
            "Each member of an event stream union must target a structure shape, but the following union members do not: [" +
            invalid.join(", ") +
            "]",
          ),
        )
      }
    }
    if shape.body is Service(..) {
      let supports_payload = shape.traits
        .iter()
        .any(p => {
          match self.shapes.get(p.0) {
            Some(definition) =>
              match definition.trait_value("smithy.api#protocolDefinition") {
                Some(config) =>
                  validation_array(validation_field(config, "traits")).contains(
                    String("smithy.api#httpPayload"),
                  )
                None => false
              }
            None => false
          }
        })
      if !supports_payload {
        continue
      }
      let pending = [shape.id]
      let seen : Set[ShapeId] = Set([])
      while pending.pop() is Some(id) {
        if seen.contains(id) {
          continue
        }
        seen.add(id)
        guard self.shapes.get(id) is Some(child) else { continue }
        if child.body is Member(target~) &&
          !http_trait(child, "httpPayload") &&
          self.shapes.get(target) is Some(target_shape) &&
          http_trait(target_shape, "streaming") {
          events.push(
            validation_event(
              "StreamingTrait",
              "ERROR",
              Some(child),
              "Member `" +
              id.to_string() +
              "` referencing @streaming shape `" +
              target.to_string() +
              "` must have the @httpPayload trait, as service `" +
              shape.id.to_string() +
              "` has a protocol that supports @httpPayload.",
            ),
          )
        }
        for edge in edges {
          if edge.from == id && edge.label != "trait" {
            pending.push(edge.to)
          }
        }
      }
    }
  }
  events
}

///|
fn Model::event_payload_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for _, shape in self.shapes {
    guard shape.body is Structure(_) else { continue }
    let members = self.http_members(shape.id)
    let unmarked = members
      .filter(m => {
        !http_trait(m, "eventPayload") && !http_trait(m, "eventHeader")
      })
      .map(m => m.id.member.unwrap())
    if unmarked.is_empty() {
      continue
    }
    for member_ in members {
      if http_trait(member_, "eventPayload") {
        events.push(
          validation_event(
            "EventPayloadTrait",
            "ERROR",
            Some(shape),
            "This event structure contains a member marked with the `eventPayload` trait, so all other members must be marked with the `eventHeader` trait. However, the following member(s) are not marked with the eventHeader trait: " +
            http_ticked(unmarked),
          ),
        )
      }
    }
  }
  events
}
