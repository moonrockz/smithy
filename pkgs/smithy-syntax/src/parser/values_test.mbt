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
test "exponent-form numbers are exact" {
  guard value("1e19") is Number(n, _) else { fail("not a number") }
  guard n.value is Decimal(d) else { fail("not a decimal") }
  inspect(
    d.to_bigint() == BigInt::from_string("10000000000000000000"),
    content="true",
  )
  guard value("2.5e+10") is Number(a, _) else { fail("not a number") }
  inspect(a.as_double(), content="25000000000")
  guard value("1E-3") is Number(b, _) else { fail("not a number") }
  inspect(b.as_double(), content="0.001")
  guard b.value is Decimal(bd) else { fail("not a decimal") }
  inspect(bd.scale(), content="3")
  guard value("-1.25e2") is Number(c, _) else { fail("not a number") }
  inspect(c.as_double(), content="-125")
}

///|
test "a number needing more than 28 decimal places is reported" {
  // The too-precise number is the file's last token here, but its
  // diagnostic points at the number itself, not at end-of-input, so it
  // keeps its own code (`Parser::fail` only remaps to `SM-PARSE-002` when
  // the span it is given is the end-of-input span).
  @expect.expect(vcodes("1e-40")).to_equal(["SM-PARSE-001"])
  let r = @parser.parse_text(
    (
      $|metadata v = 1e-40
      $|
    ),
  )
  inspect(r.errors()[0].title, content="NUMBER TOO PRECISE")
  // The limit itself (28 places) still parses.
  guard value("1e-28") is Number(n, _) else { fail("not a number") }
  guard n.value is Decimal(d) else { fail("not a decimal") }
  inspect(d.scale(), content="28")
}

///|
test "a number whose exponent is beyond 4096 is reported, not computed" {
  for
    text in [
      "1e2147483648", "1e-2147483648", "1e4294967297", "1e99999999999", "1e10000000",
    ] {
    let r = @parser.parse_text("metadata v = \{text}\n")
    @expect.expect(r.diagnostics.iter().map(d => d.code).collect()).to_equal([
      "SM-PARSE-001",
    ])
    inspect(r.errors()[0].title, content="NUMBER TOO LARGE")
    inspect(
      r.errors()[0].message,
      content="I cannot represent `\{text}` exactly: its exponent is beyond 4096",
    )
    debug_inspect(
      r.errors()[0].hint,
      content=(
        #|Some("Use an exponent between -4096 and 4096.")
      ),
    )
  }
  // The bound itself still parses, exactly.
  guard value("1e4096") is Number(n, _) else { fail("not a number") }
  guard n.value is Decimal(d) else { fail("not a decimal") }
  inspect(d.scale(), content="0")
  inspect(n.text, content="1e4096")
}

///|
test "a value missing at the end of the file is still SM-PARSE-002" {
  // Unlike the too-precise number above, this diagnostic's span really is
  // the end-of-input span (nothing follows `=`), so the remap applies.
  @expect.expect(vcodes("")).to_equal(["SM-PARSE-002"])
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

///|
test "object pairs and trait structure pairs require whitespace" {
  for
    text in [
      "metadata x = {a:\"x\"b:\"y\"}", "namespace a\n@t(a:\"x\"b:\"y\")\nstring S",
    ] {
    let r = @parser.parse_text(text)
    assert_true(r.has_errors(), msg=text)
  }
  for sep in [" ", ",", "\n", "// comment\n"] {
    let r = @parser.parse_text("metadata x = {a:\"x\"" + sep + "b:\"y\"}")
    assert_false(r.has_errors(), msg=sep)
  }
}

///|
test "huge exact numbers convert to signed infinity, not zero" {
  for text in ["1e4096", "-1e4096"] {
    let r = @parser.parse_text("metadata x = " + text)
    assert_false(r.has_errors())
    guard r.ast is Some(f) && f.metadata[0].value is Number(n, _) else {
      fail("no number")
    }
    assert_true(
      if text.has_prefix("-") {
        n.as_double().is_neg_inf()
      } else {
        n.as_double().is_pos_inf()
      },
    )
  }
}

///|
test "object and trait separator messages name the construct and offending key" {
  for
    (text, construct) in [
      ("metadata x = {a:\"x\"b:\"y\"}", "an object"),
      ("namespace a\n@t(a:\"x\"b:\"y\")\nstring S", "a trait body"),
    ] {
    let result = @parser.parse_text(text)
    assert_eq(result.errors().length(), 1)
    let diagnostic = result.errors()[0]
    assert_eq(diagnostic.code, "SM-PARSE-003")
    assert_eq(
      diagnostic.message,
      "I was expecting whitespace between entries in \{construct} but found `b`",
    )
    assert_true(
      diagnostic.notes.contains(
        "I separate entries in \{construct} with whitespace.",
      ),
    )
    assert_true(diagnostic.notes.iter().all(note => !note.contains("member")))
  }
}
