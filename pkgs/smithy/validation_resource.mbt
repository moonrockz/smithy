///|
fn resource_members(model : Model, id : ShapeId) -> Array[Shape] {
  let result : Array[Shape] = []
  if model.shapes.get(id) is Some(shape) {
    let members = match shape.body {
      Structure(members) | Union(members) => members
      _ => []
    }
    for member_ in members {
      if model.shapes.get(member_) is Some(member_) {
        result.push(member_)
      }
    }
  }
  result
}

///|
fn resource_member_name(member_ : Shape) -> String {
  member_.id.member.unwrap_or("")
}

///|
fn resource_bindings(
  model : Model,
  identifiers : Map[String, ShapeId],
  structure : ShapeId,
) -> Map[String, String] {
  let bindings : Map[String, String] = Map([])
  let explicit : Map[String, String] = Map([])
  for member_ in resource_members(model, structure) {
    let name = resource_member_name(member_)
    if member_.trait_value("smithy.api#resourceIdentifier")
      is Some(String(binding)) {
      explicit[binding] = name
    } else if member_.body is Member(target~) &&
      member_.trait_value("smithy.api#required") is Some(_) &&
      identifiers.get(name) == Some(target) {
      bindings[name] = name
    }
  }
  for name, member_ in explicit {
    bindings[name] = member_
  }
  bindings
}

///|
fn resource_binding_message(bindings : Map[String, String]) -> String {
  let descriptions : Array[String] = []
  for name, target in bindings {
    descriptions.push(
      "required member named `" + name + "` that targets `" + target + "`",
    )
  }
  descriptions.sort()
  descriptions.join(", ")
}

///|
fn resource_ticked_list(values : Array[String]) -> String {
  values.sort()
  values.map(value => "`" + value + "`").join(", ")
}

///|
fn resource_operation_bindings(shape : Shape) -> Array[(String, ShapeId, Bool)] {
  let result : Array[(String, ShapeId, Bool)] = []
  if shape.body
    is Resource(
      create~,
      put~,
      read~,
      update~,
      delete~,
      list~,
      operations~,
      collectionOperations~,
      ..
    ) {
    for
      (name, operation, collection) in [
        ("create", create, true),
        ("put", put, false),
        ("read", read, false),
        ("update", update, false),
        ("delete", delete, false),
        ("list", list, true),
      ] {
      if operation is Some(operation) {
        result.push((name, operation, collection))
      }
    }
    for operation in operations {
      result.push((operation.name, operation, false))
    }
    for operation in collectionOperations {
      result.push((operation.name, operation, true))
    }
  }
  result.map(entry => {
    let (name, operation, collection) = entry
    let is_collection = collection ||
      (match shape.body {
        Resource(create~, list~, collectionOperations~, ..) =>
          create == Some(operation) ||
          list == Some(operation) ||
          collectionOperations.contains(operation)
        _ => false
      })
    (name, operation, is_collection)
  })
}

///|
fn resource_is_lifecycle(
  resource : Shape,
  name : String,
  operation : ShapeId,
) -> Bool {
  match resource.body {
    Resource(create~, put~, read~, update~, delete~, list~, ..) =>
      (match name {
        "create" => create
        "put" => put
        "read" => read
        "update" => update
        "delete" => delete
        "list" => list
        _ => None
      }) ==
      Some(operation)
    _ => false
  }
}

///|
fn resource_descendants(model : Model, roots : Array[ShapeId]) -> Array[Shape] {
  let pending = roots.copy()
  let seen : Map[ShapeId, Bool] = Map([])
  let result : Array[Shape] = []
  while pending.pop() is Some(id) {
    if seen.contains(id) {
      continue
    }
    seen[id] = true
    if model.shapes.get(id) is Some(shape) &&
      shape.body is Resource(resources~, ..) {
      result.push(shape)
      pending.append(resources)
    }
  }
  result
}

///|
fn Model::resource_identifier_trait_events(
  self : Model,
) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for _, structure in self.shapes {
    let members = resource_members(self, structure.id)
    if !members
      .iter()
      .any(member_ => {
        member_.trait_value("smithy.api#resourceIdentifier") is Some(_)
      }) {
      continue
    }
    let potential : Map[String, Array[String]] = Map([])
    let explicit : Map[String, Array[String]] = Map([])
    for member_ in members {
      let name = resource_member_name(member_)
      let binding = match member_.trait_value("smithy.api#resourceIdentifier") {
        Some(String(binding)) => {
          explicit.get_or_init(binding, () => []).push(name)
          binding
        }
        _ => name
      }
      potential.get_or_init(binding, () => []).push(name)
    }
    for binding, names in potential {
      if names.length() > 1 && names.contains(binding) {
        let overrides = names.filter(name => name != binding)
        overrides.sort()
        events.push(
          validation_event(
            "ResourceIdentifierBinding",
            "WARNING",
            Some(structure),
            "Implicit resource identifier for '" +
            binding +
            "' is overridden by `resourceIdentifier` trait on members: '" +
            overrides.join("', '") +
            "'",
          ),
        )
      }
    }
    for binding, names in explicit {
      if names.length() > 1 {
        names.sort()
        events.push(
          validation_event(
            "ResourceIdentifierBinding",
            "ERROR",
            Some(structure),
            "Conflicting resource identifier member bindings found for identifier '" +
            binding +
            "' between members: '" +
            names.join("', '") +
            "'",
          ),
        )
      }
    }
  }
  events
}

