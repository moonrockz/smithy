///|
/// Parse `metadata v = <text>` and return the value.
fn value(text : String) -> @ast.NodeValue raise {
  let r = @parser.parse_text(
    (
      $|metadata v = \{text}
      $|
    ),
  )
  guard r.ast is Some(f) && f.metadata.length() == 1 else {
    fail("no value: \{r.diagnostics.iter().map(d => d.message).join(", ")}")
  }
  f.metadata[0].value
}

///|
fn vcodes(text : String) -> Array[String] {
  @parser.parse_text(
    (
      $|metadata v = \{text}
      $|
    ),
  ).diagnostics
  .iter()
  .map(d => d.code)
  .collect()
}

///|
test "scalars" {
  @expect.expect_all(e => {
    e.expect(value("\"hi\"").as_string()).to_equal(Some("hi"))
    e.expect(value("true") is Keyword(True, _)).to_be_true()
    e.expect(value("null") is Keyword(Null, _)).to_be_true()
    e.expect(value("Foo") is ShapeId({ name: "Foo", .. }, _)).to_be_true()
    e
    .expect(
      value("a.b#C$d")
      is ShapeId({ namespace: Some("a.b"), name: "C", member: Some("d"), }, _),
    )
    .to_be_true()
  })
}

///|
test "numbers are exact" {
  guard value("42") is Number(n, _) else { fail("not a number") }
  inspect(n.text, content="42")
  debug_inspect(n.as_int64(), content="Some(42)")
  guard value("-1.50") is Number(d, _) else { fail("not a number") }
  debug_inspect(d.value is Decimal(_), content="true")
  inspect(d.as_double(), content="-1.5")
  guard value("1e3") is Number(x, _) else { fail("not a number") }
  inspect(x.as_double(), content="1000")
  guard value("99999999999999999999") is Number(big, _) else {
    fail("not a number")
  }
  debug_inspect(big.as_int64(), content="None")
}

///|
test "arrays and objects with optional commas and nested values" {
  let v = value(
    (
      #|[1, 2 3,
      #| {a: "x", "b c": [true]}]
    ),
  )
  guard v is Array(items, _) else { fail("not an array") }
  inspect(items.length(), content="4")
  debug_inspect(
    items[3].get("a").bind(x => x.as_string()),
    content="Some(\"x\")",
  )
  guard items[3].get("b c") is Some(Array(inner, _)) else { fail("no b c") }
  inspect(inner.length(), content="1")
  inspect(value("{}") is Object(_, _), content="true")
  inspect(value("[]") is Array(_, _), content="true")
}

///|
test "a text block value is decoded" {
  debug_inspect(
    value(
      (
        #|"""
        #|    hello
        #|    """
      ),
    ).as_string(),
    content="Some(\"hello\\n\")",
  )
}

///|
test "an unclosed array is reported once with the array as context" {
  let r = @parser.parse_text(
    (
      #|metadata v = [1, 2
      #|namespace a
      #|
    ),
  )
  inspect(r.errors().length(), content="1")
  let d = r.errors()[0]
  inspect(d.labels[0].text, content="an array started here")
  inspect(d.notes[0], content="I was parsing an array when I got stuck.")
}

///|
test "a missing colon in an object names the key" {
  let r = @parser.parse_text(
    (
      #|metadata v = {a "x"}
      #|
    ),
  )
  inspect(
    r.errors()[0].message,
    content="I was expecting `:` after the key `a` but found a string",
  )
}

///|
test "150 nested arrays is TOO MUCH NESTING, not a crash" {
  let sb = StringBuilder()
  for _ in 0..<150 {
    sb.write_string("[")
  }
  for _ in 0..<150 {
    sb.write_string("]")
  }
  @expect.expect(vcodes(sb.to_string())).to_equal(["SM-PARSE-010"])
  // 90 deep is fine.
  let ok = StringBuilder()
  for _ in 0..<90 {
    ok.write_string("[")
  }
  for _ in 0..<90 {
    ok.write_string("]")
  }
  @expect.expect(vcodes(ok.to_string())).to_equal([])
}
