///|
test "pagination validation matches the reference corpus" {
  for
    name in [
      "paginated-valid", "paginated-valid-merge", "paginated-invalid", "paginated-map-tokens",
      "paginated-deeply-nested", "paginated-targets",
    ] {
    check_validation_events("paginated/" + name)
  }
}

///|
test "compression validation matches the reference corpus" {
  for
    name in [
      "streaming", "streaming-requiredLength", "empty-encodings", "invalid-encodings",
      "no-input", "multiple-encodings", "multiple-operations", "applied",
    ] {
    check_validation_events("requestCompression/" + name)
  }
}

///|
test "streaming validation matches the reference corpus" {
  for
    name in [
      "streaming-trait", "streaming-trait-event", "streaming-default-required", "streaming-blob-without-httppayload",
      "event-stream-with-errors", "event-payload-validation",
    ] {
    check_validation_events(name)
  }
}

///|
test "event payload requires every other member to be an event header" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|structure Message {
    #|    @eventPayload
    #|    body: String
    #|    extra: String
    #|}
  let result = @smithy.Loader::new().add_idl("event.smithy", source).assemble()
  guard result.model is Some(model) else {
    fail("event model did not assemble")
  }
  let events = model.validation_events()
  assert_eq(events.filter(e => e.id == "EventPayloadTrait").length(), 1)
  assert_true(events.iter().any(e => e.message.contains("`extra`")))
}
