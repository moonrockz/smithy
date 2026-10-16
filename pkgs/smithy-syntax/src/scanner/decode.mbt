///|
/// The decoded form of `s`: the escapes the specification lists; an
/// unknown or malformed escape is kept verbatim; `\` before a line break
/// (`\n` or `\r\n`; text blocks) adds nothing.
fn decode_escapes(s : String) -> String {
  let sb = StringBuilder()
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.code_unit_at(i).to_int().unsafe_to_char()
    if c != '\\' || i + 1 >= n {
      sb.write_char(c)
      i += 1
      continue
    }
    let e = s.code_unit_at(i + 1).to_int().unsafe_to_char()
    match e {
      '\\' | '"' | '/' => {
        sb.write_char(e)
        i += 2
      }
      'b' => {
        sb.write_char('\u{8}')
        i += 2
      }
      'f' => {
        sb.write_char('\u{c}')
        i += 2
      }
      'n' => {
        sb.write_char('\n')
        i += 2
      }
      'r' => {
        sb.write_char('\r')
        i += 2
      }
      't' => {
        sb.write_char('\t')
        i += 2
      }
      '\n' => i += 2
      '\r' if i + 2 < n && s.code_unit_at(i + 2).to_int() == '\n'.to_int() =>
        i += 3
      'u' => {
        let mut value = 0
        let mut good = 0
        while good < 4 && i + 2 + good < n {
          let h = s.code_unit_at(i + 2 + good).to_int().unsafe_to_char()
          guard is_hex(h) else { break }
          let d = if is_digit(h) {
            h.to_int() - '0'.to_int()
          } else if h >= 'a' {
            h.to_int() - 'a'.to_int() + 10
          } else {
            h.to_int() - 'A'.to_int() + 10
          }
          value = value * 16 + d
          good += 1
        }
        if good == 4 {
          sb.write_char(value.unsafe_to_char())
          i += 6
        } else {
          sb.write_char('\\')
          i += 1
        }
      }
      _ => {
        sb.write_char('\\')
        i += 1
      }
    }
  }
  sb.to_string()
}

///|
/// The value of a `String` token: the lexeme with its quotes removed and
/// its escapes decoded.
pub fn unescape(lexeme : String) -> String {
  let inner = if lexeme.length() >= 2 {
    lexeme.unsafe_substring(start=1, end=lexeme.length() - 1)
  } else {
    ""
  }
  decode_escapes(inner)
}

///|
fn leading_spaces(line : String) -> Int32 {
  let mut k = 0
  while k < line.length() && line.code_unit_at(k).to_int() == ' '.to_int() {
    k += 1
  }
  k
}

///|
fn is_blank(line : String) -> Bool {
  leading_spaces(line) == line.length()
}

///|
/// The lines of a text block body, line breaks removed (`\r\n` and `\n`).
fn block_lines(body : String) -> Array[String] {
  body
  .split(
    (
      #|
      #|
    ),
  )
  .map(raw => raw.trim_end(chars="\r").to_owned())
  .collect()
}

///|
/// The common leading-space count: over the non-blank lines, and over the
/// last line even when blank (it holds the closing quotes' indent).
fn common_indent(lines : Array[String]) -> Int32 {
  let last = lines.length() - 1
  let mut common = -1
  for idx, line in lines {
    if idx != last && is_blank(line) {
      continue
    }
    let k = leading_spaces(line)
    if common < 0 || k < common {
      common = k
    }
  }
  if common < 0 {
    0
  } else {
    common
  }
}

///|
/// The value of a `TextBlock` token, per the specification: drop the
/// opening quotes, optional spaces and the first line break; split the rest
/// into lines; remove the common indent and trailing spaces; join with
/// `\n`; then decode escapes.
pub fn text_block_value(lexeme : String) -> String {
  let n = lexeme.length()
  guard n >= 6 else { return "" }
  let mut i = 3
  while i < n &&
        (
          lexeme.code_unit_at(i).to_int() == ' '.to_int() ||
          lexeme.code_unit_at(i).to_int() == '\t'.to_int()
        ) {
    i += 1
  }
  if i < n && lexeme.code_unit_at(i).to_int() == '\r'.to_int() {
    i += 1
  }
  if i < n && lexeme.code_unit_at(i).to_int() == '\n'.to_int() {
    i += 1
  }
  let lines = block_lines(lexeme.unsafe_substring(start=i, end=n - 3))
  let common = common_indent(lines)
  let last = lines.length() - 1
  lines
  .mapi((idx, line) => {
    if idx == last && is_blank(line) {
      // The closing quotes stood on their own line: the value ends with `\n`.
      ""
    } else {
      let cut = if leading_spaces(line) < common {
        leading_spaces(line)
      } else {
        common
      }
      line
      .unsafe_substring(start=cut, end=line.length())
      .trim_end(chars=" ")
      .to_owned()
    }
  })
  .join(
    (
      #|
      #|
    ),
  )
  |> decode_escapes
}
