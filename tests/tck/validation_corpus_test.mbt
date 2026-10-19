///|
fn check_validation_events(stem : String) -> Unit raise {
  let path = "tck/validation/" + stem
  let file = if @fs.path_exists(path + ".smithy") {
    path + ".smithy"
  } else {
    path + ".json"
  }
  let source = @fs.read_file_to_string(file)
  let loader = @smithy.Loader::new()
  if file.has_suffix(".smithy") {
    ignore(loader.add_idl(file, source))
  } else {
    ignore(loader.add_json(file, source))
  }
  let reference = @json.parse(
    @fs.read_file_to_string("tck/validation-events.json"),
  )
  let suffix = if file.has_suffix(".smithy") { ".smithy" } else { ".json" }
  let expected = match reference {
    Object(files) =>
      match files.get(stem + suffix) {
        Some(Array(events)) =>
          events.map(event => {
            match event {
              String(key) => key
              _ => abort("Invalid reference event key")
            }
          })
        _ => abort("Missing reference validation events for " + stem)
      }
    _ => abort("Invalid reference validation manifest")
  }
  let actual = loader
    .assemble()
    .validation_events()
    .map(e => {
      e.id +
      "|" +
      e.severity +
      "|" +
      e.shape.map(id => id.to_string()).unwrap_or("-")
    })
  actual.sort()
  expected.sort()
  assert_eq(
    actual,
    expected,
    msg=stem +
      "\nactual: " +
      actual.join("\n") +
      "\nexpected: " +
      expected.join("\n"),
  )
}

///|
test "vendored pattern cors unit and private mixin member rules match the reference" {
  for
    name in [
      "pattern-trait", "cors-trait", "unit/invalid-members", "private-mixin-member",
    ] {
    check_validation_events(name)
  }
}

///|
test "vendored default values match the reference" {
  for
    name in [
      "default-with-invalid-blob", "default-with-null", "detects-default-out-of-range",
      "document-must-be-singular", "enum-must-match-values", "incoherent-default",
      "invalid-type-for-string", "list-must-be-empty", "list-must-match-constraints",
      "map-must-be-empty", "map-must-match-constraints", "numbers-must-fit-type",
      "numbers-must-match-constraints", "string-must-match-constraints",
    ] {
    check_validation_events("defaults/" + name)
  }
}

///|
test "remaining selector and reference advisories match Java events" {
  for
    name in [
      "xml-flattened-and-name", "deprecated-shape/deprecated-shape", "linters/emit-each-invalid-selector",
    ] {
    check_validation_events(name)
  }
}

///|
test "vendored range and length validation events match the reference" {
  check_validation_events("range-trait")
  check_validation_events("length-trait")
}

///|
test "vendored trait conflicts and exclusive member events match the reference" {
  check_validation_events("finds-conflicting-traits")
  check_validation_events("http-trait-conflicts")
  check_validation_events("exclusive-structure-member-traits-validator")
  check_validation_events("jsonName-conflict")
}

///|
test "vendored EmitEachSelector omits non-error prelude events" {
  check_validation_events("linters/emit-each-selector-validator")
}

///|
test "vendored severity override configuration errors match the reference" {
  for
    name in [
      "missing-id", "missing-namespace", "missing-severity", "should-be-array", "should-be-array-of-objects",
      "cannot-elevate-to-error",
    ] {
    check_validation_events("severityOverrides/" + name)
  }
}

///|
test "vendored assembly events retain trait and shape conflict identities" {
  for
    name in [
      "custom-trait-validation", "trait-value/extra-trait-property", "annotation-trait-extra-properties",
      "unique-structure-member", "unique-taggedunion-member", "private-access", "union-requires-members",
    ] {
    check_validation_events(name)
  }
}

///|
test "vendored service closure conflicts and renames match the reference" {
  check_validation_events("service-conflict-validator")
  for
    name in [
      "conflict", "error-rename-invalid", "invalid-identifier", "invalid-shape",
      "member-invalid", "operation-invalid", "redundant-rename-invalid", "shape-same-name",
    ] {
    check_validation_events("service-rename/" + name)
  }
}

///|
test "vendored operation input output validation matches the reference" {
  check_validation_events("operation/ambiguous-name")
  for
    name in [
      "invalid-input-output-operation-bindings", "invalid-member-target-to-input-output",
      "invalid-multiple-operations-same-shape", "valid-input-output-traits",
    ] {
    check_validation_events("operation/input-output-traits/" + name)
  }
}

///|
test "vendored resource cycle events match the reference" {
  check_validation_events("resource-parent-validator")
}

///|
test "vendored trait validator event IDs follow namespace grammar" {
  check_validation_events("traitValidators/event-ids")
}

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
