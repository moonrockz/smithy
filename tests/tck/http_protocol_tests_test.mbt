///|
/// Compare stable event identity, severity, owner and multiplicity with the
/// pinned Java .errors goldens; retain prose differences as diagnostics.
test "request and response trait validation matches pinned Java fixtures" {
  let root = "tck/protocol-tests/upstream/"
  for
    name in [
      "say-hello", "say-goodbye", "test-with-tags", "test-with-appliesto", "errorfiles/all-request-features",
      "errorfiles/all-response-features", "errorfiles/detects-invalid-params", "errorfiles/detects-duplicate-ids",
      "errorfiles/test-case-on-error", "errorfiles/timestamp-validation", "errorfiles/vendor-params-validation",
      "errorfiles/valid-json", "errorfiles/invalid-json",
    ] {
    let result = @smithy.Loader::new(protocol_tests=true)
      .add_idl(name, @fs.read_file_to_string(root + name + ".smithy"))
      .assemble()
    let expected : Array[String] = []
    if @fs.path_exists(root + name + ".errors") {
      for line in @fs.read_file_to_string(root + name + ".errors").split("\n") {
        guard line.has_prefix("[") else { continue }
        let parts = line.split(" | ").to_array()
        let level_end = line.find("]").unwrap()
        let owner_end = line.find(":").unwrap()
        expected.push(
          parts[parts.length() - 1].to_owned() +
          "|" +
          line[1:level_end].to_owned() +
          "|" +
          line[level_end + 2:owner_end].to_owned(),
        )
      }
    }
    let actual = result
      .validation_events()
      .map(e => {
        e.id +
        "|" +
        e.severity +
        "|" +
        e.shape.map(s => s.to_string()).unwrap_or("-")
      })
    expected.sort()
    actual.sort()
    assert_eq(
      actual,
      expected,
      msg=name +
        "\n" +
        result.validation_events().map(e => e.message).join("\n"),
    )
    if expected.is_empty() {
      assert_true(result.model is Some(_), msg=name)
    }
  }
}

///|
test "missing vendor parameter targets are rejected by assembly" {
  let path = "tck/protocol-tests/upstream/errorfiles/missing-vendor-params-shape.smithy"
  let loaded = @smithy.Loader::new(protocol_tests=true)
    .add_idl(path, @fs.read_file_to_string(path))
    .assemble()
  assert_true(loaded.model is None)
  assert_true(
    loaded
    .validation_events()
    .iter()
    .any(e => {
      e.severity == "ERROR" &&
      e.message.contains("missingVendorParamsStructure")
    }),
  )
}
