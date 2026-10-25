///|
fn orders_model() -> @smithy.Model {
  @smithy.Loader::new()
  .add_idl(
    "a.smithy", "$version: \"2\"\nnamespace example\nstructure Order {\n  type: String\n  id: String\n}\nstructure Error {}\nstructure type {}\n",
  )
  .assemble().model.unwrap()
}

///|
fn simple_symbol(
  shape : @smithy.Shape,
) -> @codegen.Symbol raise @codegen.CodegenError {
  match @codegen.SymbolName::parse(shape.id.name()) {
    Some(name) => @codegen.Symbol::new(name)
    None => raise @codegen.InvalidSettings("bad name")
  }
}

///|
test "cached calls the base provider once per shape" {
  let model = orders_model()
  let calls = Ref(0)
  let provider = @codegen.SymbolProvider::new(shape => {
    calls.val += 1
    simple_symbol(shape)
  }).cached()
  let order = model.get("example#Order").unwrap()
  let error = model.get("example#Error").unwrap()
  let first = provider.to_symbol(order)
  let second = provider.to_symbol(order)
  assert_eq(first, second)
  assert_eq(calls.val, 1)
  let _ = provider.to_symbol(error)
  assert_eq(calls.val, 2)
}

///|
test "cached does not cache errors" {
  let model = orders_model()
  let calls = Ref(0)
  let provider = @codegen.SymbolProvider::new(shape => {
    calls.val += 1
    if calls.val == 1 {
      raise @codegen.InvalidSettings("first")
    }
    simple_symbol(shape)
  }).cached()
  let order = model.get("example#Order").unwrap()
  try provider.to_symbol(order) catch {
    @codegen.InvalidSettings("first") => ()
    e => fail("unexpected error: \{e.message()}")
  } noraise {
    _ => fail("expected an error")
  }
  let ok = provider.to_symbol(order)
  assert_eq(ok.name.to_string(), "Order")
  assert_eq(calls.val, 2)
}

///|
test "decorate runs after the base provider" {
  let model = orders_model()
  let provider = @codegen.SymbolProvider::new(simple_symbol).decorate((
    shape,
    symbol,
  ) => symbol.with_property("shape", Json::string(shape.id.to_string())))
  let symbol = provider.to_symbol(model.get("example#Order").unwrap())
  assert_eq(symbol.property("shape"), Some(Json::string("example#Order")))
}

///|
test "the default member name is the member part of the shape id" {
  let model = orders_model()
  let provider = @codegen.SymbolProvider::new(simple_symbol)
  assert_eq(
    provider.to_member_name(model.get("example#Order$id").unwrap()),
    "id",
  )
  assert_eq(
    provider.to_member_name(model.get("example#Order").unwrap()),
    "Order",
  )
}

///|
test "a custom member name function replaces the default" {
  let model = orders_model()
  let provider = @codegen.SymbolProvider::new(simple_symbol, to_member_name=shape => {
    shape.id.to_string()
  })
  assert_eq(
    provider.to_member_name(model.get("example#Order$id").unwrap()),
    "example#Order$id",
  )
}

///|
test "reserved words escape symbols and members separately" {
  let model = orders_model()
  let provider = @codegen.SymbolProvider::new(simple_symbol).with_reserved_words(
    symbols=@codegen.ReservedWords::new(["Error"]),
    members=@codegen.ReservedWords::new(["type"]),
  )
  let error = provider.to_symbol(model.get("example#Error").unwrap())
  assert_eq(error.name.to_string(), "Error_")
  let member_name_text = provider.to_member_name(
    model.get("example#Order$type").unwrap(),
  )
  assert_eq(member_name_text, "type_")
  let kept = provider.to_symbol(model.get("example#type").unwrap())
  assert_eq(kept.name.to_string(), "type")
  let order_member = provider.to_member_name(
    model.get("example#Order$id").unwrap(),
  )
  assert_eq(order_member, "id")
}

///|
test "a reserved word escape that is blank raises an error" {
  let model = orders_model()
  let provider = @codegen.SymbolProvider::new(simple_symbol).with_reserved_words(
    symbols=@codegen.ReservedWords::new(["Error"], escape=_ => "a b"),
    members=@codegen.ReservedWords::new([]),
  )
  try provider.to_symbol(model.get("example#Error").unwrap()) catch {
    @codegen.InvalidSettings(_) => ()
    e => fail("unexpected error: \{e.message()}")
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "provider errors propagate" {
  let model = orders_model()
  let provider = @codegen.SymbolProvider::new(_ => {
    raise @codegen.InvalidSettings("x")
  })
  let order = model.get("example#Order").unwrap()
  try provider.to_symbol(order) catch {
    @codegen.InvalidSettings("x") => ()
    e => fail("unexpected error: \{e.message()}")
  } noraise {
    _ => fail("expected an error")
  }
  try provider.cached().to_symbol(order) catch {
    @codegen.InvalidSettings("x") => ()
    e => fail("unexpected error: \{e.message()}")
  } noraise {
    _ => fail("expected an error")
  }
}
