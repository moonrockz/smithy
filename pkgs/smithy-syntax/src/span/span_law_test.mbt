///|
fn pick(rs : @splitmix.RandomState, n : Int32) -> Int32 {
  rs.next_uint(limit=n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
/// A random non-negative offset, at most 1000.
pub(all) struct AnyOffset(@span.Offset) derive(Debug)

///|
pub impl @quickcheck.Arbitrary for AnyOffset with fn arbitrary(_size, rs) {
  AnyOffset(@span.Offset::new(pick(rs, 1001)).unwrap())
}

///|
/// `check` requires `Shrink`; these generators don't shrink, so the default
/// (empty) implementation is enough.
pub impl @quickcheck.Shrink for AnyOffset

///|
pub(all) struct AnyLength(@span.Length) derive(Debug)

///|
pub impl @quickcheck.Arbitrary for AnyLength with fn arbitrary(_size, rs) {
  AnyLength(@span.Length::new(pick(rs, 1001)).unwrap())
}

///|
pub impl @quickcheck.Shrink for AnyLength

///|
/// A random text of ASCII letters, spaces, LF, CRLF and lone CR, with an
/// offset inside it (or at its end).
pub(all) struct TextAndOffset(String, @span.Offset) derive(Debug)

///|
pub impl @quickcheck.Arbitrary for TextAndOffset with fn arbitrary(size, rs) {
  let pieces = ["a", "b", " ", "\n", "\r\n", "\r", "é", "\u{1F600}"]
  let sb = StringBuilder()
  for _ in 0..<pick(rs, size + 1) {
    sb.write_string(pieces[pick(rs, pieces.length())])
  }
  let text = sb.to_string()
  TextAndOffset(text, @span.Offset::new(pick(rs, text.length() + 1)).unwrap())
}

///|
pub impl @quickcheck.Shrink for TextAndOffset

///|
test "law: Offset::new accepts exactly the non-negative ints" {
  @quickcheck.check(
    (n : Int32) => (@span.Offset::new(n) is Some(_)) == (n >= 0),
    count=300,
    seed=1001,
  )
  @quickcheck.check(
    (n : Int32) => (@span.Length::new(n) is Some(_)) == (n >= 0),
    count=300,
    seed=1002,
  )
  @quickcheck.check(
    (n : Int32) => (@span.Line::new(n) is Some(_)) == (n >= 1),
    count=300,
    seed=1003,
  )
  @quickcheck.check(
    (n : Int32) => (@span.Column::new(n) is Some(_)) == (n >= 1),
    count=300,
    seed=1004,
  )
}

///|
test "law: advance and distance round-trip, and advance never moves backwards" {
  @quickcheck.check(
    (p : (AnyOffset, AnyLength)) => {
      let (AnyOffset(o), AnyLength(l)) = p
      let moved = o.advance(l)
      o.distance(moved) == l &&
      moved >= o &&
      o.next() == o.advance(@span.Length::one())
    },
    count=300,
    seed=1005,
  )
}

///|
test "law: distance and to are symmetric, and to's end is the larger offset" {
  @quickcheck.check(
    (p : (AnyOffset, AnyOffset)) => {
      let (AnyOffset(a), AnyOffset(b)) = p
      let s = a.to(b)
      a.distance(b) == b.distance(a) &&
      s == b.to(a) &&
      s.end() == (if a > b { a } else { b }) &&
      s.start == (if a < b { a } else { b }) &&
      s.length == a.distance(b)
    },
    count=300,
    seed=1006,
  )
}

///|
test "law: Length addition is a commutative monoid with zero" {
  @quickcheck.check(
    (p : (AnyLength, AnyLength, AnyLength)) => {
      let (AnyLength(a), AnyLength(b), AnyLength(c)) = p
      a + b == b + a &&
      a + b + c == a + (b + c) &&
      a + @span.Length::zero() == a
    },
    count=300,
    seed=1007,
  )
}

///|
test "law: a span contains its start when non-empty and never its end; join covers and is idempotent" {
  @quickcheck.check(
    (p : (AnyOffset, AnyOffset, AnyOffset, AnyOffset)) => {
      let (AnyOffset(a), AnyOffset(b), AnyOffset(c), AnyOffset(d)) = p
      let s = a.to(b)
      let u = c.to(d)
      let j = s.join(u)
      s.contains(s.start) == !s.is_empty() &&
      !s.contains(s.end()) &&
      j == u.join(s) &&
      j.join(s) == j &&
      j.start <= s.start &&
      j.start <= u.start &&
      j.end() >= s.end() &&
      j.end() >= u.end()
    },
    count=300,
    seed=1008,
  )
}

///|
test "law: position and line_span agree, and position is monotone in the offset" {
  @quickcheck.check(
    (t : TextAndOffset) => {
      let TextAndOffset(text, o) = t
      let st = @span.SourceText::new(text)
      let p = st.position(o)
      guard st.line_span(p.line) is Some(ls) else { return false }
      // The column counts units from the line start, also on the line break.
      let agrees = o.0 - ls.start.0 + 1 == p.column.0 && o >= ls.start
      let in_range = p.line.0 >= 1 && p.line.0 <= st.line_count()
      let monotone = o.0 == 0 ||
        ({
          let q = st.position(@span.Offset::new(o.0 - 1).unwrap())
          q.line < p.line || (q.line == p.line && q.column < p.column)
        })
      agrees && in_range && monotone
    },
    count=400,
    max_size=24,
    seed=1009,
  )
}

///|
test "law: slice of a line span is the line text and never panics on any span" {
  @quickcheck.check(
    (t : TextAndOffset) => {
      let TextAndOffset(text, o) = t
      let st = @span.SourceText::new(text)
      let p = st.position(o)
      let by_line = st.line_span(p.line).map(s => st.slice(s)) ==
        st.line_text(p.line)
      let any_span = st.slice(o.to(st.end())).length() == st.end().0 - o.0
      by_line && any_span
    },
    count=300,
    max_size=24,
    seed=1010,
  )
}

///|
test "law: slice clamps arbitrary endpoints to the text length" {
  @quickcheck.check(
    (p : (TextAndOffset, AnyOffset, AnyOffset)) => {
      let (TextAndOffset(text, _), AnyOffset(a), AnyOffset(b)) = p
      let span = a.to(b)
      let n = text.length()
      let lo = if span.start.0 > n { n } else { span.start.0 }
      let hi = if span.end().0 > n { n } else { span.end().0 }
      @span.SourceText::new(text).slice(span) ==
      text.unsafe_substring(start=lo, end=hi)
    },
    count=400,
    seed=1012,
  )
}
