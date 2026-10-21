///|
fn protocol_case_events(case_ : String) -> @smithy.LoadResult {
  @smithy.Loader::new(protocol_tests=true)
  .add_idl(
    "case.smithy",
    "$version: \"2\"\nnamespace example\nuse smithy.test#httpRequestTests\n@trait @protocolDefinition structure Protocol {}\n@httpRequestTests([" +
    case_ +
    "])\noperation Test { input: Input }\nstructure Input { @required count: Integer, name: String, at: Timestamp }",
  )
  .assemble()
}

///|
test "appliesTo and parameter object shape are validated at assembly" {
  for
    (suffix, event) in [
      ("params: {count: 1}, appliesTo: \"both\"", "TraitValue"),
      ("params: [1]", "HttpRequestTestsInput"),
      ("params: {count: \"one\"}", "HttpRequestTestsInput"),
      ("params: {}", "HttpRequestTestsInput"),
    ] {
    let loaded = protocol_case_events(
      "{id: \"TestCase\", protocol: Protocol, method: \"POST\", uri: \"/\", " +
      suffix +
      "}",
    )
    assert_true(
      loaded
      .validation_events()
      .iter()
      .any(e => e.id.has_prefix(event) && e.severity == "ERROR"),
      msg=loaded
        .validation_events()
        .map(e => e.id + ": " + e.message)
        .join("\n"),
    )
  }
}

///|
test "protocol params use epoch timestamps and permit only optional nulls" {
  for
    suffix in [
      "params: {count: 1, name: null, at: 1.5}", "params: {count: 1}, appliesTo: \"client\"",
      "params: {count: 1}, appliesTo: \"server\"",
    ] {
    assert_true(
      protocol_case_events(
        "{id: \"TestCase\", protocol: Protocol, method: \"POST\", uri: \"/\", " +
        suffix +
        "}",
      ).model
      is Some(_),
    )
  }
  for
    suffix in [
      "params: {count: null}", "params: {count: 1, at: \"2026-01-01T00:00:00Z\"}",
    ] {
    assert_true(
      protocol_case_events(
        "{id: \"TestCase\", protocol: Protocol, method: \"POST\", uri: \"/\", " +
        suffix +
        "}",
      )
      .validation_events()
      .iter()
      .any(e => e.severity == "ERROR"),
    )
  }
}

///|
test "protocol traits are opt in and remain implicit on model export" {
  assert_true(
    @smithy.Loader::new().assemble().model
    .unwrap()
    .get("smithy.test#httpRequestTests")
    is None,
  )
  let model = protocol_case_events(
    "{id: \"TestCase\", protocol: Protocol, method: \"POST\", uri: \"/\", params: {count: 1}}",
  ).model.unwrap()
  assert_true(model.get("smithy.test#httpRequestTests") is Some(_))
  assert_false(
    @smithy.Loader::new().add_ast("model.json", model.to_json_ast()).assemble().model
    is Some(_),
  )
  assert_true(
    @smithy.Loader::new(protocol_tests=true)
    .add_ast("model.json", model.to_json_ast())
    .assemble().model
    is Some(_),
  )
}

///|
test "empty JSON bodies and non-JSON media types do not cause false syntax events" {
  for
    suffix in [
      "bodyMediaType: \"application/json\"", "body: \"\", bodyMediaType: \"application/json\"",
      "body: \"raw\", bodyMediaType: \"application/notjson\"",
    ] {
    let loaded = protocol_case_events(
      "{id: \"TestCase\", protocol: Protocol, method: \"POST\", uri: \"/\", params: {count: 1}, " +
      suffix +
      "}",
    )
    assert_false(
      loaded
      .validation_events()
      .iter()
      .any(e => e.severity == "ERROR" || e.severity == "DANGER"),
      msg=loaded.validation_events().map(e => e.message).join("\n"),
    )
  }
}
