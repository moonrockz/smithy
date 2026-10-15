///|
/// `NodeObjectKey = QuotedText / Identifier`.
fn Parser::parse_object_key(
  self : Parser,
) -> @ast.Node[String] raise ParseError {
  match self.peek() {
    Some(t) if t.kind == Identifier => {
      ignore(self.advance())
      @ast.Node::new(t.lexeme, t.span)
    }
    Some(t) if t.kind == @scanner.TokenKind::String => {
      ignore(self.advance())
      @ast.Node::new(@scanner.unescape(t.lexeme), t.span)
    }
    _ =>
      self.fail(
        "SM-PARSE-001",
        "UNEXPECTED TOKEN",
        "I was expecting a key (an identifier or a quoted string) but found \{self.found()}",
        self.here(),
      )
  }
}

///|
/// Task 10 fills this in; for now only quoted strings.
fn Parser::parse_node_value(self : Parser) -> @ast.NodeValue raise ParseError {
  let t = self.expect_kind(@scanner.TokenKind::String, "a value")
  String(@scanner.unescape(t.lexeme), t.span)
}
