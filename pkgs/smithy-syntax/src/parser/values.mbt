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
/// Whether `c` is an ASCII digit.
fn is_number_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// The digits of `chars` from `start`, and the index after them.
fn number_digits(chars : Array[Char], start : Int32) -> (String, Int32) {
  let n = chars.length()
  let mut i = start
  while i < n && is_number_digit(chars[i]) {
    i += 1
  }
  (String::from_array(chars[start:i]), i)
}

///|
/// The largest exponent magnitude a number lexeme may have. Past it the
/// exact value would need `10^n` digits for a huge `n`, so the parser
/// reports the number instead of computing it.
let max_number_exponent : Int32 = 4096

///|
/// Split a scanner-validated `Number` lexeme (`[-] int [. frac]
/// [e|E [+|-] digits]`) into its sign, integer digits, fraction digits
/// (empty when there is no `.`) and exponent (`0` when there is no
/// `e`/`E`). The exponent saturates: once its magnitude passes
/// `max_number_exponent` it stops growing, so a long run of exponent
/// digits never overflows.
fn split_number_lexeme(text : String) -> (String, String, String, Int32) {
  let chars = text.to_array()
  let n = chars.length()
  let mut i = 0
  let sign = if i < n && chars[i] == '-' {
    i += 1
    "-"
  } else {
    ""
  }
  let (int_digits, after_int) = number_digits(chars, i)
  i = after_int
  let frac_digits = if i < n && chars[i] == '.' {
    let (digits, after_frac) = number_digits(chars, i + 1)
    i = after_frac
    digits
  } else {
    ""
  }
  let exponent = if i < n && (chars[i] == 'e' || chars[i] == 'E') {
    i += 1
    let exp_sign = if i < n && chars[i] == '-' {
      i += 1
      -1
    } else {
      if i < n && chars[i] == '+' {
        i += 1
      }
      1
    }
    let (exp_digits, _) = number_digits(chars, i)
    let mut exp_value = 0
    for ch in exp_digits {
      if exp_value > max_number_exponent {
        break
      }
      exp_value = exp_value * 10 + (ch.to_int() - '0'.to_int())
    }
    exp_sign * exp_value
  } else {
    0
  }
  (sign, int_digits, frac_digits, exponent)
}

///|
/// The exact decimal value of a lexeme with a `.` or an exponent (or
/// both), as `coefficient * 10^(-scale)`: no `Double` involved, so no
/// lexeme the scanner accepts can lose precision. `span` is the number
/// token's span, for the diagnostic when the scale is unrepresentable.
fn Parser::decimal_from_lexeme(
  self : Parser,
  text : String,
  span : @span.Span,
) -> @decimal.Decimal raise ParseError {
  let (sign, int_digits, frac_digits, exponent) = split_number_lexeme(text)
  if exponent > max_number_exponent || exponent < -max_number_exponent {
    self.fail(
      "SM-PARSE-001",
      "NUMBER TOO LARGE",
      "I cannot represent `\{text}` exactly: its exponent is beyond \{max_number_exponent}",
      span,
      hint="Use an exponent between -\{max_number_exponent} and \{max_number_exponent}.",
    )
  }
  let mut coefficient = BigInt::from_string(sign + int_digits + frac_digits)
  let mut scale = frac_digits.length() - exponent
  if scale < 0 {
    coefficient *= BigInt::from_int(10).pow(BigInt::from_int(-scale))
    scale = 0
  }
  match @decimal.Decimal::new(coefficient, scale) {
    Some(d) => d
    // `Decimal::new` rejects a negative scale (never produced here) or
    // one past `max_scale` (28): more decimal places than Smithy numbers
    // can hold.
    None =>
      self.fail(
        "SM-PARSE-001",
        "NUMBER TOO PRECISE",
        "I cannot represent `\{text}` exactly: it needs more than 28 decimal places",
        span,
        hint="Round the number to at most 28 decimal places.",
      )
  }
}

///|
/// The exact value of a `Number` token.
fn Parser::parse_number(
  self : Parser,
  t : @scanner.Token,
) -> @ast.NumberLiteral raise ParseError {
  let text = t.lexeme
  let value : @ast.NumberValue = if @scanner.is_integer_lexeme(text) {
    Integer(BigInt::from_string(text))
  } else {
    match @decimal.Decimal::from_string(text) {
      Some(d) => Decimal(d)
      // The scanner validated the digits; a lexeme the decimal parser
      // rejects (an exponent form it does not take) is parsed exactly
      // from its digits instead.
      None => Decimal(self.decimal_from_lexeme(text, t.span))
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
    if !self.at_kind(close) && !self.at_end() {
      self.expect_separator(construct=what)
    }
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
        self.here_anchored(),
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
