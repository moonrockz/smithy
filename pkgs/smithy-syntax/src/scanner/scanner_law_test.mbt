///|
test "law: the scan is lossless for any text" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let text = t.text()
      @scanner.tokenize_text(text).to_source() == text
    },
    count=400,
    max_size=16,
    seed=2031,
  )
}

///|
test "law: scan_at is pure and its steps chain to the end of the text" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let text = t.text()
      let mut at = @span.Offset::zero()
      let mut ok = true
      while @scanner.scan_at(text, at) is Some(step) {
        ok = ok && step.end > at && @scanner.scan_at(text, at) == Some(step)
        at = step.end
      }
      ok && at.0 == text.length()
    },
    count=400,
    max_size=16,
    seed=2037,
  )
}

///|
test "law: token and trivia spans tile the text in order" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let text = t.text()
      let s = @scanner.tokenize_text(text)
      let mut at = @span.Offset::zero()
      let mut ok = true
      let step = (span : @span.Span) => {
        ok = ok && span.start == at
        at = span.end()
      }
      for tr in s.trivia {
        step(tr.span())
      }
      for tok in s.tokens {
        for tr in tok.trivia_before {
          step(tr.span())
        }
        step(tok.span)
        for tr in tok.trivia_after {
          step(tr.span())
        }
      }
      ok && at.0 == text.length()
    },
    count=400,
    max_size=16,
    seed=2032,
  )
}

///|
test "law: every Error token has exactly one diagnostic that starts inside it" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let s = @scanner.tokenize_text(t.text())
      let errors = s.tokens.iter().filter(tok => tok.kind == Error).collect()
      let error_codes = [
        "SM-SCAN-001", "SM-SCAN-002", "SM-SCAN-003", "SM-SCAN-007",
      ]
      let error_diags = s.diagnostics
        .iter()
        .filter(d => error_codes.contains(d.code))
        .collect()
      if errors.length() != error_diags.length() {
        return false
      }
      let mut ok = true
      for i, tok in errors {
        let d = error_diags[i]
        ok = ok &&
          d.span.start >= tok.span.start &&
          d.span.start <= tok.span.end()
      }
      ok
    },
    count=400,
    max_size=16,
    seed=2033,
  )
}

///|
test "law: a lexeme is the source text of its span" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let text = t.text()
      let s = @scanner.tokenize_text(text)
      s.tokens
      .iter()
      .all(tok => {
        text.unsafe_substring(start=tok.span.start.0, end=tok.span.end().0) ==
        tok.lexeme
      })
    },
    count=300,
    max_size=16,
    seed=2034,
  )
}

///|
test "law: trivia_after holds at most one newline, and it is last" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let s = @scanner.tokenize_text(t.text())
      let mut ok = true
      for i, tok in s.tokens {
        if i == s.tokens.length() - 1 {
          continue
        }
        let newlines = tok.trivia_after
          .iter()
          .filter(x => x.is_newline())
          .count()
        ok = ok && newlines <= 1
        if newlines == 1 {
          ok = ok &&
            tok.trivia_after[tok.trivia_after.length() - 1].is_newline()
        }
      }
      ok
    },
    count=300,
    max_size=16,
    seed=2035,
  )
}

///|
test "law: every diagnostic code is in the table" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let s = @scanner.tokenize_text(t.text())
      s.diagnostics.iter().all(d => @diagnostic.description(d.code) is Some(_))
    },
    count=300,
    max_size=16,
    seed=2036,
  )
}
