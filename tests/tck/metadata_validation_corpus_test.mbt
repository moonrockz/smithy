///|
test "metadata trait definitions match the reference" {
  for
    name in [
      "duplicate-key", "triple-duplicate-key", "reserved-keys", "operation-io-metadata",
      "no-metadata-value",
    ] {
    check_validation_events("metadata/" + name)
  }
}

///|
test "typed metadata values match the reference" {
  for
    name in [
      "valid-typed-metadata", "map-typed-metadata", "invalid-value", "missing-required-member",
      "missing-required-nested-member",
    ] {
    check_validation_events("metadata/" + name)
  }
}

///|
test "unstable and deprecated trait use matches the reference" {
  check_validation_events("unstable-trait-validator")
  check_validation_events("deprecated-trait-validator")
}

///|
test "unstable feature ownership matches the reference" {
  check_validation_events("unstable-features-trait")
}

///|
test "shape closure metadata matches the reference" {
  for
    name in [
      "closure-id-collision", "duplicate-closure-id", "empty-namespace", "empty-selector",
      "invalid-selector-syntax", "no-namespaces-or-selector", "rename-outside-closure",
      "shape-name-conflict", "documentation", "malformed-closure-id", "malformed-rename-id",
      "rename-rules",
    ] {
    check_validation_events("shapeClosures/" + name)
  }
}