///|
fn Model::resource_events(self : Model) -> Array[ValidationEvent] {
  let events = self.resource_identifier_trait_events()
  for _, resource in self.shapes {
    guard resource.body is Resource(identifiers~, properties~, resources~, ..) else {
      continue
    }
    for identifier, _ in identifiers {
      if properties
        .keys()
        .any(property => property.to_lower() == identifier.to_lower()) {
        events.push(
          validation_event(
            "ResourceIdentifier",
            "ERROR",
            Some(resource),
            "Resource identifier `" +
            identifier +
            "` cannot also be a resource property",
          ),
        )
      }
    }
    for child_id in resources {
      guard self.shapes.get(child_id) is Some(child) &&
        child.body is Resource(identifiers=child_identifiers, ..) else {
        continue
      }
      let missing : Array[String] = []
      let mismatched : Array[String] = []
      for name, target in identifiers {
        match child_identifiers.get(name) {
          None => missing.push(name)
          Some(actual) =>
            if actual != target {
              mismatched.push(
                "expected the `" +
                name +
                "` member to target `" +
                target.to_string() +
                "`, but found a target of `" +
                actual.to_string() +
                "`",
              )
            }
        }
      }
      missing.sort()
      mismatched.sort()
      if !missing.is_empty() {
        events.push(
          validation_event(
            "ResourceIdentifier",
            "ERROR",
            Some(child),
            "This resource is bound as a child of `" +
            resource.id.to_string() +
            "`, but it is invalid because its `identifiers` property is missing the following identifiers that are defined in `" +
            resource.id.to_string() +
            "`: [" +
            missing.join(", ") +
            "]",
          ),
        )
      }
      if !mismatched.is_empty() {
        events.push(
          validation_event(
            "ResourceIdentifier",
            "ERROR",
            Some(child),
            "The `identifiers` property of this resource is incompatible with its binding to `" +
            resource.id.to_string() +
            "`: " +
            mismatched.join("; "),
          ),
        )
      }
      let checked : Map[ShapeId, Bool] = Map([])
      for (_, operation_id, _) in resource_operation_bindings(child) {
        if checked.contains(operation_id) {
          continue
        }
        checked[operation_id] = true
        guard self.shapes.get(operation_id) is Some(operation) &&
          operation.body is Operation(input~, ..) else {
          continue
        }
        let bindings = resource_bindings(self, child_identifiers, input)
        let missing = identifiers
          .keys()
          .filter(name => !bindings.contains(name))
          .collect()
        if !missing.is_empty() {
          events.push(
            validation_event(
              "ResourceIdentifierBinding",
              "ERROR",
              Some(operation),
              "This operation is bound to the `" +
              child.id.to_string() +
              "` resource, which is a child of the `" +
              resource.id.to_string() +
              "` resource, and it is missing the following resource identifier bindings of `" +
              resource.id.to_string() +
              "`: [" +
              resource_ticked_list(missing) +
              "]",
            ),
          )
        }
      }
    }
    let checked : Map[ShapeId, Bool] = Map([])
    for
      (name, operation_id, collection) in resource_operation_bindings(resource) {
      guard self.shapes.get(operation_id) is Some(operation) &&
        operation.body is Operation(input~, ..) else {
        continue
      }
      if resource_is_lifecycle(resource, name, operation_id) {
        let is_readonly = operation.trait_value("smithy.api#readonly")
          is Some(_)
        let require_readonly = name == "read" || name == "list"
        if is_readonly != require_readonly {
          events.push(
            validation_event(
              "ResourceLifecycle",
              "ERROR",
              Some(resource),
              "The `" +
              name +
              "` lifecycle operation of this resource targets an invalid operation, `" +
              operation_id.to_string() +
              "`. The targeted operation " +
              (if require_readonly { "must" } else { "must not" }) +
              " be marked with the readonly trait.",
            ),
          )
        }
        if (name == "put" || name == "delete") &&
          operation.trait_value("smithy.api#idempotent") is None {
          events.push(
            validation_event(
              "ResourceLifecycle",
              "ERROR",
              Some(resource),
              "The `" +
              name +
              "` lifecycle operation of this resource targets an invalid operation, `" +
              operation_id.to_string() +
              "`. The targeted operation must be marked as idempotent.",
            ),
          )
        }
      }
      if checked.contains(operation_id) {
        continue
      }
      checked[operation_id] = true
      let bindings = resource_bindings(self, identifiers, input)
      let members = resource_members(self, input)
      let all_bound = identifiers
        .iter()
        .all(entry => {
          let (name, target) = entry
          match bindings.get(name) {
            Some(member_name) =>
              members
              .iter()
              .any(member_ => {
                resource_member_name(member_) == member_name &&
                member_.body is Member(target=actual) &&
                actual == target
              })
            None => false
          }
        })
      if collection && all_bound {
        events.push(
          validation_event(
            "ResourceIdentifierBinding",
            "ERROR",
            Some(operation),
            "This operation is bound as a collection operation on the `" +
            resource.id.to_string() +
            "` resource, but it improperly binds all of the identifiers of the resource to members of the operation input.",
          ),
        )
      } else if !collection && !all_bound {
        let expected : Map[String, String] = Map([])
        for name, target in identifiers {
          expected[name] = target.to_string()
        }
        events.push(
          validation_event(
            "ResourceIdentifierBinding",
            "ERROR",
            Some(operation),
            "This operation does not form a valid instance operation when bound to resource `" +
            resource.id.to_string() +
            "`. All of the identifiers of the resource were not implicitly or explicitly bound to the input of the operation. Expected the following identifier bindings: [" +
            resource_binding_message(expected) +
            "]. Found the following identifier bindings: [" +
            resource_binding_message(bindings) +
            "]",
          ),
        )
      }
    }
    events.append(self.resource_property_events(resource))
  }
  events.append(self.resource_service_events())
  events.append(self.resource_reference_events())
  events.append(self.resource_lifecycle_trait_events())
  events
}

