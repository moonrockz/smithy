///|
fn o(n : Int32) -> @span.Offset raise {
  guard @span.Offset::new(n) is Some(x) else { fail("bad offset \{n}") }
  x
}

///|
test "a span is a start and a length, half open" {
  let s = o(2).to(o(5))
  @expect.expect_all(e => {
    e.expect(s.start).to_equal(o(2))
    e.expect(s.end()).to_equal(o(5))
    e.expect(s.contains(o(2))).to_be_true()
    e.expect(s.contains(o(4))).to_be_true()
    e.expect(s.contains(o(5))).to_be_false()
    e.expect(o(3).to(o(3)).is_empty()).to_be_true()
    e.expect(o(5).to(o(2))).to_equal(s)
  })
  debug_inspect(s, content="{ start: Offset(2), length: Length(3) }")
}

///|
test "join covers both spans" {
  let a = o(2).to(o(5))
  let b = o(9).to(o(12))
  @expect.expect(a.join(b)).to_equal(o(2).to(o(12)))
  @expect.expect(b.join(a)).to_equal(o(2).to(o(12)))
}

///|
test "positions compare and print" {
  let p = @span.Position::new(@span.Line::first().next(), @span.Column::first())
  debug_inspect(p, content="{ line: Line(2), column: Column(1) }")
}
