///|
fn Model::example_value_events(
  self : Model,
  operation : Shape,
  target : ShapeId,
  value : NodeValue,
  title : String,
  name : String,
  allow_constraint_errors : Bool,
) -> Array[ValidationEvent] {
  self
  .node_validation_events(
    value,
    target,
    Some(operation),
    "ExamplesTrait",
    "ERROR",
    allow_constraint_errors~,
  )
  .map(event => {
    let original = event.message
    let prefix = "Error validating value"
    let context = "Example " + name + " of `" + title + "`"
    let message = if original.has_prefix(prefix) {
      let remaining = original[prefix.length():].to_owned()
      if remaining.find(": ") is Some(at) {
        let path = remaining[:at].to_owned().replace(old="/", new=".")
        context + path + remaining[at:].to_owned()
      } else {
        context + remaining
      }
    } else {
      context + ": " + original
    }
    { ..event, message, }
  })
}

///|
fn Model::example_services_contain_error(
  self : Model,
  operation : Shape,
  error_id : ShapeId,
) -> Bool {
  let mut has_service = false
  for _, service in self.shapes {
    guard service.body is Service(errors~, ..) else { continue }
    has_service = true
    if self
      .http_contained_operations(service)
      .iter()
      .any(op => op.id == operation.id) &&
      !errors.contains(error_id) {
      return false
    }
  }
  has_service
}

///|
fn Model::examples_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for _, operation in self.shapes {
    guard operation.body is Operation(input~, output~, errors~) else {
      continue
    }
    for
      example in validation_array(operation.trait_value("smithy.api#examples")) {
      let title = validation_string(example, "title").unwrap_or("")
      let output_value = validation_field(example, "output")
      let error_value = validation_field(example, "error")
      let allow = validation_field(example, "allowConstraintErrors") ==
        Some(Boolean(true))
      if self.shapes.contains(input) {
        if allow && error_value is None {
          events.push(
            validation_event(
              "ExamplesTrait",
              "ERROR",
              Some(operation),
              "Example: `" +
              title +
              "` has allowConstraintErrors enabled, so error must be defined.",
            ),
          )
        }
        let input_value = validation_field(example, "input").unwrap_or(
          Object(Map([])),
        )
        events.append(
          self.example_value_events(
            operation, input, input_value, title, "input", allow,
          ),
        )
      }
      if output_value is Some(_) && error_value is Some(_) {
        events.push(
          validation_event(
            "ExamplesTrait",
            "ERROR",
            Some(operation),
            "Example: `" +
            title +
            "` has both output and error defined, only one should be present.",
          ),
        )
      } else if output_value is Some(value) {
        if self.shapes.contains(output) {
          events.append(
            self.example_value_events(
              operation, output, value, title, "output", allow,
            ),
          )
        }
      } else if error_value is Some(error_) &&
        validation_string(error_, "shapeId") is Some(id) {
        let target = ShapeId::parse(id)
        if target is Some(target) &&
          self.shapes.contains(target) &&
          (
            errors.contains(target) ||
            self.example_services_contain_error(operation, target)
          ) {
          let value = validation_field(error_, "content").unwrap_or(
            Object(Map([])),
          )
          events.append(
            self.example_value_events(
              operation, target, value, title, "error", allow,
            ),
          )
        } else {
          events.push(
            validation_event(
              "ExamplesTrait",
              "ERROR",
              Some(operation),
              "Error parameters provided for operation without the `" +
              id +
              "` error: `" +
              title +
              "`",
            ),
          )
        }
      }
    }
  }
  events
}