///|
fn Model::resource_service_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for _, service in self.shapes {
    guard service.body is Service(operations~, resources~, ..) else { continue }
    let descendants = resource_descendants(self, resources)
    let operation_containers : Map[ShapeId, Array[String]] = Map([])
    for operation in operations {
      operation_containers
      .get_or_init(operation, () => [])
      .push("(service: `" + service.id.to_string() + "`)")
      guard self.shapes.get(operation) is Some(operation) &&
        operation.body is Operation(input~, output~, ..) else {
        continue
      }
      let members = resource_members(self, input)
      members.append(resource_members(self, output))
      let candidates : Array[String] = []
      for resource in descendants {
        guard resource.body is Resource(identifiers~, ..) else { continue }
        if members
          .iter()
          .any(member_ => {
            member_.body is Member(target~) &&
            member_.trait_value("smithy.api#required") is Some(_) &&
            identifiers.get(resource_member_name(member_)) == Some(target)
          }) {
          candidates.push(resource.id.to_string())
        }
      }
      if !candidates.is_empty() {
        events.push(
          validation_event(
            "ServiceBoundResourceOperation." +
            service.id.to_string() +
            "." +
            operation.id.name,
            "WARNING",
            Some(operation),
            "The `" +
            operation.id.to_string() +
            "` operation is bound to the `" +
            service.id.to_string() +
            "` service but has members that match identifiers of the following resource shapes: [" +
            resource_ticked_list(candidates) +
            "]. It may be more accurately bound to one of them than directly to the service.",
          ),
        )
      }
    }
    for resource in descendants {
      let containers : Array[String] = []
      if resources.contains(resource.id) {
        containers.push(service.id.to_string())
      }
      for parent in descendants {
        if parent.body is Resource(resources=children, ..) &&
          children.contains(resource.id) {
          containers.push(parent.id.to_string())
        }
      }
      if containers.length() > 1 {
        events.push(
          validation_event(
            "SingleResourceBinding",
            "ERROR",
            Some(resource),
            "A resource can appear only once in an entire service closure. This resource is illegally bound into the `" +
            service.id.to_string() +
            "` service closure from multiple shapes: [" +
            resource_ticked_list(containers) +
            "]",
          ),
        )
      }
      let checked : Map[ShapeId, Bool] = Map([])
      for (_, operation, _) in resource_operation_bindings(resource) {
        if checked.contains(operation) {
          continue
        }
        checked[operation] = true
        operation_containers
        .get_or_init(operation, () => [])
        .push("(resource: `" + resource.id.to_string() + "`)")
      }
    }
    for operation, containers in operation_containers {
      if containers.length() > 1 &&
        self.shapes.get(operation) is Some(operation) {
        containers.sort()
        events.push(
          validation_event(
            "SingleOperationBinding",
            "ERROR",
            Some(operation),
            "An operation can appear only once in an entire service closure. This operation is illegally bound into the `" +
            service.id.to_string() +
            "` service closure from multiple shapes: " +
            containers.join(", "),
          ),
        )
      }
    }
  }
  events
}

