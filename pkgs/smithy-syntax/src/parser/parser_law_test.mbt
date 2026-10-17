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
test "law: every AST descendant lies inside its parent and siblings are in order" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let r = @parser.parse_text(t.text())
      guard r.ast is Some(_) else { return true }
      let stack = [@traversal.NodeRef::of_result(r).unwrap()]
      let mut ok = true
      while stack.pop() is Some(parent) {
        let children = parent.children()
        let mut last = parent.span().start
        for child in children {
          let span = child.span()
          ok = ok && span.start >= last && span.end() <= parent.span().end()
          last = span.start
          stack.push(child)
        }
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
test "law: any text parses the same from its CST source" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let r1 = @parser.parse_text(t.text())
      let r2 = @parser.parse_text(r1.cst.to_source())
      r1 == r2
    },
    count=400,
    max_size=16,
    seed=3036,
  )
}
