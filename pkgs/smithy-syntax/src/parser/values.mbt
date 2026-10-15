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
/// `Decimal::from_double` rejects a precision that would push the scaled
/// value past `Int64`, which a fixed high precision does for anything but
/// tiny magnitudes (`1000` at precision 17 already overflows). Try the
/// highest precision that fits, down to an integer.
fn decimal_from_double(d : Double) -> @decimal.Decimal {
  let mut precision = 17
  while precision >= 0 {
    if @decimal.Decimal::from_double(d, precision) is Some(v) {
      return v
    }
    precision -= 1
  }
  @decimal.Decimal::from_int(0)
}

///|
/// The exact value of a `Number` token.
fn Parser::parse_number(
  _self : Parser,
  t : @scanner.Token,
) -> @ast.NumberLiteral {
  let text = t.lexeme
  let value : @ast.NumberValue = if @scanner.is_integer_lexeme(text) {
    Integer(BigInt::from_string(text))
  } else {
    match @decimal.Decimal::from_string(text) {
      Some(d) => Decimal(d)
      // The scanner validated the digits; a lexeme the decimal parser
      // rejects (an exponent form it does not take) falls back to a
      // double, which is still a decimal value.
      None =>
        Decimal(
          decimal_from_double(@string.parse_double(text) catch { _ => 0.0 }),
        )
    }
  }
  { text, value, }
}

///|
/// `NodeObjectKvp *(WS NodeObjectKvp)` up to `close` (not consumed).
fn Parser::parse_object_kvps(
  self : Parser,
  close : @scanner.TokenKind,
  what : String,
) -> Array[@ast.NodeKvp] raise ParseError {
  let kvps : Array[@ast.NodeKvp] = []
  while !self.at_kind(close) {
    if self.at_end() {
      self.fail(
        "SM-PARSE-002",
        "UNFINISHED \{what.to_upper()}",
        "I reached the end of the file while reading \{what}",
        self.here(),
        hint="Add the closing bracket.",
      )
    }
    let key = self.parse_object_key()
    guard self.at_kind(Colon) else {
      self.fail(
        "SM-PARSE-001",
        "UNEXPECTED TOKEN",
        "I was expecting `:` after the key `\{key.value}` but found \{self.found()}",
        self.here(),
        example="{ \{key.value}: \"value\" }",
      )
    }
    ignore(self.advance())
    let value = self.parse_node_value()
    kvps.push({ key, value, span: key.span.join(value.span()), })
  }
  kvps
}

///|
/// `NodeValue = NodeArray / NodeObject / Number / NodeKeyword / NodeStringValue`.
fn Parser::parse_node_value(self : Parser) -> @ast.NodeValue raise ParseError {
  match self.peek() {
    None =>
      self.fail(
        "SM-PARSE-002",
        "UNEXPECTED END OF FILE",
        "I was expecting a value but reached the end of the file",
        self.here(),
      )
    Some(t) =>
      match t.kind {
        LBracket => {
          ignore(self.advance())
          self.enter()
          self.push_context("an array", t.span)
          let items : Array[@ast.NodeValue] = []
          while !self.at_kind(RBracket) {
            if self.at_end() {
              self.fail(
                "SM-PARSE-002",
                "UNFINISHED ARRAY",
                "I reached the end of the file while reading an array",
                self.here(),
                hint="Add the closing `]`.",
              )
            }
            items.push(self.parse_node_value())
          }
          let close = self.expect_kind(RBracket, "`]`")
          self.pop_context()
          self.leave()
          Array(items[:], t.span.join(close.span))
        }
        LBrace => {
          ignore(self.advance())
          self.enter()
          self.push_context("an object", t.span)
          let kvps = self.parse_object_kvps(RBrace, "an object")
          let close = self.expect_kind(RBrace, "`}`")
          self.pop_context()
          self.leave()
          Object(kvps[:], t.span.join(close.span))
        }
        Number => {
          ignore(self.advance())
          Number(self.parse_number(t), t.span)
        }
        String => {
          ignore(self.advance())
          String(@scanner.unescape(t.lexeme), t.span)
        }
        TextBlock => {
          ignore(self.advance())
          TextBlock(@scanner.text_block_value(t.lexeme), t.span)
        }
        Identifier =>
          match t.lexeme {
            "true" => {
              ignore(self.advance())
              Keyword(True, t.span)
            }
            "false" => {
              ignore(self.advance())
              Keyword(False, t.span)
            }
            "null" => {
              ignore(self.advance())
              Keyword(Null, t.span)
            }
            _ => {
              let id = self.parse_shape_id()
              ShapeId(id.value, id.span)
            }
          }
        _ =>
          self.fail(
            "SM-PARSE-001",
            "UNEXPECTED TOKEN",
            "I was expecting a value but found \{self.found()}",
            self.here(),
            notes=[
              "A value is a string, a number, `true`, `false`, `null`, a shape ID, an array `[...]` or an object `{...}`.",
            ],
          )
      }
  }
}
