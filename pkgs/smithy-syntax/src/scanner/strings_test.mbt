///|
fn skinds(text : String) -> Array[@scanner.TokenKind] {
  @scanner.tokenize_text(text).tokens.iter().map(t => t.kind).collect()
}

///|
fn scodes(text : String) -> Array[String] {
  @scanner.tokenize_text(text).diagnostics.iter().map(d => d.code).collect()
}

///|
test "quoted strings" {
  @expect.expect(
    skinds(
      (
        #|"" "hi" "a\"b" "multi
        #|line"
      ),
    ),
  ).to_equal([String, String, String, String])
  inspect(
    @scanner.tokenize_text("\"a\\\"b\"").tokens[0].lexeme,
    content="\"a\\\"b\"",
  )
}

///|
test "an unterminated string runs to the end and is SM-SCAN-002" {
  let s = @scanner.tokenize_text(
    (
      #|"abc
      #|string Foo
    ),
  )
  @expect.expect(
    skinds(
      (
        #|"abc
        #|string Foo
      ),
    ),
  ).to_equal([Error])
  @expect.expect(
    scodes(
      (
        #|"abc
        #|string Foo
      ),
    ),
  ).to_equal(["SM-SCAN-002"])
  inspect(
    s.to_source(),
    content=(
      #|"abc
      #|string Foo
    ),
  )
}

///|
test "bad escapes keep the String token and report each one" {
  @expect.expect(skinds("\"a\\qb\"")).to_equal([String])
  @expect.expect(scodes("\"a\\qb\"")).to_equal(["SM-SCAN-005"])
  @expect.expect(scodes("\"\\q\\z\"")).to_equal(["SM-SCAN-005", "SM-SCAN-005"])
  @expect.expect(scodes("\"\\u12\"")).to_equal(["SM-SCAN-006"])
  @expect.expect(scodes("\"\\u12G4\"")).to_equal(["SM-SCAN-006"])
  @expect.expect(scodes("\"\\n\\t\\r\\b\\f\\/\\\\\\\"\\u00e9\"")).to_equal([])
}

///|
test "text blocks" {
  let text =
    #|"""
    #|    hello
    #|    """
  @expect.expect(skinds(text)).to_equal([TextBlock])
  @expect.expect(scodes(text)).to_equal([])
  inspect(@scanner.tokenize_text(text).tokens[0].lexeme == text, content="true")
}

///|
test "a text block may hold one or two quotes in a row" {
  let text =
    #|"""
    #|  say "hi" or ""hey""
    #|  """
  @expect.expect(skinds(text)).to_equal([TextBlock])
}

///|
/// Pins the reference's `valid/text-blocks.smithy` and `valid/traits.smithy`:
/// `\` before a line break is the text block line-continuation escape, not
/// an unknown escape.
test "a backslash before a line break escapes the line break" {
  let text =
    #|"""
    #|    Hi \
    #|    there \
    #|    bye"""
  @expect.expect(skinds(text)).to_equal([TextBlock])
  @expect.expect(scodes(text)).to_equal([])
  @expect.expect(@scanner.text_block_value(text)).to_equal("Hi there bye")
}

///|
test "a backslash before a CRLF line break is the same continuation escape" {
  let block = "\"\"\"\r\na\\\r\nb\r\n\"\"\""
  @expect.expect(skinds(block)).to_equal([TextBlock])
  @expect.expect(scodes(block)).to_equal([])
  @expect.expect(@scanner.text_block_value(block)).to_equal("ab\n")
  // A quoted string spanning lines decodes it the same way.
  let quoted = "\"a\\\r\nb\""
  @expect.expect(scodes(quoted)).to_equal([])
  @expect.expect(@scanner.unescape(quoted)).to_equal("ab")
}

///|
test "a text block must start with a line break" {
  @expect.expect(scodes("\"\"\"hello\"\"\"")).to_equal(["SM-SCAN-004"])
  @expect.expect(skinds("\"\"\"hello\"\"\"")).to_equal([TextBlock])
  @expect.expect(
    scodes(
      (
        #|"""
        #| x
        #|"""
      ),
    ),
  ).to_equal([])
}

///|
test "an unterminated text block is SM-SCAN-003" {
  @expect.expect(
    scodes(
      (
        #|"""
        #| abc
      ),
    ),
  ).to_equal(["SM-SCAN-003"])
  @expect.expect(
    skinds(
      (
        #|"""
        #| abc
      ),
    ),
  ).to_equal([Error])
}
