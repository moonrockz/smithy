///|
/// The code unit at `at` as a `Char`, or `None` past the end. A unit of a
/// surrogate pair comes back as itself; the scanner only compares against
/// ASCII, and lexemes are sliced from the text, so no character is lost.
fn unit_at(text : String, at : @span.Offset) -> Char? {
  if at.0 >= text.length() {
    None
  } else {
    Some(text.code_unit_at(at.0).to_int().unsafe_to_char())
  }
}

///|
/// The unit `k` places after `at`.
fn peek(text : String, at : @span.Offset, k : Int32) -> Char? {
  unit_at(text, @span.Offset::new(at.0 + k).unwrap_or(at))
}

///|
fn is_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_ident_char(c : Char) -> Bool {
  is_alpha(c) || is_digit(c) || c == '_'
}

///|
/// The offset of the first unit at or after `from` that fails `pred` (or
/// the end of the text).
fn skip_while(
  text : String,
  from : @span.Offset,
  pred : (Char) -> Bool,
) -> @span.Offset {
  let mut at = from
  while unit_at(text, at) is Some(c) && pred(c) {
    at = at.next()
  }
  at
}

///|
fn slice(text : String, from : @span.Offset, to : @span.Offset) -> String {
  text.unsafe_substring(start=from.0, end=to.0)
}

///|
/// A `Step` for a token from `at` to `end`.
fn token_step(
  kind : TokenKind,
  text : String,
  at : @span.Offset,
  end : @span.Offset,
) -> Step {
  {
    piece: Tok(kind, slice(text, at, end), at.to(end)),
    end,
    diagnostics: [][:],
  }
}

///|
fn trivia_step(t : Trivia, end : @span.Offset) -> Step {
  { piece: Triv(t), end, diagnostics: [][:], }
}

///|
/// A `Step` for an `Error` token with one diagnostic.
fn error_step(
  text : String,
  at : @span.Offset,
  end : @span.Offset,
  d : @diagnostic.Diagnostic,
) -> Step {
  {
    piece: Tok(Error, slice(text, at, end), at.to(end)),
    end,
    diagnostics: [d][:],
  }
}

///|
fn lexical(
  code : String,
  title : String,
  message : String,
  span : @span.Span,
  notes? : Array[String],
  hint? : String,
) -> @diagnostic.Diagnostic {
  @diagnostic.Diagnostic::new(
    code~,
    severity=Error,
    title~,
    message~,
    span~,
    notes?,
    hint?,
  )
}
