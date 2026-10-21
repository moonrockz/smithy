///|
test "public JSON value parser retains decimal and large exponent tokens" {
  let text = "{\"values\":[0.10000000000000000001,9007199254740993,1e1000000,-0.00]}"
  let value = @syntax.parse_json_value(text)
  assert_eq(value.stringify(), text)
}
