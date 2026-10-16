///|
fn nkinds(text : String) -> Array[@scanner.TokenKind] {
  @scanner.tokenize_text(text).tokens.iter().map(t => t.kind).collect()
}

///|
fn ncodes(text : String) -> Array[String] {
  @scanner.tokenize_text(text).diagnostics.iter().map(d => d.code).collect()
}

///|
test "valid numbers" {
  for
    text in [
      "0", "7", "42", "-1", "1.5", "-0.25", "1e3", "1E-3", "2.5e+10", "0.0",
    ] {
    @expect.expect(nkinds(text)).because(text).to_equal([Number])
    @expect.expect(ncodes(text)).because(text).to_equal([])
  }
}

///|
test "invalid numbers are one Error token with SM-SCAN-007" {
  for text in ["01", "1.", "1e", "1e+", "-", "-a", "1.e5", "00"] {
    @expect.expect(nkinds(text)[0]).because(text).to_equal(Error)
    @expect.expect(ncodes(text)).because(text).to_equal(["SM-SCAN-007"])
  }
  inspect(@scanner.tokenize_text("01 x").to_source(), content="01 x")
}

///|
test "a number stops at punctuation" {
  @expect.expect(nkinds("[1,2]")).to_equal([LBracket, Number, Number, RBracket])
}

///|
test "is_integer_lexeme" {
  @expect.expect_all(e => {
    e.expect(@scanner.is_integer_lexeme("42")).to_be_true()
    e.expect(@scanner.is_integer_lexeme("-42")).to_be_true()
    e.expect(@scanner.is_integer_lexeme("4.2")).to_be_false()
    e.expect(@scanner.is_integer_lexeme("4e2")).to_be_false()
  })
}
