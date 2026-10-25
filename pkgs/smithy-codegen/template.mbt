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
/// The kind of an opening block tag.
priv enum BlockKind {
  /// `${?name}`: render when the value is truthy.
  If
  /// `${^name}`: render when the value is falsy.
  Unless
  /// `${#name}` or `${#name as key, value}`: the names of the key and the value.
  Loop(String, String)
}

///|
/// One piece of a parsed template.
priv enum Token {
  Literal(String)
  /// An expression: its source, its formatter, whether the value is aligned
  /// (`|`) and the offset of its `$`.
  Expr(ArgSource, Char, Bool, Int32)
  /// An opening block tag: its kind, the name of its value and the offset of its `$`.
  Open(BlockKind, String, Int32)
  /// A closing block tag. `matching` has the index of its opening tag.
  Close
}

///|
/// A parsed template: its tokens and its length in characters. For an opening
/// or closing tag, `matching` has the index of the other tag of the block. For
/// all other tokens it has -1.
priv struct ParsedTemplate {
  tokens : Array[Token]
  matching : Array[Int32]
  length : Int32
}

///|
/// An expression that the parser read.
priv struct ParsedExpr {
  source : ArgSource
  formatter : Char
  align : Bool
  trim_after : Bool
  /// The position after the expression.
  end : Int32
}

///|
/// A block tag that the parser read.
priv struct ParsedBlock {
  sigil : Char
  name : String
  /// The names of the key and the value of a loop.
  loop_names : (String, String)
  trim_after : Bool
  /// The position after the tag.
  end : Int32
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
fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
fn is_block_sigil(c : Char) -> Bool {
  c == '?' || c == '^' || c == '#' || c == '/'
}

///|
/// Remove the trailing characters of the set from the literal text.
fn trim_literal_end(literal : StringBuilder, chars : String) -> Unit {
  let text = literal.to_string()
  literal.reset()
  literal.write_string(text.trim_end(chars~).to_owned())
}

///|
/// When the tag from `start` to `end` is the only thing on its line, besides
/// spaces and tabs, give the position after the newline of that line. The end
/// of the template also ends a line.
fn standalone_end(chars : Array[Char], start : Int32, end : Int32) -> Int32? {
  let length = chars.length()
  let mut before = start - 1
  while before >= 0 && (chars[before] == ' ' || chars[before] == '\t') {
    before -= 1
  }
  if before >= 0 && chars[before] != '\n' {
    return None
  }
  let mut after = end
  while after < length && (chars[after] == ' ' || chars[after] == '\t') {
    after += 1
  }
  if after >= length {
    Some(after)
  } else if chars[after] == '\n' {
    Some(after + 1)
  } else if chars[after] == '\r' &&
    after + 1 < length &&
    chars[after + 1] == '\n' {
    Some(after + 2)
  } else {
    None
  }
}

///|
/// Parse a template into tokens. The parser is one loop over the characters
/// with a cursor and a stack of open blocks; it does not recurse. Offsets
/// count characters of the template as written. A `\r\n` pair becomes `\n`.
/// A block that is not closed, a closing tag with another name and a closing
/// tag without an opening tag are errors.
fn parse_template(template : String) -> ParsedTemplate raise CodegenError {
  let chars = template.to_array()
  let length = chars.length()
  let tokens : Array[Token] = []
  let matching : Array[Int32] = []
  // The indexes of the opening tags that are not closed yet.
  let open_tags : Array[Int32] = []
  let literal = StringBuilder()
  fn push_token(token : Token) -> Unit {
    if !literal.is_empty() {
      tokens.push(Literal(literal.to_string()))
      matching.push(-1)
      literal.reset()
    }
    tokens.push(token)
    matching.push(-1)
  }

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
    if next != '{' {
      let expr = parse_source(chars, template, start, pos, false, false)
      pos = expr.end
      push_token(Expr(expr.source, expr.formatter, false, start))
      continue
    }
    pos += 1
    let trim_before = pos < length && chars[pos] == '-'
    if trim_before {
      pos += 1
    }
    if pos < length && is_block_sigil(chars[pos]) {
      let block = parse_block(chars, template, start, pos + 1)
      // A tag that is alone on its line takes the line with it.
      match standalone_end(chars, start, block.end) {
        Some(line_end) => {
          trim_literal_end(literal, " \t")
          pos = line_end
        }
        None => pos = block.end
      }
      if trim_before {
        trim_literal_end(literal, " \t\n\r")
      }
      if block.trim_after {
        while pos < length && is_space(chars[pos]) {
          pos += 1
        }
      }
      let index = tokens.length() + (if literal.is_empty() { 0 } else { 1 })
      match block.sigil {
        '/' =>
          match open_tags.pop() {
            None =>
              raise template_error(
                "a closing tag `${/\{block.name}}` without an open tag",
                start,
                template,
              )
            Some(open) => {
              match tokens[open] {
                Open(_, open_name, _) =>
                  if open_name != block.name {
                    raise template_error(
                      "a closing tag `${/\{block.name}}` where I expected `${/\{open_name}}`",
                      start,
                      template,
                    )
                  }
                _ => ()
              }
              push_token(Close)
              matching[open] = index
              matching[index] = open
            }
          }
        sigil => {
          let kind = match sigil {
            '?' => If
            '^' => Unless
            _ => Loop(block.loop_names.0, block.loop_names.1)
          }
          push_token(Open(kind, block.name, start))
          open_tags.push(index)
        }
      }
      continue
    }
    let expr = parse_source(chars, template, start, pos, true, trim_before)
    pos = expr.end
    if trim_before {
      trim_literal_end(literal, " \t\n\r")
    }
    push_token(Expr(expr.source, expr.formatter, expr.align, start))
    if expr.trim_after {
      while pos < length && is_space(chars[pos]) {
        pos += 1
      }
    }
  }
  if open_tags.pop() is Some(open) {
    match tokens[open] {
      Open(kind, name, offset) => {
        let sigil = match kind {
          If => '?'
          Unless => '^'
          Loop(_, _) => '#'
        }
        raise template_error(
          "a `${\{sigil}\{name}}` that is not closed",
          offset,
          template,
        )
      }
      _ => ()
    }
  }
  if !literal.is_empty() {
    tokens.push(Literal(literal.to_string()))
    matching.push(-1)
  }
  { tokens, matching, length, }
}