///|
fn Model::resource_reference_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let candidates : Map[String, Array[ShapeId]] = Map([])
  for _, resource in self.shapes {
    if resource.body is Resource(identifiers~, ..) {
      for name, target in identifiers {
        candidates
        .get_or_init(name + "|" + target.to_string(), () => [])
        .push(resource.id)
      }
    }
  }
  if candidates.is_empty() {
    return events
  }
  let lifecycle_members = self.resource_lifecycle_members()
  let edges = selector_edges(self).filter(edge => edge.label != "trait")
  let predecessors : Map[ShapeId, Array[ShapeId]] = Map([])
  for edge in edges {
    predecessors.get_or_init(edge.to, () => []).push(edge.from)
  }
  for _, member_ in self.shapes {
    guard member_.body is Member(target~) &&
      self.shapes.get(target) is Some(target_shape) &&
      target_shape.body is Simple(String) else {
      continue
    }
    guard candidates.get(
        resource_member_name(member_) + "|" + target.to_string(),
      )
      is Some(resources) else {
      continue
    }
    let ignored : Map[ShapeId, Bool] = Map([])
    for resource in lifecycle_members.get(member_.id).unwrap_or([]) {
      ignored[resource] = true
    }
    for id in [member_.id, member_.id.root()] {
      if self.shapes.get(id) is Some(shape) {
        for
          reference in validation_array(
            shape.trait_value("smithy.api#references"),
          ) {
          if validation_string(reference, "resource") is Some(resource) &&
            ShapeId::parse(resource) is Some(resource) {
            ignored[resource] = true
          }
        }
      }
    }
    let pending = [member_.id]
    let visited : Map[ShapeId, Bool] = Map([])
    while pending.pop() is Some(current) {
      if visited.contains(current) {
        continue
      }
      visited[current] = true
      if self.shapes.get(current) is Some(shape) &&
        shape.body is Resource(resources~, ..) {
        ignored[current] = true
        for child in resources {
          ignored[child] = true
        }
      }
      pending.append(predecessors.get(current).unwrap_or([]))
    }
    let missing = resources
      .filter(resource => !ignored.contains(resource))
      .map(id => id.to_string())
    if !missing.is_empty() {
      events.push(
        validation_event(
          "MemberShouldReferenceResource",
          "WARNING",
          Some(member_),
          "This member appears to reference the following resources without being included in a `@references` trait: [" +
          resource_ticked_list(missing) +
          "]",
        ),
      )
    }
  }
  events
}

///|
fn resource_field_chain(node : @jmespath.Node) -> Array[String]? {
  match node.kind {
    Field(name) => Some([name])
    Subexpression(left, right) =>
      if resource_field_chain(left) is Some(left) &&
        resource_field_chain(right) is Some(right) {
        left.append(right)
        Some(left)
      } else {
        None
      }
    _ => None
  }
}

///|
fn Model::resource_lifecycle_members(
  self : Model,
) -> Map[ShapeId, Array[ShapeId]] {
  let result : Map[ShapeId, Array[ShapeId]] = Map([])
  for _, operation in self.shapes {
    guard operation.body is Operation(input~, output~, ..) else { continue }
    for
      trait_name in [
        "createsResources", "putsResources", "readsResources", "updatesResources",
        "deletesResources",
      ] {
      for
        binding in validation_array(
          operation.trait_value("smithy.api#" + trait_name),
        ) {
        guard validation_string(binding, "resource") is Some(resource_id) &&
          self.get(resource_id) is Some(resource) &&
          resource.body is Resource(identifiers~, ..) else {
          continue
        }
        for structure in [input, output] {
          for member_ in resource_members(self, structure) {
            if identifiers.contains(resource_member_name(member_)) {
              result.get_or_init(member_.id, () => []).push(resource.id)
            }
          }
          if validation_field(binding, "identifiers") is Some(Object(locators)) {
            for _, locator in locators {
              guard validation_string(locator, "path") is Some(path) else {
                continue
              }
              let parsed = @jmespath.parse(path) catch { _ => continue }
              guard resource_field_chain(parsed.root) is Some(fields) else {
                continue
              }
              let mut current = structure
              let mut terminal : ShapeId? = None
              for field in fields {
                terminal = None
                for member_ in resource_members(self, current) {
                  if resource_member_name(member_) == field &&
                    member_.body is Member(target~) {
                    terminal = Some(member_.id)
                    current = target
                    break
                  }
                }
                if terminal is None {
                  break
                }
              }
              if terminal is Some(member_id) {
                result.get_or_init(member_id, () => []).push(resource.id)
              }
            }
          }
        }
      }
    }
  }
  result
}

///|
fn resource_property_shape(model : Model, structure : ShapeId) -> ShapeId {
  for member_ in resource_members(model, structure) {
    if member_.trait_value("smithy.api#nestedProperties") is Some(_) &&
      member_.body is Member(target~) &&
      model.shapes.get(target) is Some(shape) &&
      shape.body is Structure(_) {
      return target
    }
  }
  structure
}

///|
fn resource_list_element(model : Model, member_ : Shape) -> ShapeId? {
  if member_.body is Member(target~) &&
    model.shapes.get(target) is Some(list) &&
    list.body is List(element) &&
    model.shapes.get(element) is Some(element) &&
    element.body is Member(target~) &&
    model.shapes.get(target) is Some(structure) &&
    structure.body is Structure(_) {
    Some(target)
  } else {
    None
  }
}

