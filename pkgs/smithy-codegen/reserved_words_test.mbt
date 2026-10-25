///|
test "reserved words escape only reserved names" {
  let words = @codegen.ReservedWords::new(["type", "use"])
  assert_eq(words.escape("type"), "type_")
  assert_eq(words.escape("name"), "name")
  let ci = @codegen.ReservedWords::new(["Type"], case_sensitive=false)
  assert_true(ci.is_reserved("TYPE"))
  assert_false(words.is_reserved("Type"))
}

///|
test "reserved words use a custom escape" {
  let words = @codegen.ReservedWords::new(["type"], escape=w => "_" + w)
  assert_eq(words.escape("type"), "_type")
}
