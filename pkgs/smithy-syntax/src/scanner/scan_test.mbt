///|
fn off(n : Int32) -> @span.Offset raise {
  guard @span.Offset::new(n) is Some(o) else { fail("bad offset") }
  o
}

///|
fn stream(text : String) -> @scanner.TokenStream {
  @scanner.tokenize_text(text)
}

///|
fn kinds(text : String) -> Array[@scanner.TokenKind] {
  stream(text).tokens.iter().map(t => t.kind).collect()
}

///|
fn lexemes(text : String) -> Array[String] {
  stream(text).tokens.iter().map(t => t.lexeme).collect()
}

///|
fn codes(text : String) -> Array[String] {
  stream(text).diagnostics.iter().map(d => d.code).collect()
}

///|
test "scan_at is a pure function of the text and an offset" {
  let text = "ab cd"
  guard @scanner.scan_at(text, off(3)) is Some(step) else { fail("no step") }
  debug_inspect(
    step.piece,
    content="Tok(Identifier, \"cd\", { start: Offset(3), length: Length(2) })",
  )
  debug_inspect(step.end, content="Offset(5)")
  inspect(step.diagnostics.length(), content="0")
  inspect(@scanner.scan_at(text, off(5)) is None, content="true")
  // Calling it twice gives the same answer: nothing is remembered.
  inspect(
    @scanner.scan_at(text, off(3)) == @scanner.scan_at(text, off(3)),
    content="true",
  )
}

///|
test "punctuation" {
  @expect.expect(kinds("@ : := = . # $ { } [ ] ( )")).to_equal([
    At,
    Colon,
    Walrus,
    Equal,
    Dot,
    Pound,
    Dollar,
    LBrace,
    RBrace,
    LBracket,
    RBracket,
    LParen,
    RParen,
  ])
}

///|
test "identifiers and keywords are identifiers" {
  @expect.expect(lexemes("namespace smithy.example _x __y1 Foo_Bar")).to_equal([
    "namespace", "smithy", ".", "example", "_x", "__y1", "Foo_Bar",
  ])
  debug_inspect(kinds("structure")[0], content="Identifier")
}

///|
test "a shape id scans as adjacent pieces" {
  @expect.expect(kinds("smithy.api#String$member")).to_equal([
    Identifier,
    Dot,
    Identifier,
    Pound,
    Identifier,
    Dollar,
    Identifier,
  ])
}

///|
test "whitespace, commas and comments are trivia" {
  let s = stream(
    (
      #|a, b // c
      #|/// doc
      #|d
    ),
  )
  inspect(s.tokens.length(), content="3")
  @expect.expect(s.tokens[0].trivia_after.map(t => t.text())).to_equal([
    ",", " ",
  ])
  @expect.expect(s.tokens[1].trivia_after.map(t => t.text())).to_equal([
    " ", "// c", "\n",
  ])
  @expect.expect(s.tokens[2].trivia_before.map(t => t.text())).to_equal([
    "/// doc", "\n",
  ])
  guard s.tokens[2].trivia_before[0] is Comment(c) else {
    fail("not a comment")
  }
  debug_inspect(c.kind, content="Doc")
  inspect(c.text, content=" doc")
  debug_inspect(c.span, content="{ start: Offset(10), length: Length(7) }")
}

///|
test "trivia after a token stops at the first line break" {
  let s = stream(
    (
      #|a
      #|
      #|  b
    ),
  )
  @expect.expect(s.tokens[0].trivia_after.map(t => t.text())).to_equal(["\n"])
  @expect.expect(s.tokens[1].trivia_before.map(t => t.text())).to_equal([
    "\n", "  ",
  ])
}

///|
test "CRLF is one newline trivia and the scan is lossless" {
  let text = "string Foo\r\nstring Bar\r\n"
  let s = stream(text)
  inspect(s.to_source() == text, content="true")
  @expect.expect(s.tokens[1].trivia_after.map(t => t.text())).to_equal(["\r\n"])
  inspect(s.tokens[1].trivia_after[0].is_newline(), content="true")
}

///|
test "a text with only trivia keeps it on the stream" {
  let s = stream(
    (
      #|  // hi
      #|
    ),
  )
  inspect(s.tokens.length(), content="0")
  inspect(s.trivia.length(), content="3")
  inspect(
    s.to_source(),
    content=(
      #|  // hi
      #|
    ),
  )
}

///|
test "an unexpected character is an Error token with SM-SCAN-001" {
  let s = stream("a ^ b")
  @expect.expect(kinds("a ^ b")).to_equal([Identifier, Error, Identifier])
  @expect.expect(codes("a ^ b")).to_equal(["SM-SCAN-001"])
  inspect(s.to_source(), content="a ^ b")
  inspect(s.diagnostics[0].message, content="I don't know what to do with `^`")
}

///|
test "a lone CR is whitespace, not a newline" {
  @expect.expect(stream("a\rb").tokens[0].trivia_after.map(t => t.text())).to_equal([
      "\r",
    ],
  )
  inspect(
    stream("a\rb").tokens[0].trivia_after[0].is_newline(),
    content="false",
  )
}

///|
test "the pipeline stages compose" {
  let text = "a b"
  let steps = @scanner.scan_pieces(text)
  inspect(steps.length(), content="3")
  let s = text |> @scanner.scan_pieces |> @scanner.attach_trivia
  inspect(s.tokens.length(), content="2")
  inspect(s == stream(text), content="true")
}

///|
test "a comma is trivia even without surrounding spaces" {
  let stream = @scanner.tokenize_text("a,b")
  assert_eq(stream.tokens.map(t => t.lexeme), ["a", "b"])
  assert_true(stream.tokens[0].trivia_after[0] is Comma(_))
  assert_eq(stream.to_source(), "a,b")
  let only = @scanner.tokenize_text(",")
  assert_true(only.tokens.is_empty())
  assert_true(only.trivia[0] is Comma(_))
  assert_eq(only.to_source(), ",")
}
