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
