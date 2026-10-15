///|
fn off(n : Int32) -> @span.Offset raise {
  guard @span.Offset::new(n) is Some(o) else { fail("bad offset \{n}") }
  o
}

///|
fn len(n : Int32) -> @span.Length raise {
  guard @span.Length::new(n) is Some(l) else { fail("bad length \{n}") }
  l
}

///|
test "offsets and lengths are never negative" {
  debug_inspect(@span.Offset::new(-1), content="None")
  debug_inspect(@span.Length::new(-1), content="None")
  debug_inspect(@span.Offset::new(0).map(o => o.0), content="Some(0)")
  debug_inspect(@span.Line::new(0), content="None")
  debug_inspect(@span.Column::new(0), content="None")
  inspect(@span.Line::first().0, content="1")
}

///|
test "offset arithmetic" {
  @expect.expect_all(e => {
    e.expect(off(3).advance(len(4))).to_equal(off(7))
    e.expect(off(3).next()).to_equal(off(4))
    e.expect(off(3).distance(off(10))).to_equal(len(7))
    e.expect(off(10).distance(off(3))).to_equal(len(7))
    e.expect(len(2) + len(3)).to_equal(len(5))
    e.expect(off(2) < off(3)).to_be_true()
    e.expect(@span.Length::of_string("héllo")).to_equal(len(5))
  })
}

///|
test "lines and columns step" {
  inspect(@span.Line::first().next().0, content="2")
  inspect(@span.Column::first().next().0, content="2")
}
