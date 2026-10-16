///|
/// The token kinds, the reference's `IdlToken` without its whitespace
/// kinds (those are `Trivia`) and without `EOF`. Keywords are identifiers:
/// Smithy keywords are contextual and the parser recognizes them.
pub(all) enum TokenKind {
  Identifier
  Number
  String
  TextBlock
  At
  Colon
  Walrus
  Equal
  Dot
  Pound
  Dollar
  LBrace
  RBrace
  LBracket
  RBracket
  LParen
  RParen
  /// Text a lexical error covers; the diagnostic is in the stream.
  Error
} derive(Eq, Debug, Hash)

///|
/// `//` or `///`.
pub(all) enum CommentKind {
  Line
  Doc
} derive(Eq, Debug, Hash)

///|
/// A comment. `span` covers the slashes and the text up to the line break
/// (not included); `text` is what follows the slashes.
pub(all) struct Comment {
  kind : CommentKind
  text : String
  span : @span.Span
} derive(Eq, Debug)

///|
/// Text between tokens. The specification treats a comma as whitespace, so
/// it is trivia here.
pub(all) enum Trivia {
  Whitespace(String, @span.Span)
  Newline(String, @span.Span)
  Comma(@span.Span)
  Comment(Comment)
} derive(Eq, Debug)

///|
/// The source text of the trivia.
pub fn Trivia::text(self : Trivia) -> String {
  match self {
    Whitespace(text, _) | Newline(text, _) => text
    Comma(_) => ","
    Comment(c) => (if c.kind == Doc { "///" } else { "//" }) + c.text
  }
}

///|
/// The span the trivia covers.
pub fn Trivia::span(self : Trivia) -> @span.Span {
  match self {
    Whitespace(_, s) | Newline(_, s) | Comma(s) => s
    Comment(c) => c.span
  }
}

///|
/// Whether this trivia is a line break.
pub fn Trivia::is_newline(self : Trivia) -> Bool {
  self is Newline(_, _)
}

///|
/// Whether this trivia is a comment.
pub fn Trivia::is_comment(self : Trivia) -> Bool {
  self is Comment(_)
}

///|
/// A token with the trivia around it. Trivia after a token up to and
/// including the first line break is its `trivia_after`; everything else
/// is the next token's `trivia_before`.
pub(all) struct Token {
  kind : TokenKind
  lexeme : String
  span : @span.Span
  trivia_before : ArrayView[Trivia]
  trivia_after : ArrayView[Trivia]
} derive(Eq, Debug)

///|
/// `trivia_before`, the lexeme and `trivia_after`, as in the source.
pub fn Token::to_source(self : Token) -> String {
  let sb = StringBuilder()
  for t in self.trivia_before {
    sb.write_string(t.text())
  }
  sb.write_string(self.lexeme)
  for t in self.trivia_after {
    sb.write_string(t.text())
  }
  sb.to_string()
}

///|
/// The result of a scan. `trivia` is the trivia of a text with no tokens,
/// and empty otherwise. `diagnostics` are the lexical problems in order.
pub(all) struct TokenStream {
  tokens : ArrayView[Token]
  trivia : ArrayView[Trivia]
  diagnostics : ArrayView[@diagnostic.Diagnostic]
} derive(Eq, Debug)

///|
/// The scanned text, byte for byte.
pub fn TokenStream::to_source(self : TokenStream) -> String {
  let sb = StringBuilder()
  for t in self.trivia {
    sb.write_string(t.text())
  }
  for token in self.tokens {
    sb.write_string(token.to_source())
  }
  sb.to_string()
}

///|
/// Whether any diagnostic has severity `Error`.
pub fn TokenStream::has_errors(self : TokenStream) -> Bool {
  self.diagnostics.iter().any(d => d.is_error())
}

///|
/// What one scanning step produces, in source order.
pub(all) enum Piece {
  Tok(TokenKind, String, @span.Span)
  Triv(Trivia)
} derive(Eq, Debug)

///|
/// One step of the scan: the piece read at an offset, where the next step
/// starts, and the lexical problems found in the piece (several for a
/// string with several bad escapes).
pub(all) struct Step {
  piece : Piece
  end : @span.Offset
  diagnostics : ArrayView[@diagnostic.Diagnostic]
} derive(Eq, Debug)