///|
fn resource_element_shape(
  model : Model,
  structure : ShapeId,
  auto_detect : Bool,
) -> (ShapeId, Bool)? {
  let members = resource_members(model, structure)
  for member_ in members {
    if member_.trait_value("smithy.api#nestedProperties") is Some(_) {
      return resource_list_element(model, member_).map(id => (id, true))
    }
  }
  if auto_detect {
    let elements : Array[ShapeId] = []
    for member_ in members {
      if resource_list_element(model, member_) is Some(id) {
        elements.push(id)
      }
    }
    if elements.length() == 1 {
      return Some((elements[0], false))
    }
  }
  None
}

///|
fn resource_not_property(model : Model, member_ : Shape) -> Bool {
  member_.trait_value("smithy.api#notProperty") is Some(_) ||
  member_.traits
  .keys()
  .any(id => {
    model.shapes
    .get(id)
    .map(trait_ => {
      trait_.trait_value("smithy.api#trait") is Some(_) &&
      trait_.trait_value("smithy.api#notProperty") is Some(_)
    })
    .unwrap_or(false)
  })
}

///|
fn resource_property_name(member_ : Shape) -> String {
  match member_.trait_value("smithy.api#property") {
    Some(value) =>
      validation_string(value, "name").unwrap_or(resource_member_name(member_))
    None => resource_member_name(member_)
  }
}

///|
fn Model::resource_property_member_events(
  self : Model,
  resource : Shape,
  structure : ShapeId,
  identifiers : Map[String, String],
  binding : String,
  element : Bool,
  strict : Bool,
  used : Map[String, Bool],
) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  guard resource.body is Resource(properties~, ..) else { return events }
  let mappings : Map[String, Array[String]] = Map([])
  let severity = if strict { "ERROR" } else { "WARNING" }
  for member_ in resource_members(self, structure) {
    guard member_.body is Member(target~) else { continue }
    let name = resource_member_name(member_)
    let identifier = identifiers.values().any(value => value == name)
    let excluded = resource_not_property(self, member_)
    let explicitly_named = match member_.trait_value("smithy.api#property") {
      Some(value) => validation_string(value, "name") is Some(_)
      None => false
    }
    let is_property = if element {
      !identifier &&
      (explicitly_named || (!excluded && properties.contains(name)))
    } else {
      (!identifier && !excluded) || properties.contains(name)
    }
    if !is_property {
      if element && strict && !identifier && !excluded {
        events.push(
          validation_event(
            "ResourceOperationInputOutput",
            "ERROR",
            Some(member_),
            "Member `" +
            name +
            "` does not target a property or identifier for resource `" +
            resource.id.to_string() +
            "`. If it is an identifier, apply the `smithy.api#resourceIdentifier` trait. If it is a property, apply the `smithy.api#property` trait. If it is neither, apply the `smithy.api#notProperty` trait.",
          ),
        )
      }
      continue
    }
    let property = resource_property_name(member_)
    used[property] = true
    mappings.get_or_init(property, () => []).push(name)
    match properties.get(property) {
      Some(expected) =>
        if target != expected {
          events.push(
            validation_event(
              "ResourceOperationInputOutput",
              severity,
              Some(member_),
              "This member must target `" +
              expected.to_string() +
              "`. This member is used as part of the `" +
              binding +
              "` operation of the `" +
              resource.id.to_string() +
              "` resource and conflicts with its `" +
              property +
              "` resource property.",
            ),
          )
        }
      None =>
        if element {
          events.push(
            validation_event(
              "ResourceOperationInputOutput",
              severity,
              Some(member_),
              "This member is marked with the `smithy.api#property` trait but resolves to `" +
              property +
              "`, which is not a resource property of the `" +
              resource.id.to_string() +
              "` resource.",
            ),
          )
        } else if !identifier {
          events.push(
            validation_event(
              "ResourceOperationInputOutput",
              "ERROR",
              Some(member_),
              "Member `" +
              name +
              "` does not target a property or identifier for resource `" +
              resource.id.to_string() +
              "`. If it is an identifier, apply the `smithy.api#resourceIdentifier` trait. If it is a property, apply the `smithy.api#property` trait. If it is neither, apply the `smithy.api#notProperty` trait.",
            ),
          )
        }
    }
  }
  for property, members in mappings {
    if members.length() > 1 {
      members.sort()
      events.push(
        validation_event(
          "ResourceOperationInputOutput",
          severity,
          self.shapes.get(structure),
          "This shape contains members with conflicting resource property names that resolve to '" +
          property +
          "': " +
          members.join(", "),
        ),
      )
    }
  }
  events
}

