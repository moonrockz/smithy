///|
test "reference JSON AST corpus decodes and round trips without dropping fields" {
  let cases = @tck.json_cases()
  assert_true(cases.length() > 0)
  for case in cases {
    let document = @syntax.parse_json_ast(case.text) catch {
      error => fail("\{case.path}: \{error}")
    }
    let encoded = @syntax.encode_json_ast(document)
    if encoded != @json.parse(case.text) {
      fail("\{case.path}: encoding changed the JSON AST")
    }
    assert_eq(@syntax.decode_json_ast(encoded), document)
  }
}
