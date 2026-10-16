///|
test "semantic IDs enforce the Smithy grammar and preserve member identity" {
  for text in ["example.weather#City", "x#_1$__a", "smithy.api#String"] {
    assert_eq(@smithy.ShapeId::parse(text).unwrap().to_string(), text)
  }
  for
    text in [
      "City", "#City", "x..y#City", "x#_", "_#City", "x#City$_", "x#City$one$two",
      "x#1City",
    ] {
    assert_eq(@smithy.ShapeId::parse(text), None)
  }
  let id = @smithy.ShapeId::parse("example.weather#City").unwrap()
  assert_eq(id.with_member("name").unwrap().root(), id)
}

///|
test "semantic numbers compare exact values without expanding exponents" {
  for
    (a, b) in [
      ("1", "1.0"),
      ("100", "1e2"),
      ("-0", "0.000"),
      ("1e100000000000", "10e99999999999"),
    ] {
    assert_eq(@smithy.NodeNumber::parse(a), @smithy.NodeNumber::parse(b))
  }
  assert_true(
    @smithy.NodeNumber::parse("9007199254740992") !=
    @smithy.NodeNumber::parse("9007199254740993"),
  )
  assert_true(
    @smithy.NodeNumber::parse("0.10000000000000000001") !=
    @smithy.NodeNumber::parse("0.10000000000000000002"),
  )
  assert_eq(@smithy.NodeNumber::parse("1 "), None)
}

///|
test "node values retain exact numeric representations and nested values" {
  let ast = @syntax.parse_json_ast(
    "{\"smithy\":\"2\",\"metadata\":{\"number\":0.10000000000000000001,\"nested\":[true,null,\"text\"]}}",
  )
  for _, json in ast.metadata.unwrap() {
    let value = @smithy.NodeValue::from_json(json)
    assert_eq(@json.to_json(value).stringify(), json.stringify())
  }
}

///|
test "law: semantic ID formatting is stable" {
  @quickcheck.check(
    (text : String) => {
      match @smithy.ShapeId::parse(text) {
        None => true
        Some(id) => @smithy.ShapeId::parse(id.to_string()) == Some(id)
      }
    },
    count=300,
    seed=6031,
  )
}
