///|
/// Where an expression takes its value from.
priv enum ArgSource {
  /// `$L`: the next argument.
  Relative
  /// `$1L`: the argument at a 1-based position.
  Positional(Int32)
  /// `$name:L` or `${name:L}`: a value of the context.
  Named(String)
}

///|
/// One piece of a parsed template.
priv enum Token {
  Literal(String)
  /// An expression: its source, its formatter and the offset of its `$`.
  Expr(ArgSource, Char, Int32)
}

///|
/// A parsed template: its tokens and its length in characters.
priv struct ParsedTemplate {
  tokens : Array[Token]
  length : Int32
}

///|
/// The error for a bad template: `I found {problem} at offset {n} in template `{template}`.`
fn template_error(
  problem : String,
  offset : Int32,
  template : String,
) -> CodegenError {
  InvalidTemplate(
    "I found \{problem} at offset \{offset} in template `\{template}`.",
  )
}

///|
fn is_upper(c : Char) -> Bool {
  c >= 'A' && c <= 'Z'
}

///|
fn is_lower(c : Char) -> Bool {
  c >= 'a' && c <= 'z'
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_name_char(c : Char) -> Bool {
  is_lower(c) || is_upper(c) || is_digit(c) || c == '_' || c == '.'
}

///|
/// Parse a template into tokens. The parser is one loop over the characters
/// with a cursor; it does not recurse. Offsets count characters of the
/// template as written. A `\r\n` pair becomes `\n`.
fn parse_template(template : String) -> ParsedTemplate raise CodegenError {
  let chars = template.to_array()
  let length = chars.length()
  let tokens : Array[Token] = []
  let literal = StringBuilder()
  let mut pos = 0
  while pos < length {
    let c = chars[pos]
    if c == '\r' && pos + 1 < length && chars[pos + 1] == '\n' {
      pos += 1
      continue
    }
    if c != '$' {
      literal.write_char(c)
      pos += 1
      continue
    }
    let start = pos
    pos += 1
    if pos >= length {
      raise template_error("a `$` at the end of the template", start, template)
    }
    let next = chars[pos]
    if next == '$' {
      literal.write_char('$')
      pos += 1
      continue
    }
    if !literal.is_empty() {
      tokens.push(Literal(literal.to_string()))
      literal.reset()
    }
    if next == '{' {
      pos += 1
      let source = parse_source(chars, template, start, pos, true)
      pos = source.2
      tokens.push(Expr(source.0, source.1, start))
    } else {
      let source = parse_source(chars, template, start, pos, false)
      pos = source.2
      tokens.push(Expr(source.0, source.1, start))
    }
  }
  if !literal.is_empty() {
    tokens.push(Literal(literal.to_string()))
  }
  { tokens, length, }
}

///|
/// Parse the source and the formatter of an expression that starts at `pos`
/// (after `$` or after `${`). It returns the source, the formatter and the
/// position after the expression. For a braced expression it reads the `}`.
fn parse_source(
  chars : Array[Char],
  template : String,
  start : Int32,
  from : Int32,
  braced : Bool,
) -> (ArgSource, Char, Int32) raise CodegenError {
  let length = chars.length()
  let mut pos = from
  // In a braced expression the end of the template always means "not closed".
  let unclosed = "a `${` that is not closed"
  if pos >= length {
    raise template_error(unclosed, start, template)
  }
  let first = chars[pos]
  let mut source = Relative
  let mut formatter = ' '
  if is_upper(first) {
    formatter = first
    pos += 1
  } else if is_digit(first) {
    let digits = StringBuilder()
    while pos < length && is_digit(chars[pos]) {
      digits.write_char(chars[pos])
      pos += 1
    }
    let text = digits.to_string()
    if text.length() > 9 {
      raise template_error(
        "a position `\{text}` that is too large",
        start,
        template,
      )
    }
    if pos >= length {
      raise template_error(
        if braced {
          unclosed
        } else {
          "a position `\{text}` without a formatter"
        },
        start,
        template,
      )
    }
    if !is_upper(chars[pos]) {
      raise template_error(
        "a position `\{text}` followed by `\{chars[pos]}` instead of a formatter",
        start,
        template,
      )
    }
    let mut index = 0
    for digit in text {
      index = index * 10 + (digit.to_int() - '0'.to_int())
    }
    if index < 1 {
      raise template_error(
        "a position `\{text}`, but positions start at 1",
        start,
        template,
      )
    }
    source = Positional(index)
    formatter = chars[pos]
    pos += 1
  } else if is_lower(first) {
    let name = StringBuilder()
    while pos < length && is_name_char(chars[pos]) {
      name.write_char(chars[pos])
      pos += 1
    }
    let name = name.to_string()
    if pos >= length {
      raise template_error(
        if braced {
          unclosed
        } else {
          "a name `\{name}` without `:` and a formatter"
        },
        start,
        template,
      )
    }
    if chars[pos] != ':' {
      raise template_error(
        "a name `\{name}` followed by `\{chars[pos]}` instead of `:`",
        start,
        template,
      )
    }
    pos += 1
    if pos >= length {
      raise template_error(
        if braced {
          unclosed
        } else {
          "a name `\{name}:` without a formatter"
        },
        start,
        template,
      )
    }
    if !is_upper(chars[pos]) {
      raise template_error(
        "a name `\{name}:` followed by `\{chars[pos]}` instead of a formatter",
        start,
        template,
      )
    }
    source = Named(name)
    formatter = chars[pos]
    pos += 1
  } else {
    raise template_error(
      if braced {
        "a `${` followed by `\{first}`"
      } else {
        "a `$` followed by `\{first}`"
      },
      start,
      template,
    )
  }
  if braced {
    if pos >= length {
      raise template_error(unclosed, start, template)
    }
    if chars[pos] != '}' {
      raise template_error(
        "a `${` expression with `\{chars[pos]}` where I expected `}`",
        start,
        template,
      )
    }
    pos += 1
  }
  (source, formatter, pos)
}