///|
fn Model::resource_property_events(
  self : Model,
  resource : Shape,
) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  if resource.body is Resource(identifiers~, properties~, ..) &&
    !properties.is_empty() {
    let used : Map[String, Bool] = Map([])
    for
      (name, operation_id, collection) in resource_operation_bindings(resource) {
      guard self.shapes.get(operation_id) is Some(operation) &&
        operation.body is Operation(input~, output~, ..) else {
        continue
      }
      // Create is a collection binding whose properties are still top-level.
      if !collection || name == "create" {
        for structure in [input, output] {
          let bindings = resource_bindings(self, identifiers, structure)
          events.append(
            self.resource_property_member_events(
              resource,
              resource_property_shape(self, structure),
              bindings,
              name,
              false,
              true,
              used,
            ),
          )
        }
      } else {
        for
          (structure, auto_detect) in [(input, false), (output, name == "list")] {
          match resource_element_shape(self, structure, auto_detect) {
            Some((element, strict)) => {
              let bindings = resource_bindings(self, identifiers, element)
              events.append(
                self.resource_property_member_events(
                  resource, element, bindings, name, true, strict, used,
                ),
              )
            }
            None =>
              for member_ in resource_members(self, structure) {
                if member_.trait_value("smithy.api#nestedProperties") is Some(_) {
                  events.push(
                    validation_event(
                      "ResourceOperationInputOutput",
                      "WARNING",
                      Some(member_),
                      "The `smithy.api#nestedProperties` trait applied to a member of a collection operation's input or output does not target a list of structures.",
                    ),
                  )
                }
              }
          }
        }
      }
    }
    for property, _ in properties {
      if !used.contains(property) {
        events.push(
          validation_event(
            "ResourceOperationInputOutput",
            "ERROR",
            Some(resource),
            "Resource property `" +
            property +
            "` is not used in the input or output of create, an instance operation, or the list element of a collection operation.",
          ),
        )
      }
    }
  }
  events
}

///|
priv struct ResourcePathValue {
  leaf : ShapeId
  arrays : Array[ShapeId]
}

///|
fn resource_path_normalize(model : Model, id : ShapeId) -> ResourcePathValue {
  let mut leaf = id
  let arrays : Array[ShapeId] = []
  let seen : Map[ShapeId, Bool] = Map([])
  while model.shapes.get(leaf) is Some(shape) && shape.body is List(element) {
    if seen.contains(leaf) {
      break
    }
    seen[leaf] = true
    guard model.shapes.get(element) is Some(element) &&
      element.body is Member(target~) else {
      break
    }
    arrays.push(leaf)
    leaf = target
  }
  { leaf, arrays, }
}

///|
fn resource_path_unsupported(node : @jmespath.Node) -> Array[String] {
  match node.kind {
    Identity | Field(_) => []
    Subexpression(left, right)
    | Projection(left, right)
    | ObjectProjection(left, right) => {
      let unsupported = resource_path_unsupported(left)
      unsupported.append(resource_path_unsupported(right))
      unsupported
    }
    Flatten(inner) | ExpressionRef(inner) => resource_path_unsupported(inner)
    Function(name, _) => ["`" + name + "` function"]
    Index(_, _) => ["index"]
    Slice(_, _, _, _) => ["slice"]
    Literal(_) => ["literal"]
    MultiList(_) => ["multiselect list"]
    MultiHash(_) => ["multiselect hash"]
    Binary(operator, _, _) =>
      [
        match operator {
          And => "and"
          Or => "or"
          Pipe => "pipe"
          _ => "comparator"
        },
      ]
    Not(_) => ["not"]
    Filter(_, _, _) => ["filter projection"]
  }
}

///|
fn resource_path_walk(
  model : Model,
  node : @jmespath.Node,
  start : ResourcePathValue,
) -> Result[ResourcePathValue, String] {
  match node.kind {
    Identity => Ok(start)
    Field(name) => {
      if !start.arrays.is_empty() {
        return Err("cannot access field `" + name + "` on an array")
      }
      guard model.shapes.get(start.leaf) is Some(shape) else {
        return Err("unknown shape `" + start.leaf.to_string() + "`")
      }
      match shape.body {
        Structure(_) | Union(_) => {
          for member_ in resource_members(model, shape.id) {
            if resource_member_name(member_) == name &&
              member_.body is Member(target~) {
              return Ok(resource_path_normalize(model, target))
            }
          }
          Err("no member `" + name + "` on `" + start.leaf.to_string() + "`")
        }
        Map(value~, ..) =>
          if model.shapes.get(value) is Some(member_) &&
            member_.body is Member(target~) {
            Ok(resource_path_normalize(model, target))
          } else {
            Err("unknown map value")
          }
        _ =>
          Err(
            "cannot access field `" +
            name +
            "` on `" +
            start.leaf.to_string() +
            "`",
          )
      }
    }
    Subexpression(left, right) =>
      match resource_path_walk(model, left, start) {
        Err(error) => Err(error)
        Ok(left) => resource_path_walk(model, right, left)
      }
    Projection(left, right) =>
      match resource_path_walk(model, left, start) {
        Err(error) => Err(error)
        Ok(left) => {
          if left.arrays.is_empty() {
            return Err("projection `[*]` applied to a non-array")
          }
          let inner = { leaf: left.leaf, arrays: left.arrays[1:].to_owned(), }
          match resource_path_walk(model, right, inner) {
            Err(error) => Err(error)
            Ok(right) => {
              let arrays = [left.arrays[0]]
              arrays.append(right.arrays)
              Ok({ leaf: right.leaf, arrays, })
            }
          }
        }
      }
    Flatten(inner) =>
      match resource_path_walk(model, inner, start) {
        Err(error) => Err(error)
        Ok(inner) => {
          if inner.arrays.is_empty() {
            return Err("flatten `[]` applied to a non-array")
          }
          let arrays = [inner.arrays[0]]
          if inner.arrays.length() > 2 {
            arrays.append(inner.arrays[2:].to_owned())
          }
          Ok({ leaf: inner.leaf, arrays, })
        }
      }
    _ => Err("unsupported expression")
  }
}

