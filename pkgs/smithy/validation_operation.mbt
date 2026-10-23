///|
fn Model::operation_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let graph = SelectorGraph::new(self)
  for descriptor in ["input", "output"] {
    let opposite = if descriptor == "input" { "output" } else { "input" }
    for _, shape in self.shapes {
      if shape.trait_value("smithy.api#" + descriptor) is None {
        continue
      }
      let operations : Set[ShapeId] = Set([])
      for edge in graph.incoming(shape.id) {
        guard self.shapes.get(edge.from) is Some(owner) else { continue }
        if edge.label == descriptor {
          operations.add(owner.id)
          if !shape.id.name.has_prefix(owner.id.name) {
            events.push(
              validation_event(
                "OperationInputOutputName." + descriptor,
                "WARNING",
                Some(owner),
                "The " +
                descriptor +
                " of this operation should target a shape that starts with the operation's name, '" +
                owner.id.name +
                "', but the targeted shape is `" +
                shape.id.to_string() +
                "`",
              ),
            )
          }
        } else if edge.label == opposite {
          events.push(
            validation_event(
              "OperationInputOutputMisuse",
              "ERROR",
              Some(owner),
              "Operation `" +
              opposite +
              "` cannot target structures marked with the `@" +
              descriptor +
              "` trait: `" +
              shape.id.to_string() +
              "`",
            ),
          )
        } else if edge.label == "" && owner.body is Member(..) {
          events.push(
            validation_event(
              "OperationInputOutputMisuse",
              "ERROR",
              Some(owner),
              "Members cannot target structures marked with the @" +
              descriptor +
              " trait: " +
              shape.id.to_string(),
            ),
          )
        }
      }
      if operations.length() > 1 {
        let names = operations
          .iter()
          .map(id => "`" + id.to_string() + "`")
          .to_array()
        names.sort()
        events.push(
          validation_event(
            "OperationInputOutputMisuse",
            "ERROR",
            Some(shape),
            "Shapes marked with the @" +
            descriptor +
            " trait cannot be used as " +
            descriptor +
            " by multiple operations: " +
            names.join(", "),
          ),
        )
      }
    }
  }
  for _, operation in self.shapes {
    guard operation.body is Operation(input~, output~, ..) else { continue }
    for
      (descriptor, target, suffixes) in [
        ("input", input, ["Input", "Request"]),
        ("output", output, ["Output", "Response"]),
      ] {
      for suffix in suffixes {
        let id = operation.id.namespace + "#" + operation.id.name + suffix
        if id == target.to_string() {
          continue
        }
        if self.get(id) is Some(ambiguous) {
          events.push(
            validation_event(
              "OperationNameAmbiguity",
              "WARNING",
              Some(ambiguous),
              "The name of this shape implies that it is the " +
              descriptor +
              " of " +
              operation.id.to_string() +
              ", but that operation uses " +
              target.to_string() +
              " for " +
              descriptor +
              ". This kind of ambiguity can confuse developers calling this operation " +
              "and can cause issues in code generators that use similar naming conventions to generate " +
              descriptor +
              " types.",
            ),
          )
        }
      }
    }
  }
  events
}
