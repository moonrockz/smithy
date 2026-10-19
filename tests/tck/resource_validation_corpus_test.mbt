///|
test "resource identifier inheritance matches the reference" {
  let result = @smithy.Loader::new()
    .add_json(
      "identifiers.json",
      @fs.read_file_to_string(
        "tck/validation/resource-identifiers/resource-identifiers.json",
      ),
    )
    .assemble()
  assert_eq(
    result.diagnostics.length(),
    0,
    msg=result.diagnostics.map(d => d.message).join("\n"),
  )
  check_validation_events("resource-identifiers/resource-identifiers")
}

///|
test "resource identifier bindings match the reference" {
  check_validation_events("resource-identifiers/detects-conflicting-bindings")
  check_validation_events("resource-operation-binding-validator")
  check_validation_events("resource-must-bind-parent-identifiers")
}

///|
test "resource lifecycle bindings match the reference" {
  for
    name in [
      "validates-idempotent-lifecycles", "validates-readonly-lifecycles", "validates-instance-and-collection-operations",
      "valid-implicit-lifecycles",
    ] {
    check_validation_events("lifecycle/" + name)
  }
}

///|
test "resources and operations have one service closure binding" {
  check_validation_events("single-resource-binding")
  check_validation_events("single-operation-binding")
}

///|
test "service operations and members identify likely resource bindings" {
  check_validation_events("resource-identifiers/detects-misbound-operations")
}

///|
test "resource operation properties match the reference" {
  check_validation_events("resource-operation-errors")
  for
    name in [
      "resource-properties", "resource-properties-errors", "resource-properties-nested",
      "invalid-resource-properties-nested", "invalid-output-identifier", "collection-operation-input-properties",
      "collection-operation-output-properties", "collection-operation-no-auto-detection",
      "list-element-bindings", "list-element-identifier-rename", "list-element-marker-misuse",
      "list-element-notproperty", "list-element-property-mismatch", "list-element-strict-unknown-member",
      "list-only-resource-properties", "list-output-ambiguous", "shared-list-element-structure",
    ] {
    check_validation_events("resource-properties/" + name)
  }
}

///|
test "resource lifecycle trait locators match the reference" {
  for
    name in [
      "creates-resources-valid", "creates-resources-wrong-identifier", "creates-resources-no-identifiers",
      "creates-resources-redundant-lifecycle", "creates-resources-path-not-in-structure",
      "creates-resources-unsupported-function", "creates-resources-identifier-type-mismatch",
      "creates-resources-property-type-mismatch", "creates-resources-same-list-valid",
      "creates-resources-different-lists", "creates-resources-nested-same-list-valid",
      "creates-resources-nested-depth-mismatch", "creates-resources-from-root", "creates-resources-inferred-unmatched",
      "creates-resources-inferred-not-a-structure", "creates-resources-inferred-projection-valid",
      "creates-resources-properties-inferred-valid", "creates-resources-reference-suppressed-by-binding",
      "puts-resources-valid", "puts-resources-wrong-identifier", "reads-resources-property-type-mismatch",
      "updates-resources-invalid-jmespath", "deletes-resources-invalid-jmespath",
    ] {
    check_validation_events(name)
  }
}
