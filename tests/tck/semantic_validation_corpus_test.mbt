///|
test "authentication validation matches the reference corpus" {
  for
    name in [
      "auth-trait-must-target-service-schemes", "auth-trait-invalid-shape-id", "auth-trait-must-target-auth-definitions",
    ] {
    check_validation_events("auth/" + name)
  }
  check_validation_events("service-auth-definitions/one-auth-scheme")
  check_validation_events("service-auth-definitions/multiple-auth-schemes")
}

///|
test "idempotency validation matches the reference corpus" {
  for
    name in [
      "bare", "exists-empty-list", "notfound-empty-list", "exists-errors-valid",
      "notfound-errors-valid", "multiple-errors-valid", "not-found-errors-invalid",
      "both-properties", "errors-not-on-operation",
    ] {
    check_validation_events("idempotent-trait-" + name)
  }
  check_validation_events("idempotency-token-trait-ignored")
}

///|
test "reference and trait path validation matches the reference corpus" {
  check_validation_events("no-inline-document-support")
  for
    name in [
      "bad-ids", "invalid-string-reference-multiple-identifiers", "invalid-string-shape-reference-with-ids",
      "missing-identifier-reference", "reference-id-member-not-found", "reference-must-target-resource",
      "valid-implicit-references", "recursive-member-references", "missing-member-references",
    ] {
    check_validation_events("references/" + name)
  }
  for
    name in [
      "allows-empty-paths", "invalid-named-members", "valid-for-nested", "invalid-member-of-collection",
    ] {
    check_validation_events("trait-breaking-changes/" + name)
  }
}