///|
fn resource_path_parse(
  path : String,
  kind : String,
  name : String,
  trait_name : String,
  operation : Shape,
  events : Array[ValidationEvent],
) -> @jmespath.Node? {
  let parsed = @jmespath.parse(path) catch {
    @jmespath.JmespathError(diagnostic) => {
      events.push(
        validation_event(
          "ResourceLifecycleTrait",
          "ERROR",
          Some(operation),
          "Invalid JMESPath expression `" +
          path +
          "` for " +
          kind +
          " `" +
          name +
          "` in `@" +
          trait_name +
          "`: " +
          diagnostic.message,
        ),
      )
      return None
    }
  }
  let unsupported = resource_path_unsupported(parsed.root)
  if !unsupported.is_empty() {
    events.push(
      validation_event(
        "ResourceLifecycleTrait",
        "ERROR",
        Some(operation),
        "JMESPath expression `" +
        path +
        "` for " +
        kind +
        " `" +
        name +
        "` in `@" +
        trait_name +
        "` contains unsupported expressions: " +
        unsupported.map(value => "'" + value + "'").join(", "),
      ),
    )
    return None
  }
  Some(parsed.root)
}

///|
fn Model::resource_lifecycle_kind_events(
  self : Model,
  operation : Shape,
  resource : Shape,
  trait_name : String,
  binding : NodeValue,
  kind : String,
  side : ShapeId,
) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  guard resource.body is Resource(identifiers~, properties~, ..) else {
    return events
  }
  let definitions = if kind == "identifier" { identifiers } else { properties }
  let key = if kind == "identifier" { "identifiers" } else { "properties" }
  let explicit = match validation_field(binding, key) {
    Some(Object(fields)) => fields
    _ => Map([])
  }
  let signatures : Map[String, Array[ShapeId]] = Map([])
  for name, locator in explicit {
    guard validation_string(locator, "path") is Some(path) else { continue }
    guard definitions.get(name) is Some(target) else {
      let capitalized = if kind == "identifier" {
        "Identifier"
      } else {
        "Property"
      }
      events.push(
        validation_event(
          "ResourceLifecycleTrait",
          "ERROR",
          Some(operation),
          capitalized +
          " `" +
          name +
          "` in `@" +
          trait_name +
          "` does not match any " +
          kind +
          " of resource `" +
          resource.id.to_string() +
          "`. Valid " +
          kind +
          "s: [" +
          resource_ticked_list(definitions.keys().to_array()) +
          "]",
        ),
      )
      continue
    }
    guard resource_path_parse(path, kind, name, trait_name, operation, events)
      is Some(parsed) else {
      continue
    }
    match resource_path_walk(self, parsed, { leaf: side, arrays: [], }) {
      Err(error) =>
        events.push(
          validation_event(
            "ResourceLifecycleTrait",
            "DANGER",
            Some(operation),
            "JMESPath expression `" +
            path +
            "` for " +
            kind +
            " `" +
            name +
            "` in `@" +
            trait_name +
            "` has problems when resolved against `" +
            side.to_string() +
            "`: " +
            error,
          ),
        )
      Ok(result) => {
        if !result.arrays.is_empty() {
          signatures[name] = result.arrays
        }
        let declared = resource_path_normalize(self, target).leaf
        if result.leaf != declared {
          events.push(
            validation_event(
              "ResourceLifecycleTrait",
              "ERROR",
              Some(operation),
              "JMESPath expression `" +
              path +
              "` for " +
              kind +
              " `" +
              name +
              "` in `@" +
              trait_name +
              "` resolves to `" +
              result.leaf.to_string() +
              "`, but the resource " +
              kind +
              " targets `" +
              declared.to_string() +
              "`.",
            ),
          )
        }
      }
    }
  }
  if kind == "identifier" && signatures.length() > 1 {
    let values = signatures.values().to_array()
    if values.iter().any(value => value != values[0]) {
      let details : Array[String] = []
      for name, arrays in signatures {
        details.push(
          "`" +
          name +
          "` -> [" +
          arrays.map(id => "`" + id.to_string() + "`").join(", ") +
          "]",
        )
      }
      events.push(
        validation_event(
          "ResourceLifecycleTrait",
          "ERROR",
          Some(operation),
          "Identifiers in `@" +
          trait_name +
          "` for resource `" +
          resource.id.to_string() +
          "` project through different lists, making cardinality ambiguous. Identifiers and the lists they iterate: " +
          details.join(", "),
        ),
      )
    }
  }
  if validation_string(binding, key + "From") is Some(path) &&
    resource_path_parse(
      path,
      key + "From",
      key + "From",
      trait_name,
      operation,
      events,
    )
    is Some(parsed) {
    let prefix = "`" + key + "From` `" + path + "` in `@" + trait_name + "`"
    match resource_path_walk(self, parsed, { leaf: side, arrays: [], }) {
      Err(error) =>
        events.push(
          validation_event(
            "ResourceLifecycleTrait",
            "DANGER",
            Some(operation),
            prefix +
            " has problems when resolved against `" +
            side.to_string() +
            "`: " +
            error,
          ),
        )
      Ok(result) =>
        if parsed.kind is Identity {
          let side_name = if operation.body is Operation(output~, ..) &&
            output == side {
            "output"
          } else {
            "input"
          }
          events.push(
            validation_event(
              "ResourceLifecycleTrait",
              "ERROR",
              Some(operation),
              prefix +
              " points at the whole " +
              side_name +
              " root; it must point at a nested structure or a projection.",
            ),
          )
        } else if self.shapes.get(result.leaf) is Some(shape) &&
          shape.body is Structure(_) {
          let matched : Map[String, Shape] = Map([])
          let unmatched : Array[String] = []
          for member_ in resource_members(self, result.leaf) {
            if member_.trait_value("smithy.api#notProperty") is Some(_) {
              continue
            }
            let name = if kind == "identifier" {
              match member_.trait_value("smithy.api#resourceIdentifier") {
                Some(String(name)) => name
                _ => resource_member_name(member_)
              }
            } else {
              resource_property_name(member_)
            }
            if definitions.contains(name) {
              matched[name] = member_
            } else {
              unmatched.push(resource_member_name(member_))
            }
          }
          if matched.is_empty() {
            events.push(
              validation_event(
                "ResourceLifecycleTrait",
                "ERROR",
                Some(operation),
                prefix +
                " resolves to `" +
                result.leaf.to_string() +
                "`, whose members match no " +
                kind +
                " of resource `" +
                resource.id.to_string() +
                "`.",
              ),
            )
          } else {
            if !unmatched.is_empty() {
              events.push(
                validation_event(
                  "ResourceLifecycleTrait",
                  "ERROR",
                  Some(operation),
                  prefix +
                  " resolves to `" +
                  result.leaf.to_string() +
                  "`, which has members that are neither a " +
                  kind +
                  " nor an identifier of resource `" +
                  resource.id.to_string() +
                  "` and are not marked `@notProperty`: [" +
                  unmatched.map(name => "`" + name + "`").join(", ") +
                  "]",
                ),
              )
            }
            for name, member_ in matched {
              if member_.body is Member(target~) &&
                definitions.get(name) is Some(declared) {
                let leaf = resource_path_normalize(self, target).leaf
                let declared = resource_path_normalize(self, declared).leaf
                if leaf != declared {
                  events.push(
                    validation_event(
                      "ResourceLifecycleTrait",
                      "ERROR",
                      Some(operation),
                      "Inferred " +
                      kind +
                      " `" +
                      name +
                      "` in `@" +
                      trait_name +
                      "` (member `" +
                      resource_member_name(member_) +
                      "`) resolves to `" +
                      leaf.to_string() +
                      "`, but the resource " +
                      kind +
                      " targets `" +
                      declared.to_string() +
                      "`.",
                    ),
                  )
                }
              }
            }
          }
        } else {
          events.push(
            validation_event(
              "ResourceLifecycleTrait",
              "ERROR",
              Some(operation),
              prefix +
              " must point at a nested structure or a projection of structures, but resolved to `" +
              result.leaf.to_string() +
              "`.",
            ),
          )
        }
    }
  }
  events
}

