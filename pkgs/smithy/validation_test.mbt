///|
test "configured selector validators emit reference event identities" {
  let source =
    #|$version: "2"
    #|metadata validators = [
    #|  {name: "EmitEachSelector", id: "Found", configuration: {selector: "structure"}}
    #|  {name: "EmitNoneSelector", id: "Missing", configuration: {selector: "union"}}
    #|]
    #|namespace example
    #|structure Thing {}
  let result = @smithy.Loader::new()
    .add_idl("example.smithy", source)
    .assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let events = model.validation_events()
  assert_true(
    events
    .iter()
    .any(e => {
      e.id == "Found" &&
      e.severity == "DANGER" &&
      e.shape.map(id => id.to_string()) == Some("example#Thing")
    }),
  )
  assert_true(
    events
    .iter()
    .any(e => e.id == "Missing" && e.severity == "DANGER" && e.shape is None),
  )
}

///|
test "missing configured validator warns without rejecting the model" {
  let source =
    #|$version: "2"
    #|metadata validators = [{name: "FutureValidator"}]
    #|namespace example
    #|structure Thing {}
  let result = @smithy.Loader::new()
    .add_idl("example.smithy", source)
    .assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let events = model.validation_events()
  assert_true(
    events
    .iter()
    .any(e => {
      e.id == "UnknownValidator_FutureValidator" &&
      e.severity == "WARNING" &&
      e.shape is None
    }),
  )
}

///|
test "suppression IDs require dot segment boundaries" {
  assert_true(@smithy.suppression_matches("Example", "Example.Child"))
  assert_true(@smithy.suppression_matches("Example", "Example"))
  assert_false(@smithy.suppression_matches("Example", "ExampleChild"))
}

///|
test "EmitEachSelector expands shape, trait and captured variable templates" {
  let source =
    #|$version: "2"
    #|metadata validators = [{name: "EmitEachSelector", id: "Template", configuration: {selector: "[id|namespace=example] $foo(*)", messageTemplate: "Trait @{trait|documentation}. ID @{id}. Name @{id|name}. Var @{var|foo|id}. Escape @@."}}]
    #|namespace example
    #|@documentation("hello")
    #|string Baz
  let result = @smithy.Loader::new()
    .add_idl("example.smithy", source)
    .assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let events = model.validation_events()
  assert_true(
    events
    .iter()
    .any(e => {
      e.id == "Template" &&
      e.shape.map(id => id.to_string()) == Some("example#Baz") &&
      e.message ==
      "Trait \"hello\". ID example#Baz. Name Baz. Var [example#Baz]. Escape @."
    }),
  )
}

///|
test "EmitEachSelector rejects malformed message template paths" {
  for template in ["@{", "@{}", "@{var|}", "@invalid"] {
    let source = "$version: \"2\"\nmetadata validators = [{name: \"EmitEachSelector\", configuration: {selector: \"structure\", messageTemplate: \"" +
      template +
      "\"}}]\nnamespace example\nstructure Thing {}"
    let result = @smithy.Loader::new()
      .add_idl("template.smithy", source)
      .assemble()
    guard result.model is Some(model) else { fail("model did not assemble") }
    assert_true(
      model
      .validation_events()
      .iter()
      .any(e => {
        e.id == "Model" &&
        e.severity == "ERROR" &&
        e.message.contains("message template")
      }),
    )
  }
}

///|
test "invalid validator configuration stops later validation phases" {
  let source = "$version: \"2\"\nmetadata validators = [{}]\nnamespace example\n@pattern(\"x\")\nstring Value"
  let events = @smithy.Loader::new()
    .add_idl("config.smithy", source)
    .assemble()
    .validation_events()
  assert_true(events.iter().any(e => e.id == "Model" && e.severity == "ERROR"))
  assert_false(events.iter().any(e => e.id == "PatternTrait"))
}

///|
test "invalid union trait arity stops checking child values" {
  let source = "$version: \"2\"\nnamespace example\n@trait\nunion t { a: String, b: Integer }\n@t(a: 1, b: \"x\")\nstructure Value {}"
  let events = @smithy.Loader::new()
    .add_idl("union.smithy", source)
    .assemble()
    .validation_events()
  assert_eq(events.filter(e => e.id == "TraitValue").length(), 1)
}

///|
test "models constructed or transformed in memory rerun structural checks" {
  let source = "$version: \"2\"\nnamespace example\nstructure Value { value: String }"
  let model = @smithy.Loader::new().add_idl("value.smithy", source).assemble().model.unwrap()
  let shapes = model.shapes.copy()
  ignore(shapes.remove(@smithy.ShapeId::parse("smithy.api#String").unwrap()))
  let model = { ..model, shapes, }
  assert_true(
    model
    .validation_events()
    .iter()
    .any(event => {
      event.id == "Target.UnresolvedShape" &&
      event.shape.map(id => id.to_string()) == Some("example#Value$value")
    }),
  )
}

///|
test "assembly failures retain reference validation event identities" {
  let source =
    #|$version: "2"
    #|namespace example
    #|structure Broken { value: Missing }
  let result = @smithy.Loader::new().add_idl("broken.smithy", source).assemble()
  assert_true(result.model is None)
  assert_true(
    result
    .validation_events()
    .iter()
    .any(e => {
      e.id == "Target.UnresolvedShape" &&
      e.severity == "ERROR" &&
      e.shape.map(id => id.to_string()) == Some("example#Broken$value")
    }),
  )
}

///|
test "resource diamond retains the pinned Java ResourceCycle event" {
  // Java Smithy 1.74.1 treats a repeated descendant as a resource cycle.
  // Preserve its assembly event and critical-validator short circuit.
  let loaded = @smithy.Loader::new()
    .add_idl(
      "diamond.smithy", "$version: \"2\"\nnamespace diamond\nservice S { version: \"1\", resources: [Root] }\nresource Root { resources: [A, B] }\nresource A { resources: [Shared] }\nresource B { resources: [Shared] }\nresource Shared {}",
    )
    .assemble()
  assert_true(loaded.model is None)
  let events = loaded.validation_events()
  assert_eq(events.length(), 1)
  assert_eq(events[0].id, "ResourceCycle")
  assert_eq(events[0].severity, "ERROR")
  assert_eq(events[0].shape.map(id => id.to_string()), Some("diamond#Shared"))
}
