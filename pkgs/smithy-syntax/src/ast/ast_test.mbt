///|
fn sp(a : Int32, b : Int32) -> @span.Span raise {
  guard @span.Offset::new(a) is Some(x) && @span.Offset::new(b) is Some(y) else {
    fail("bad span")
  }
  x.to(y)
}

///|
test "shape ids print as written" {
  inspect(
    @ast.ShapeId::new("String", namespace="smithy.api"),
    content="smithy.api#String",
  )
  inspect(@ast.ShapeId::new("Foo", member="bar"), content="Foo$bar")
  inspect(@ast.ShapeId::new("Foo").is_absolute(), content="false")
}

///|
test "keywords map to shape kinds" {
  @expect.expect_all(e => {
    e
    .expect(@ast.ShapeKind::of("structure"))
    .to_equal(Some(Aggregate(Structure)))
    e.expect(@ast.ShapeKind::of("intEnum")).to_equal(Some(Enum(IntEnum)))
    e
    .expect(@ast.ShapeKind::of("bigDecimal"))
    .to_equal(Some(Simple(BigDecimal)))
    e.expect(@ast.ShapeKind::of("operation")).to_equal(Some(Operation))
    e.expect(@ast.ShapeKind::of("apply")).to_equal(None)
    e.expect(@ast.SimpleType::Timestamp.keyword()).to_equal("timestamp")
    e
    .expect(@ast.ShapeKind::Aggregate(Structure).to_string())
    .to_equal("structure")
    e.expect(@ast.ShapeKind::Simple(String).to_string()).to_equal("string")
  })
}

///|
test "number literals convert" {
  let i : @ast.NumberLiteral = {
    text: "42",
    value: Integer(BigInt::from_int(42)),
  }
  debug_inspect(i.as_int64(), content="Some(42)")
  inspect(i.as_double(), content="42")
  let huge : @ast.NumberLiteral = {
    text: "99999999999999999999",
    value: Integer(BigInt::from_string("99999999999999999999")),
  }
  debug_inspect(huge.as_int64(), content="None")
}

///|
test "node values expose strings and object keys" {
  let kvp : @ast.NodeKvp = {
    key: @ast.Node::new("a", sp(1, 2)),
    value: @ast.NodeValue::String("x", sp(4, 7)),
    span: sp(1, 7),
  }
  let kvps : Array[@ast.NodeKvp] = [kvp]
  let obj : @ast.NodeValue = Object(kvps[:], sp(0, 8))
  debug_inspect(obj.get("a").bind(v => v.as_string()), content="Some(\"x\")")
  debug_inspect(obj.get("b"), content="None")
  debug_inspect(obj.span(), content="{ start: Offset(0), length: Length(8) }")
}

///|
test "a shape reports its name and kind" {
  let s : @ast.Shape = Simple(
    kind=String,
    name=@ast.Node::new("Foo", sp(7, 10)),
    mixins=None,
  )
  inspect(s.name().value, content="Foo")
  debug_inspect(s.kind(), content="Simple(String)")
}

///|
test "every shape keyword round trips through ShapeKind" {
  for
    keyword in [
      "blob", "boolean", "document", "string", "byte", "short", "integer", "long",
      "float", "double", "bigInteger", "bigDecimal", "timestamp", "enum", "intEnum",
      "list", "map", "union", "structure", "set", "service", "resource", "operation",
    ] {
    let kind = @ast.ShapeKind::of(keyword).unwrap()
    assert_eq(kind.keyword(), keyword)
    assert_eq(kind.to_string(), keyword)
  }
}
