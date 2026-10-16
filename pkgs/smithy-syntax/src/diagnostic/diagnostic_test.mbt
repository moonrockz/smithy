///|
fn sp(a : Int32, b : Int32) -> @span.Span raise {
  guard @span.Offset::new(a) is Some(x) && @span.Offset::new(b) is Some(y) else {
    fail("bad span")
  }
  x.to(y)
}

///|
test "a diagnostic has defaults for the optional parts" {
  let d = @diagnostic.Diagnostic::new(
    code="SM-PARSE-001",
    severity=Error,
    title="UNEXPECTED TOKEN",
    message="I was expecting a shape name here",
    span=sp(4, 7),
  )
  @expect.expect_all(e => {
    e.expect(d.is_error()).to_be_true()
    e.expect(d.labels.length()).to_equal(0)
    e.expect(d.notes.length()).to_equal(0)
    e.expect(d.hint).to_equal(None)
    e.expect(d.example).to_equal(None)
  })
}

///|
test "a warning is not an error" {
  let d = @diagnostic.Diagnostic::new(
    code="SM-PARSE-009",
    severity=Warning,
    title="DETACHED DOC COMMENT",
    message="this documentation comment is not followed by a shape",
    span=sp(0, 10),
    hint="Move it right before the shape it documents.",
  )
  inspect(d.is_error(), content="false")
  debug_inspect(
    d.hint,
    content="Some(\"Move it right before the shape it documents.\")",
  )
}

///|
test "with_context prepends a label and a note and keeps the rest" {
  let d = @diagnostic.Diagnostic::new(
    code="SM-PARSE-001",
    severity=Error,
    title="UNEXPECTED TOKEN",
    message="m",
    span=sp(4, 7),
    notes=["later"],
  )
  let c = d.with_context(
    { span: sp(0, 9), text: "the structure started here", },
    "I was parsing a structure.",
  )
  @expect.expect_all(e => {
    e.expect(c.labels.length()).to_equal(1)
    e.expect(c.labels[0].text).to_equal("the structure started here")
    e
    .expect(c.notes.to_owned())
    .to_equal(["I was parsing a structure.", "later"])
    e.expect(c.message).to_equal("m")
    e.expect(d.labels.length()).to_equal(0)
  })
}

///|
test "every code has a description and the table is in order" {
  let codes = @diagnostic.codes()
  inspect(codes.length(), content="22")
  inspect(codes[0], content="SM-SCAN-001")
  inspect(codes[7], content="SM-PARSE-001")
  inspect(codes[17], content="SM-PARSE-011")
  inspect(codes[20], content="SM-PARSE-014")
  inspect(codes[21], content="SM-PARSE-015")
  for c in codes {
    inspect(@diagnostic.description(c) is Some(_), content="true")
  }
  debug_inspect(@diagnostic.description("SM-NOPE-001"), content="None")
}
