///|
fn check_selector_case_file(name : String) -> Unit raise {
  let source = @fs.read_file_to_string("tck/selectors/cases/" + name)
  let result = @smithy.Loader::new().add_idl(name, source).assemble()
  guard result.model is Some(model) else {
    fail(result.diagnostics.map(d => d.code + ": " + d.message).join("\n"))
  }
  guard model.metadata.get("selectorTests") is Some(metadata) &&
    @json.to_json(metadata) is Array(cases) else {
    fail("selectorTests metadata missing in " + name)
  }
  for entry in cases {
    guard entry is Object(fields) &&
      fields.get("selector") is Some(String(expression)) &&
      fields.get("matches") is Some(Array(matches)) else {
      fail("invalid selector test case in " + name)
    }
    let skip_prelude = fields.get("skipPreludeShapes") ==
      Some(Json::boolean(true))
    let expected : Array[String] = []
    for value in matches {
      if value is String(id) && (!skip_prelude || !id.has_prefix("smithy.api#")) {
        expected.push(id)
      }
    }
    expected.sort()
    let selector = @smithy.Selector::parse(expression) catch {
      @smithy.InvalidSelector(message) =>
        fail(name + ": " + expression + ": " + message)
    }
    let actual = selector
      .select_ids(model)
      .filter(id => !skip_prelude || !id.has_prefix("smithy.api#"))
    assert_eq(
      actual,
      expected,
      msg=name +
        ": " +
        expression +
        " actual=" +
        actual.join(",") +
        " expected=" +
        expected.join(","),
    )
  }
}

///|
test "vendored id attribute selectors match the reference" {
  check_selector_case_file("id-attribute.smithy")
}

///|
test "vendored service attribute selectors match the reference" {
  check_selector_case_file("service-attribute.smithy")
}

///|
test "vendored attribute existence selectors match the reference" {
  check_selector_case_file("attribute-existence.smithy")
}

///|
test "vendored numeric comparator selectors match the reference" {
  check_selector_case_file("numeric-comparators.smithy")
}

///|
test "vendored string comparator selectors match the reference" {
  check_selector_case_file("string-comparators.smithy")
}

///|
test "vendored neighbor selectors match the reference" {
  check_selector_case_file("neighbors.smithy")
}

///|
test "vendored function selectors match the reference" {
  check_selector_case_file("functions.smithy")
}

///|
test "vendored in selectors match the reference" {
  check_selector_case_file("in-function.smithy")
}

///|
test "vendored recursive selectors match the reference" {
  check_selector_case_file("recursive-function.smithy")
}

///|
test "vendored root selectors match the reference" {
  check_selector_case_file("root-function.smithy")
}

///|
test "vendored node attribute selectors match the reference" {
  check_selector_case_file("node-attributes.smithy")
}

///|
test "vendored projection attribute selectors match the reference" {
  check_selector_case_file("projection-attributes.smithy")
}

///|
test "vendored scoped attribute selectors match the reference" {
  check_selector_case_file("scope-attribute.smithy")
}

///|
test "vendored trait attribute selectors match the reference" {
  check_selector_case_file("trait-attributes.smithy")
}

///|
test "vendored variable selectors match the reference" {
  check_selector_case_file("variables.smithy")
}
