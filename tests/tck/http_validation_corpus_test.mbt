///|
test "HTTP header validators match the reference corpus" {
  check_validation_events("http-header-tchar-validator")
}

///|
test "HTTP API key validator matches the reference corpus" {
  check_validation_events("http-api-key-scheme-trait-validator-test")
}

///|
test "HTTP operation validators match the reference corpus" {
  for
    stem in [
      "http-method-semantics-validator", "http-response-code-semantics-validator",
      "http-response-code-semantics-validator-204", "http-uri-format-invalid", "http-uri-greedy-labels-validator1",
      "http-uri-greedy-labels-validator2", "http-query-literals-and-bindings-conflict1",
      "http-query-literals-and-bindings-conflict2", "http-query-literals-and-bindings-conflict3",
      "http-request-response-validator", "http-bindings-missing-validator", "http-bindings-missing-validator-warning",
      "http-binding-trait-ignored", "host-request-validator", "http-uri-conflict-validator",
    ] {
    check_validation_events(stem)
  }
}
