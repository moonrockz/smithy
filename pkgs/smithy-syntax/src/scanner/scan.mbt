///|
/// `IdentifierStart = (1*"_" (ALPHA / DIGIT)) / ALPHA`.
fn at_identifier_start(text : String, at : @span.Offset) -> Bool {
  match unit_at(text, at) {
    Some(c) if is_alpha(c) => true
    Some('_') => {
      let after = skip_while(text, at, c => c == '_')
      match unit_at(text, after) {
        Some(c) => is_alpha(c) || is_digit(c)
        None => false
      }
    }
    _ => false
  }
}

///|
fn scan_identifier(text : String, at : @span.Offset) -> Step {
  token_step(Identifier, text, at, skip_while(text, at, is_ident_char))
}

///|
/// Spaces and tabs; a lone `\r` too, since it is not a line break.
fn scan_whitespace(text : String, at : @span.Offset) -> Step {
  let mut end = at
  while unit_at(text, end) is Some(' ' | '\t' | '\r') {
    if unit_at(text, end) == Some('\r') &&
      peek(text, end, @span.Length::new(1).unwrap()) == Some('\n') {
      break
    }
    end = end.next()
  }
  trivia_step(Whitespace(slice(text, at, end), at.to(end)), end)
}

///|
fn scan_newline(text : String, at : @span.Offset) -> Step {
  let end = if unit_at(text, at) == Some('\r') {
    at.next().next()
  } else {
    at.next()
  }
  trivia_step(Newline(slice(text, at, end), at.to(end)), end)
}

///|
/// `//` or `///` to the end of the line (the line break is not included).
fn scan_comment(text : String, at : @span.Offset) -> Step {
  let kind = if peek(text, at, @span.Length::new(2).unwrap()) == Some('/') {
    Doc
  } else {
    Line
  }
  let text_start = at.advance(
    if kind == Doc {
      @span.Length::new(3).unwrap()
    } else {
      @span.Length::new(2).unwrap()
    },
  )
  let mut end = text_start
  while unit_at(text, end) is Some(c) && c != '\n' {
    if c == '\r' && peek(text, end, @span.Length::new(1).unwrap()) == Some('\n') {
      break
    }
    end = end.next()
  }
  trivia_step(
    Comment({ kind, text: slice(text, text_start, end), span: at.to(end), }),
    end,
  )
}

///|
fn scan_single(kind : TokenKind, text : String, at : @span.Offset) -> Step {
  token_step(kind, text, at, at.next())
}

///|
/// One unexpected character (both units of a surrogate pair) as an `Error`
/// token with `SM-SCAN-001`.
fn scan_unexpected(text : String, at : @span.Offset) -> Step {
  let c = text.code_unit_at(at.0).to_int()
  let is_high = c >= 0xD800 && c <= 0xDBFF
  let low_follows = match peek(text, at, @span.Length::new(1).unwrap()) {
    Some(l) => l.to_int() >= 0xDC00 && l.to_int() <= 0xDFFF
    None => false
  }
  let end = if is_high && low_follows { at.next().next() } else { at.next() }
  let shown = slice(text, at, end)
  error_step(
    text,
    at,
    end,
    lexical(
      "SM-SCAN-001",
      "UNEXPECTED CHARACTER",
      "I don't know what to do with `\{shown}`",
      at.to(end),
      notes=[
        "I was reading tokens and found a character that cannot start one. Smithy IDL uses letters, digits, `_`, quotes, numbers and the punctuation `@ : := = . # $ { } [ ] ( ) ,`.",
      ],
    ),
  )
}

///|
/// One token or one piece of trivia at `at`, or `None` at the end of the
/// text. Pure: the same text and offset always give the same step.
pub fn scan_at(text : String, at : @span.Offset) -> Step? {
  guard unit_at(text, at) is Some(c) else { return None }
  Some(
    match c {
      '\n' => scan_newline(text, at)
      '\r' =>
        if peek(text, at, @span.Length::new(1).unwrap()) == Some('\n') {
          scan_newline(text, at)
        } else {
          scan_whitespace(text, at)
        }
      ' ' | '\t' => scan_whitespace(text, at)
      ',' => trivia_step(Comma(at.to(at.next())), at.next())
      '/' if peek(text, at, @span.Length::new(1).unwrap()) == Some('/') =>
        scan_comment(text, at)
      '@' => scan_single(At, text, at)
      ':' =>
        if peek(text, at, @span.Length::new(1).unwrap()) == Some('=') {
          token_step(Walrus, text, at, at.next().next())
        } else {
          scan_single(Colon, text, at)
        }
      '=' => scan_single(Equal, text, at)
      '.' => scan_single(Dot, text, at)
      '#' => scan_single(Pound, text, at)
      '$' => scan_single(Dollar, text, at)
      '{' => scan_single(LBrace, text, at)
      '}' => scan_single(RBrace, text, at)
      '[' => scan_single(LBracket, text, at)
      ']' => scan_single(RBracket, text, at)
      '(' => scan_single(LParen, text, at)
      ')' => scan_single(RParen, text, at)
      '"' => scan_string_or_text_block(text, at)
      '-' => scan_number(text, at)
      _ =>
        if is_digit(c) {
          scan_number(text, at)
        } else if at_identifier_start(text, at) {
          scan_identifier(text, at)
        } else {
          scan_unexpected(text, at)
        }
    },
  )
}