///|
fn Model::resource_lifecycle_trait_events(
  self : Model,
) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for _, operation in self.shapes {
    guard operation.body is Operation(input~, output~, ..) else { continue }
    for
      (trait_name, lifecycle) in [
        ("createsResources", "create"),
        ("putsResources", "put"),
        ("readsResources", "read"),
        ("updatesResources", "update"),
        ("deletesResources", "delete"),
      ] {
      for
        binding in validation_array(
          operation.trait_value("smithy.api#" + trait_name),
        ) {
        guard validation_string(binding, "resource") is Some(resource_id) &&
          self.get(resource_id) is Some(resource) &&
          resource.body is Resource(..) else {
          continue
        }
        if resource_is_lifecycle(resource, lifecycle, operation.id) {
          events.push(
            validation_event(
              "ResourceLifecycleTrait",
              "WARNING",
              Some(operation),
              "Resource `" +
              resource_id +
              "` in `@" +
              trait_name +
              "` is already bound to this operation via the resource's lifecycle. The trait is redundant.",
            ),
          )
        }
        let identifier_side = if lifecycle == "create" { output } else { input }
        events.append(
          self.resource_lifecycle_kind_events(
            operation, resource, trait_name, binding, "identifier", identifier_side,
          ),
        )
        if lifecycle != "delete" {
          let property_side = if lifecycle == "read" { output } else { input }
          events.append(
            self.resource_lifecycle_kind_events(
              operation, resource, trait_name, binding, "property", property_side,
            ),
          )
        }
      }
    }
  }
  events
}
