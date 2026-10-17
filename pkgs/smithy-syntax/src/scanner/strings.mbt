///|
/// Check one escape at `at` (which holds the `\`): the offset after it and
/// its diagnostic, if any. The token is still a string; `unescape` keeps a
/// bad escape verbatim.
fn check_escape(
  text : String,
  at : @span.Offset,
) -> (@span.Offset, @diagnostic.Diagnostic?) {
  match unit_at(text, at.next()) {
    Some('\\' | '"' | 'b' | 'f' | 'n' | 'r' | 't' | '/') =>
      (at.next().next(), None)
    // `\` before a line break is the text block line-continuation escape
    // (the specification's "escapes in text blocks"); `decode_escapes`
    // already reads it as adding nothing. A quoted string can span lines
    // too, so this is accepted there as well, for the same reason. A CRLF
    // line break is one break: `\` + `\r\n` is the same escape.
    Some('\n') => (at.next().next(), None)
    Some('\r') if unit_at(text, at.next().next()) is Some('\n') =>
      (at.next().next().next(), None)
    Some('u') => {
      let mut end = at.next().next()
      let mut good = 0
      while good < 4 && unit_at(text, end) is Some(c) && is_hex(c) {
        end = end.next()
        good += 1
      }
      if good < 4 {
        (
          end,
          Some(
            lexical(
              "SM-SCAN-006",
              "INVALID UNICODE ESCAPE",
              "a `\\u` escape needs exactly four hex digits",
              at.to(end),
              hint="Write the code point as four hex digits, like `\\u00e9`.",
            ),
          ),
        )
      } else {
        (end, None)
      }
    }
    Some(c) => {
      let end = at.next().next()
      (
        end,
        Some(
          lexical(
            "SM-SCAN-005",
            "UNKNOWN ESCAPE",
            "I don't know the escape `\\\{c}`",
            at.to(end),
            notes=[
              "The escapes I know are `\\\\`, `\\\"`, `\\b`, `\\f`, `\\n`, `\\r`, `\\t`, `\\/` and `\\uXXXX`.",
            ],
          ),
        ),
      )
    }
    None => (at.next(), None)
  }
}

///|
/// A quoted string (which may span lines) or a text block.
fn scan_string_or_text_block(text : String, at : @span.Offset) -> Step {
  if looking_at(text, at, "\"\"\"") {
    scan_text_block(text, at)
  } else {
    scan_quoted(text, at)
  }
}

///|
/// Read string content from `from` until `closer` matches. The offset of
/// the closer (or the end of the text) and the escape diagnostics found.
fn string_body(
  text : String,
  from : @span.Offset,
  closer : String,
) -> (@span.Offset, Array[@diagnostic.Diagnostic]) {
  let found : Array[@diagnostic.Diagnostic] = []
  let mut at = from
  while unit_at(text, at) is Some(c) {
    if c == '"' && looking_at(text, at, closer) {
      return (at, found)
    }
    if c == '\\' {
      let (after, d) = check_escape(text, at)
      if d is Some(x) {
        found.push(x)
      }
      at = after
    } else {
      at = at.next()
    }
  }
  (at, found)
}

///|
fn scan_quoted(text : String, at : @span.Offset) -> Step {
  let (closer, found) = string_body(text, at.next(), "\"")
  match unit_at(text, closer) {
    Some(_) => {
      let end = closer.next()
      {
        piece: Tok(String, slice(text, at, end), at.to(end)),
        end,
        diagnostics: found[:],
      }
    }
    None =>
      error_step(
        text,
        at,
        closer,
        lexical(
          "SM-SCAN-002",
          "UNTERMINATED STRING",
          "this string never ends",
          at.to(closer),
          hint="Add the closing `\"`.",
          notes=[
            "I found an opening quote but reached the end of the file before the closing one. A string may span lines, so I read everything after the quote as the string.",
          ],
        ),
      )
  }
}

///|
/// `TextBlock = ThreeDquotes [SP] NL *TextBlockContent ThreeDquotes`.
fn scan_text_block(text : String, at : @span.Offset) -> Step {
  let three = @span.Length::new(3).unwrap()
  let after_quotes = skip_while(text, at.advance(three), c => {
    c == ' ' || c == '\t'
  })
  let (content_start, has_break) = match unit_at(text, after_quotes) {
    Some('\n') => (after_quotes.next(), true)
    Some('\r') if peek(text, after_quotes, @span.Length::new(1).unwrap()) ==
      Some('\n') => (after_quotes.next().next(), true)
    _ => (at.advance(three), false)
  }
  let found : Array[@diagnostic.Diagnostic] = []
  if !has_break {
    found.push(
      lexical(
        "SM-SCAN-004",
        "TEXT BLOCK MUST START WITH A LINE BREAK",
        "the opening `\"\"\"` must be followed by a line break",
        at.to(content_start),
        hint="Put the text on the line after the opening quotes, and the closing quotes on their own line.",
      ),
    )
  }
  let (closer, escapes) = string_body(text, content_start, "\"\"\"")
  found.append(escapes)
  match unit_at(text, closer) {
    Some(_) => {
      let end = closer.advance(three)
      {
        piece: Tok(TextBlock, slice(text, at, end), at.to(end)),
        end,
        diagnostics: found[:],
      }
    }
    None =>
      error_step(
        text,
        at,
        closer,
        lexical(
          "SM-SCAN-003",
          "UNTERMINATED TEXT BLOCK",
          "this text block never ends",
          at.to(closer),
          hint="Add the closing `\"\"\"`.",
        ),
      )
  }
}
