///|
test "law: the parser never panics and the CST is lossless for any text" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let text = t.text()
      @parser.parse_text(text).cst.to_source() == text
    },
    count=400,
    max_size=16,
    seed=3031,
  )
}

///|
test "law: CST statements tile the token array in order" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let r = @parser.parse_text(t.text())
      let mut at = 0
      let mut ok = true
      for s in r.cst.statements {
        ok = ok && s.tokens.length() > 0
        if s.tokens.length() > 0 {
          ok = ok && s.tokens[0] == r.cst.tokens[at]
          at += s.tokens.length()
        }
      }
      ok && at == r.cst.tokens.length()
    },
    count=400,
    max_size=16,
    seed=3032,
  )
}

///|
test "law: every AST statement span lies inside the file span and statements are in order" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let r = @parser.parse_text(t.text())
      guard r.ast is Some(f) else { return true }
      let mut last = @span.Offset::zero()
      let mut ok = true
      for s in f.statements {
        let sp = s.span()
        ok = ok && sp.start >= last && sp.end() <= f.span.end()
        last = sp.start
      }
      ok
    },
    count=400,
    max_size=16,
    seed=3033,
  )
}

///|
test "law: every diagnostic code is in the table and every span is inside the text" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let text = t.text()
      let r = @parser.parse_text(text)
      r.diagnostics
      .iter()
      .all(d => {
        @diagnostic.description(d.code) is Some(_) &&
        d.span.end().0 <= text.length()
      })
    },
    count=400,
    max_size=16,
    seed=3034,
  )
}

///|
/// The lexical structure of the rest of the file stays intact; a lost
/// quote re-pairs every later quote and is covered by the scanner laws,
/// not this one.
test "law: one edit to a valid model gives at most three diagnostics and keeps most shapes" {
  @quickcheck.check(
    (m : @lawkit.EditedModel) => {
      let r = @parser.parse_text(m.text())
      guard r.ast is Some(f) else { return r.diagnostics.length() <= 3 }
      // The small model has 8 shape statements and 1 apply.
      r.diagnostics.length() <= 3 && f.shapes().length() >= 5
    },
    count=300,
    max_size=16,
    seed=3035,
  )
}

///|
test "law: a valid model parses the same from its CST source" {
  @quickcheck.check(
    (_u : Unit) => {
      let r1 = @parser.parse_text(@lawkit.small_model())
      let r2 = @parser.parse_text(r1.cst.to_source())
      r1.ast == r2.ast && r1.diagnostics.length() == 0
    },
    count=1,
    seed=3036,
  )
}
