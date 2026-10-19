///|
fn validator_config_events(
  definitions : String,
) -> Array[@smithy.ValidationEvent] {
  let source = "$version: \"2\"\nmetadata validators = " +
    definitions +
    "\nnamespace example\nstructure Thing {}\n"
  @smithy.Loader::new()
  .add_idl("config.smithy", source)
  .assemble()
  .validation_events()
}

///|
test "validator metadata requires an array of objects" {
  for value in ["{}", "null", "true", "5", "\"text\""] {
    let events = validator_config_events(value)
    assert_eq(events.length(), 1, msg=value)
    assert_eq(events[0].id, "Model", msg=value)
    assert_eq(events[0].severity, "ERROR", msg=value)
  }
  let events = validator_config_events("[null, true, 5, \"text\", []]")
  assert_eq(events.length(), 5)
  assert_true(
    events.iter().all(event => event.id == "Model" && event.severity == "ERROR"),
  )
}

///|
test "validator definitions validate required and optional field types" {
  for
    definition in [
      "{}", "{name: 1}", "{name: \"EmitEachSelector\", id: false}", "{name: \"EmitEachSelector\", message: []}",
      "{name: \"EmitEachSelector\", severity: 5}", "{name: \"EmitEachSelector\", severity: \"ERROR\"}",
      "{name: \"EmitEachSelector\", severity: \"SUPPRESSED\"}", "{name: \"EmitEachSelector\", namespaces: \"example\"}",
      "{name: \"EmitEachSelector\", namespaces: [1]}", "{name: \"EmitEachSelector\", configuration: null}",
      "{name: \"EmitEachSelector\", selector: 3}", "{name: \"EmitEachSelector\", selector: \"[\", configuration: {selector: \"structure\"}}",
    ] {
    let events = validator_config_events("[" + definition + "]")
    assert_eq(events.length(), 1, msg=definition)
    assert_eq(events[0].id, "Model", msg=definition)
    assert_eq(events[0].severity, "ERROR", msg=definition)
  }
}

///|
test "configured validator factories reject invalid settings" {
  for
    definition in [
      "{name: \"EmitEachSelector\", configuration: {selector: \"structure\", bindToTrait: \"invalid\"}}",
      "{name: \"EmitEachSelector\", configuration: {selector: \"structure\", bindToTrait: 3}}",
      "{name: \"EmitEachSelector\", configuration: {selector: \"structure\", messageTemplate: false}}",
      "{name: \"UnreferencedShape\", configuration: {rootShapeSelector: 3}}", "{name: \"UnreferencedShape\", configuration: {unexpected: true}}",
    ] {
    let events = validator_config_events("[" + definition + "]")
    assert_eq(events.length(), 1, msg=definition)
    assert_eq(events[0].id, "Model", msg=definition)
    assert_eq(events[0].severity, "ERROR", msg=definition)
  }
}

///|
test "valid validator configuration preserves severity filters and unknown warnings" {
  let events = validator_config_events(
    "[{name: \"EmitEachSelector\", id: \"Found\", severity: \"NOTE\", namespaces: [\"example\"], selector: \"structure\", configuration: {selector: \"structure\"}}, {name: \"Unknown\"}]",
  )
  assert_eq(events.length(), 2)
  assert_true(
    events
    .iter()
    .any(event => {
      event.id == "Found" &&
      event.severity == "NOTE" &&
      event.shape.map(id => id.to_string()) == Some("example#Thing")
    }),
  )
  assert_true(
    events
    .iter()
    .any(event => {
      event.id == "UnknownValidator_Unknown" && event.severity == "WARNING"
    }),
  )
}

///|
test "nullable factory binding means no trait restriction" {
  let events = validator_config_events(
    "[{name: \"EmitEachSelector\", configuration: {selector: \"structure[id|namespace=example]\", bindToTrait: null}}]",
  )
  assert_eq(events.length(), 1)
  assert_eq(events[0].id, "EmitEachSelector")
  assert_eq(events[0].severity, "DANGER")
}
