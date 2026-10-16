///|
fn at(n : Int32) -> @span.Offset raise {
  guard @span.Offset::new(n) is Some(x) else { fail("bad offset \{n}") }
  x
}

///|
fn pos(line : Int32, column : Int32) -> @span.Position raise {
  guard @span.Line::new(line) is Some(l) && @span.Column::new(column) is Some(c) else {
    fail("bad position")
  }
  @span.Position::new(l, c)
}

///|
test "positions are 1-based and count UTF-16 units" {
  let st = @span.SourceText::new("ab\ncd\r\nef")
  @expect.expect_all(e => {
    e.expect(st.line_count()).to_equal(3)
    e.expect(st.position(at(0))).to_equal(pos(1, 1))
    e.expect(st.position(at(2))).to_equal(pos(1, 3))
    e.expect(st.position(at(3))).to_equal(pos(2, 1))
    e.expect(st.position(at(7))).to_equal(pos(3, 1))
    // Past the end clamps to the end of the last line.
    e.expect(st.position(at(99))).to_equal(pos(3, 3))
    e.expect(st.end()).to_equal(at(9))
  })
}

///|
test "a lone CR is not a line break" {
  let st = @span.SourceText::new("a\rb\nc")
  inspect(st.line_count(), content="2")
  inspect(st.position(at(2)).line.0, content="1")
}

///|
test "line_text strips the line break" {
  let st = @span.SourceText::new("ab\ncd\r\nef")
  let l = (n : Int32) => @span.Line::new(n).unwrap()
  @expect.expect_all(e => {
    e.expect(st.line_text(l(1))).to_equal(Some("ab"))
    e.expect(st.line_text(l(2))).to_equal(Some("cd"))
    e.expect(st.line_text(l(3))).to_equal(Some("ef"))
    e.expect(st.line_text(l(4))).to_equal(None)
    e.expect(st.line_span(l(2))).to_equal(Some(at(3).to(at(5))))
    e.expect(st.slice(at(3).to(at(5)))).to_equal("cd")
  })
}

///|
test "a surrogate pair is two columns, as the reference counts" {
  let st = @span.SourceText::new("\u{1F600}x")
  inspect(st.position(at(2)).column.0, content="3")
}

///|
test "name is optional" {
  debug_inspect(
    @span.SourceText::new("", name="a.smithy").name(),
    content="Some(\"a.smithy\")",
  )
  debug_inspect(@span.SourceText::new("").name(), content="None")
}
