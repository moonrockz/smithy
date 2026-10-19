///|
test "vendored EmitNoneSelector event matches the reference" {
  let source = @fs.read_file_to_string(
    "tck/validation/linters/emit-none-selector-validator.json",
  )
  let result = @smithy.Loader::new()
    .add_json("emit-none.json", source)
    .assemble()
  guard result.model is Some(model) else {
    fail(result.diagnostics.map(d => d.message).join("\n"))
  }
  let events = model.validation_events()
  assert_true(
    events
    .iter()
    .any(e => {
      e.id == "NoLengthTraits" &&
      e.severity == "DANGER" &&
      e.shape is None &&
      e.message ==
      "Expected at least one shape to match selector: [trait|length]"
    }),
  )
  assert_false(events.iter().any(e => e.id == "NoDocumentationTraits"))
}

///|
test "vendored suppression takes precedence over severity override" {
  let source = @fs.read_file_to_string(
    "tck/validation/severityOverrides/suppressions-take-precedence.smithy",
  )
  let result = @smithy.Loader::new()
    .add_idl("suppression.smithy", source)
    .assemble()
  guard result.model is Some(model) else {
    fail(result.diagnostics.map(d => d.message).join("\n"))
  }
  let events = model.validation_events()
  assert_true(
    events
    .iter()
    .any(e => {
      e.id == "NoteTheInteger" &&
      e.severity == "SUPPRESSED" &&
      e.shape.map(id => id.to_string()) == Some("smithy.example#IntegerTarget")
    }),
  )
}

///|
test "vendored UnreferencedShape identifies disconnected shapes" {
  let source = @fs.read_file_to_string(
    "tck/validation/unreferenced-shapes/service-root-single-match.smithy",
  )
  let result = @smithy.Loader::new()
    .add_idl("unreferenced.smithy", source)
    .assemble()
  guard result.model is Some(model) else {
    fail(result.diagnostics.map(d => d.message).join("\n"))
  }
  let ids = model
    .validation_events()
    .filter(e => e.id == "UnreferencedShape")
    .map(e => e.shape.map(id => id.to_string()).unwrap_or(""))
  ids.sort()
  assert_eq(ids, ["smithy.example#Bam", "smithy.example#Baz"])
}

///|
test "vendored trait target emits incompatible applications" {
  let source = @fs.read_file_to_string(
    "tck/validation/trait-target/trait-target.json",
  )
  let result = @smithy.Loader::new()
    .add_json("trait-target.json", source)
    .assemble()
  guard result.model is Some(model) else {
    fail(result.diagnostics.map(d => d.message).join("\n"))
  }
  let events = model.validation_events()
  assert_eq(events.filter(e => e.id == "TraitTarget").length(), 2)
  assert_true(
    events
    .iter()
    .any(e => {
      e.id == "TraitTarget" &&
      e.severity == "ERROR" &&
      e.shape.map(id => id.to_string()) == Some("ns.foo#Invalid$baz")
    }),
  )
  assert_true(
    events
    .iter()
    .any(e => {
      e.id == "TraitTarget" &&
      e.severity == "ERROR" &&
      e.shape.map(id => id.to_string()) == Some("ns.foo#String")
    }),
  )
}

///|
test "vendored trait validators emit scoped compatibility errors" {
  let source = @fs.read_file_to_string(
    "tck/validation/traitValidators/find-incompatible-shapes.smithy",
  )
  let result = @smithy.Loader::new()
    .add_idl("trait-validators.smithy", source)
    .assemble()
  guard result.model is Some(model) else {
    fail(result.diagnostics.map(d => d.message).join("\n"))
  }
  let events = model.validation_events()
  for
    (id, shape) in [
      (
        "com.amazonaws.simple.myProtocol.NoDocuments", "com.amazonaws.simple#GetFooInput$document",
      ),
      (
        "com.amazonaws.simple.myProtocol.NoEventStreams", "com.amazonaws.simple#GetFooOutput",
      ),
      (
        "com.amazonaws.simple.myProtocol.NoErrors", "com.amazonaws.simple#GetFoo",
      ),
    ] {
    assert_true(
      events
      .iter()
      .any(e => {
        e.id == id &&
        e.severity == "ERROR" &&
        e.shape.map(s => s.to_string()) == Some(shape)
      }),
    )
  }
}

///|
test "vendored missing selector produces a model configuration error" {
  let source = @fs.read_file_to_string(
    "tck/validation/linters/emit-each-selector-requires-selectors.json",
  )
  let result = @smithy.Loader::new()
    .add_json("missing-selector.json", source)
    .assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  assert_true(
    model
    .validation_events()
    .iter()
    .any(e => {
      e.id == "Model" &&
      e.severity == "ERROR" &&
      e.shape is None &&
      e.message.contains("selector is required")
    }),
  )
}
