///|
test "operation examples match the reference validation corpus" {
  check_validation_events("examples-trait-validator")
}

///|
test "operation examples resolve errors across every containing service" {
  check_validation_events("examples-trait-service-errors")
}

///|
test "example constraint warnings preserve type errors" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|@examples([{
    #|    title: "Wrong type"
    #|    input: {value: 3}
    #|    error: {shapeId: "example#Failure", content: {}}
    #|    allowConstraintErrors: true
    #|}])
    #|operation Check {
    #|    input: Request
    #|    errors: [Failure]
    #|}
    #|structure Request { value: String }
    #|@error("client")
    #|structure Failure {}
  let result = @smithy.Loader::new()
    .add_idl("example.smithy", source)
    .assemble()
  guard result.model is Some(model) else {
    fail("example model did not assemble")
  }
  let events = model.validation_events().filter(e => e.id == "ExamplesTrait")
  assert_eq(events.length(), 1)
  assert_eq(events[0].severity, "ERROR")
  assert_true(
    events[0].message.has_prefix("Example input of `Wrong type`.value:"),
  )
}