///|
/// Read a name of a block or of a loop variable at `from`. It starts with a
/// lowercase letter. It gives the empty text when there is no name.
fn read_name(chars : Array[Char], from : Int32) -> String {
  if from >= chars.length() || !is_lower(chars[from]) {
    return ""
  }
  let name = StringBuilder()
  let mut pos = from
  while pos < chars.length() && is_name_char(chars[pos]) {
    name.write_char(chars[pos])
    pos += 1
  }
  name.to_string()
}

///|
/// Read a loop variable of `${#name as key, value}` at `from`.
fn read_variable(
  chars : Array[Char],
  template : String,
  start : Int32,
  from : Int32,
  after : String,
) -> String raise CodegenError {
  let unclosed = "a `${` that is not closed"
  if from >= chars.length() {
    raise template_error(unclosed, start, template)
  }
  let name = read_name(chars, from)
  if name.is_empty() {
    raise template_error(
      "a loop tag with `\{chars[from]}` after `\{after}` where I expected a name",
      start,
      template,
    )
  }
  if name.contains(".") {
    raise template_error(
      "a loop variable `\{name}` with a `.` in its name",
      start,
      template,
    )
  }
  name
}

///|
/// Parse a block tag. `from` is the position after the sigil. The sigil is
/// `?`, `^`, `#` or `/`. For a loop it reads `as key, value`; without it the
/// variables are `key` and `value`. It reads the `-` before the `}` and the `}`.
fn parse_block(
  chars : Array[Char],
  template : String,
  start : Int32,
  from : Int32,
) -> ParsedBlock raise CodegenError {
  let length = chars.length()
  let sigil = chars[from - 1]
  let unclosed = "a `${` that is not closed"
  let mut pos = from
  if pos >= length {
    raise template_error(unclosed, start, template)
  }
  let name = read_name(chars, pos)
  if name.is_empty() {
    raise template_error(
      "a `${\{sigil}` tag followed by `\{chars[pos]}` where I expected a name",
      start,
      template,
    )
  }
  pos += name.length()
  let mut loop_names = ("key", "value")
  if sigil == '#' && pos < length && chars[pos] == ' ' {
    while pos < length && chars[pos] == ' ' {
      pos += 1
    }
    if pos + 2 < length &&
      chars[pos] == 'a' &&
      chars[pos + 1] == 's' &&
      chars[pos + 2] == ' ' {
      pos += 3
      while pos < length && chars[pos] == ' ' {
        pos += 1
      }
      let key = read_variable(chars, template, start, pos, "as")
      pos += key.length()
      while pos < length && chars[pos] == ' ' {
        pos += 1
      }
      if pos >= length {
        raise template_error(unclosed, start, template)
      }
      if chars[pos] != ',' {
        raise template_error(
          "a loop tag with `\{chars[pos]}` after `as \{key}` where I expected `,`",
          start,
          template,
        )
      }
      pos += 1
      while pos < length && chars[pos] == ' ' {
        pos += 1
      }
      let value = read_variable(chars, template, start, pos, "as \{key},")
      pos += value.length()
      loop_names = (key, value)
    } else if pos >= length {
      raise template_error(unclosed, start, template)
    } else {
      raise template_error(
        "a loop tag with `\{chars[pos]}` after `\{name}` where I expected `as`",
        start,
        template,
      )
    }
  }
  let mut trim_after = false
  if pos < length && chars[pos] == '-' {
    trim_after = true
    pos += 1
  }
  if pos >= length {
    raise template_error(unclosed, start, template)
  }
  if chars[pos] != '}' {
    raise template_error(
      "a `${\{sigil}\{name}` tag with `\{chars[pos]}` where I expected `}`",
      start,
      template,
    )
  }
  { sigil, name, loop_names, trim_after, end: pos + 1, }
}

///|
/// Parse the source and the formatter of an expression that starts at `pos`
/// (after `$` or after `${`). It returns the source, the formatter and the
/// position after the expression. For a braced expression it reads `|`, `-`
/// and the `}`.
fn parse_source(
  chars : Array[Char],
  template : String,
  start : Int32,
  from : Int32,
  braced : Bool,
  trim_before : Bool,
) -> ParsedExpr raise CodegenError {
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
  let mut align = false
  let mut trim_after = false
  if braced {
    if pos < length && chars[pos] == '|' {
      if trim_before {
        raise template_error(
          "an alignment `|` in a tag that starts with `-`", start, template,
        )
      }
      align = true
      pos += 1
    }
    if pos < length && chars[pos] == '-' {
      trim_after = true
      pos += 1
    }
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
  { source, formatter, align, trim_after, end: pos, }
}
