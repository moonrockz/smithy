///|
test "truthiness of template values" {
  let sym = @codegen.Symbol::new(@codegen.SymbolName::parse("A").unwrap())
  assert_false(@codegen.Null.is_truthy())
  assert_false(@codegen.Bool(false).is_truthy())
  assert_false(@codegen.Text("").is_truthy())
  assert_false(@codegen.List([]).is_truthy())
  assert_false(@codegen.Record({}).is_truthy())
  assert_true(@codegen.Bool(true).is_truthy())
  assert_true(@codegen.Int(0).is_truthy())
  assert_true(@codegen.Text("x").is_truthy())
  assert_true(@codegen.List([@codegen.Null]).is_truthy())
  assert_true(@codegen.Record({ "a": @codegen.Null }).is_truthy())
  assert_true(@codegen.Sym(sym).is_truthy())
  assert_true(@codegen.Ref(@codegen.SymbolReference::new(sym)).is_truthy())
  assert_true(@codegen.Call(_ => ()).is_truthy())
}

///|
test "json string literals" {
  assert_eq(@codegen.json_string_literal(""), "\"\"")
  assert_eq(@codegen.json_string_literal("a/b"), "\"a/b\"")
  assert_eq(@codegen.json_string_literal("\u{1f}"), "\"\\u001f\"")
}
