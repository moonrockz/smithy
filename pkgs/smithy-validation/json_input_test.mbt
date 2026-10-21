///|
test "JSON input rejects duplicate names after decoding key escapes" {
  for
    text in [
      "{\"a\":1,\"a\":2}", "{\"a\":1,\"\\u0061\":2}", "{\"outer\":{\"x\":0,\"x\":1}}",
    ] {
    let mut rejected = false
    ignore(@validation.parse_json_value(text)) catch {
      @validation.DuplicateJsonKey(_) => rejected = true
      _ => fail("Expected duplicate-key rejection")
    }
    assert_true(rejected)
  }
  let value = @validation.parse_json_value("[{\"a\":1},{\"a\":2}]")
  assert_eq(value, @json.parse("[{\"a\":1},{\"a\":2}]"))
}

///|
test "JSON input distinguishes quoted punctuation and malformed syntax" {
  for
    text in [
      "{\"a\":\"[{},]\\\"\\\\\",\"b\":{\"a\":1}}", "\"🐟\"", "[0,true,null,\"x\"]",
    ] {
    assert_eq(@validation.parse_json_value(text), @json.parse(text))
  }
  for text in ["{", "[1,]", "{}{}", "{\"x\" 1}", "\"\\q\"", "\"unterminated"] {
    let mut rejected = false
    ignore(@validation.parse_json_value(text)) catch {
      _ => rejected = true
    }
    assert_true(rejected, msg=text)
  }
}

///|
test "JSON input preserves numeric tokens at nesting boundaries" {
  for
    text in ["9007199254740993", "0.10000000000000000001", "1e1000000", "-0.00"] {
    let value = @validation.parse_json_value(text)
    match value {
      Number(_, repr~) => assert_eq(repr, Some(text))
      _ => fail("Expected a number")
    }
  }
  ignore(@validation.parse_json_value("[".repeat(128) + "0" + "]".repeat(128)))
  let mut rejected = false
  ignore(@validation.parse_json_value("[".repeat(129) + "0" + "]".repeat(129))) catch {
    @validation.JsonInputLimit(_, _) => rejected = true
    _ => fail("Expected nesting limit")
  }
  assert_true(rejected)
}

///|
test "JSON input size limit counts UTF-8 bytes" {
  let mut rejected = false
  ignore(@validation.parse_json_value("\"" + "🐟".repeat(4194304) + "\"")) catch {
    @validation.JsonInputLimit(_, _) => rejected = true
    _ => fail("Expected UTF-8 byte limit")
  }
  assert_true(rejected)
}
