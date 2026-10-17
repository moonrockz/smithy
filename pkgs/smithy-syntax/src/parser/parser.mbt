///|
/// A construct the parser is inside, for titles and secondary labels.
priv struct Context {
  what : String
  span : @span.Span
}

///|
/// The parser state over a token stream. `Error` tokens are holes: `peek`
/// skips them (the scanner already reported them).
priv struct Parser {
  tokens : ArrayView[@scanner.Token]
  text_end : @span.Offset
  /// The array index of the next token; an index, so an `Int`.
  mut pos : Int32
  mut depth : Depth
  contexts : Array[Context]
  diagnostics : Array[@diagnostic.Diagnostic]
  /// Every doc comment in order, and the first one not yet taken.
  doc_comments : Array[@ast.DocComment]
  mut doc_head : Int32
  mut version : Version?
  /// Set when a recovery before the namespace may have eaten the
  /// `$version` statement: the file *might* have declared
  /// `$version: "2"`, we just couldn't read it, so `require_v2` must not
  /// report 1.0-only gating errors on the strength of a version we
  /// don't actually know.
  mut version_unknown : Bool
  /// Set once a construct the file's version does not allow has been
  /// reported (`require_v2`, or `set` in 2.0). A file reports the version
  /// mismatch once, at the first such construct: one mistyped `$version`
  /// would otherwise flag every such construct in the file.
  mut version_reported : Bool
  /// The token index of the current statement's shape keyword, once its
  /// leading traits are read; the statement's first index before that.
  /// Recovery scans past it: the failed statement's own keyword is not
  /// a new statement, and resuming there would report the failure twice.
  mut keyword_index : Int32
}

///|
fn Parser::new(stream : @scanner.TokenStream) -> Parser {
  let doc_comments : Array[@ast.DocComment] = []
  fn gather(trivia : ArrayView[@scanner.Trivia]) {
    for t in trivia {
      if t is Comment(c) && c.kind == Doc {
        doc_comments.push({ text: c.text, span: c.span, })
      }
    }
  }

  gather(stream.trivia)
  for token in stream.tokens {
    gather(token.trivia_before)
    // A comment after a token on the same line is an ordinary comment,
    // even when it starts with three slashes.
    let mut next_line = false
    for trivia in token.trivia_after {
      if next_line && trivia is Comment(c) && c.kind == Doc {
        doc_comments.push({ text: c.text, span: c.span, })
      }
      if trivia.is_newline() {
        next_line = true
      }
    }
  }
  let text_end = @span.Offset::zero().advance(
    @span.Length::of_string(stream.to_source()),
  )
  let p = {
    tokens: stream.tokens,
    text_end,
    pos: 0,
    depth: Depth::zero(),
    contexts: [],
    diagnostics: [],
    doc_comments,
    doc_head: 0,
    version: None,
    version_unknown: false,
    version_reported: false,
    keyword_index: 0,
  }
  p.skip_holes()
  p
}

///|
fn Parser::skip_holes(self : Parser) -> Unit {
  while self.pos < self.tokens.length() && self.tokens[self.pos].kind == Error {
    self.pos += 1
  }
}

///|
fn Parser::peek(self : Parser) -> @scanner.Token? {
  if self.pos < self.tokens.length() {
    Some(self.tokens[self.pos])
  } else {
    None
  }
}

///|
/// The token after `peek()`, holes skipped.
fn Parser::peek1(self : Parser) -> @scanner.Token? {
  let mut i = self.pos + 1
  while i < self.tokens.length() && self.tokens[i].kind == Error {
    i += 1
  }
  if i < self.tokens.length() {
    Some(self.tokens[i])
  } else {
    None
  }
}

///|
fn Parser::at_end(self : Parser) -> Bool {
  self.pos >= self.tokens.length()
}

///|
fn Parser::advance(self : Parser) -> @scanner.Token? {
  let t = self.peek()
  if t is Some(_) {
    // Documentation not claimed before consuming its next token belongs to
    // an expression or another construct that cannot accept documentation.
    self.take_docs_before(t.unwrap().span.start) |> ignore
    self.pos += 1
    self.skip_holes()
  }
  t
}

///|
/// Whether `peek()` is the identifier `word`.
fn Parser::at_keyword(self : Parser, word : String) -> Bool {
  self.peek() is Some(t) && t.kind == Identifier && t.lexeme == word
}

///|
fn Parser::at_kind(self : Parser, kind : @scanner.TokenKind) -> Bool {
  self.peek() is Some(t) && t.kind == kind
}

///|
/// Whether no trivia separates `peek()` from the token before it.
fn Parser::adjacent(self : Parser) -> Bool {
  guard self.pos > 0 && self.pos < self.tokens.length() else { return false }
  let prev = self.tokens[self.pos - 1]
  let cur = self.tokens[self.pos]
  prev.trivia_after.length() == 0 &&
  cur.trivia_before.length() == 0 &&
  prev.span.end() == cur.span.start
}

///|
/// Where an error with no better place goes: the current token, or the end
/// of the text.
fn Parser::here(self : Parser) -> @span.Span {
  match self.peek() {
    Some(t) => t.span
    None => self.text_end.to(self.text_end)
  }
}

///|
/// Where "I was expecting X right here" goes when X is missing at the
/// true end of the file: right after the last real token, not the raw
/// end-of-file offset. The two read the same when the file has no
/// trailing line break; when it does, this is the reference's own
/// convention for "a value/identifier is missing here" ("here" being
/// where the last thing I read ended), as opposed to `here()`'s "the
/// file ended while I was still reading an unclosed block", which the
/// reference reports at the raw end-of-file offset instead.
fn Parser::here_anchored(self : Parser) -> @span.Span {
  guard self.peek() is None else { return self.here() }
  match self.tokens.last() {
    Some(t) => t.span.end().to(t.span.end())
    None => self.text_end.to(self.text_end)
  }
}

///|
/// How the current token reads in a message: "`foo`", "end of file".
fn Parser::found(self : Parser) -> String {
  match self.peek() {
    None => "the end of the file"
    Some(t) =>
      match t.kind {
        String | TextBlock => "a string"
        Number => "the number `\{t.lexeme}`"
        _ => "`\{t.lexeme}`"
      }
  }
}

///|
fn Parser::push_context(
  self : Parser,
  what : String,
  span : @span.Span,
) -> Unit {
  self.contexts.push({ what, span, })
}

///|
fn Parser::pop_context(self : Parser) -> Unit {
  ignore(self.contexts.pop())
}

///|
/// Build and raise a diagnostic. The innermost context gives a secondary
/// label ("the structure started here") and the first note. A caller that
/// raises `SM-PARSE-001` for a diagnostic whose `span` is the end-of-input
/// span (what `here()` returns once the file is exhausted) gets
/// `SM-PARSE-002` instead: that is really "unexpected end of file", not
/// "unexpected token". A `SM-PARSE-001` whose `span` points at a real
/// token is left alone even when that token happens to be the last one in
/// the file.
fn[T] Parser::fail(
  self : Parser,
  code : String,
  title : String,
  message : String,
  span : @span.Span,
  notes? : Array[String],
  hint? : String,
  example? : String,
  labels? : Array[@diagnostic.Label],
) -> T raise ParseError {
  let code = if self.peek() is None &&
    code == "SM-PARSE-001" &&
    span == self.here() {
    "SM-PARSE-002"
  } else {
    code
  }
  let base = @diagnostic.Diagnostic::new(
    code~,
    severity=Error,
    title~,
    message~,
    span~,
    labels?,
    notes?,
    hint?,
    example?,
  )
  raise ParseError(
    match self.contexts.last() {
      Some(c) =>
        base.with_context(
          { span: c.span, text: "\{c.what} started here", },
          "I was parsing \{c.what} when I got stuck.",
        )
      None => base
    },
  )
}

///|
/// Record a diagnostic without raising (warnings, and errors the parser
/// can continue past).
fn Parser::report(
  self : Parser,
  code : String,
  severity : @diagnostic.Severity,
  title : String,
  message : String,
  span : @span.Span,
  notes? : Array[String],
  hint? : String,
) -> Unit {
  self.diagnostics.push(
    @diagnostic.Diagnostic::new(
      code~,
      severity~,
      title~,
      message~,
      span~,
      notes?,
      hint?,
    ),
  )
}

///|
/// `peek()` must have `kind`; `what` names it in the error ("a `{`").
fn Parser::expect_kind(
  self : Parser,
  kind : @scanner.TokenKind,
  what : String,
) -> @scanner.Token raise ParseError {
  match self.peek() {
    Some(t) if t.kind == kind => {
      ignore(self.advance())
      t
    }
    _ =>
      self.fail(
        "SM-PARSE-001",
        "UNEXPECTED TOKEN",
        "I was expecting \{what} but found \{self.found()}",
        self.here(),
      )
  }
}

///|
fn Parser::expect_identifier(
  self : Parser,
  what : String,
) -> @ast.Node[String] raise ParseError {
  let t = self.expect_kind(Identifier, what)
  @ast.Node::new(t.lexeme, t.span)
}

///|
/// Whether a line break or a comment separates the token at `self.pos`
/// from the one before it (a `BR`, not just whitespace).
fn Parser::has_br_before(self : Parser) -> Bool {
  guard self.pos > 0 && self.pos < self.tokens.length() else { return false }
  let prev = self.tokens[self.pos - 1]
  let next = self.tokens[self.pos]
  prev.trivia_after.iter().any(t => t.is_newline() || t.is_comment()) ||
  next.trivia_before.iter().any(t => t.is_newline() || t.is_comment())
}

///|
/// The grammar's `SP` right after the token just consumed: unlike most
/// gaps (which accept a line break or a comment as whitespace too), a few
/// spots allow only a plain space or tab before the next token - `$key`
/// and `:` in a control statement, `metadata` and the key, `=` and the
/// value, `namespace`/`use` and what follows. A line break or a comment
/// there is the reference's own unexpected token, so the error points at
/// it, not at the next real token after it.
fn Parser::expect_sp_after(
  self : Parser,
  what : String,
) -> Unit raise ParseError {
  // At the true end of the file there is no "next real token" to be
  // misplaced; that is a missing-value error, not a misplaced one, and
  // whatever parses next already reports it.
  guard self.pos > 0 && self.peek() is Some(_) else { return }
  let prev = self.tokens[self.pos - 1]
  for t in prev.trivia_after {
    if t.is_newline() || t.is_comment() {
      self.fail(
        "SM-PARSE-001",
        "UNEXPECTED LINE BREAK",
        "I was expecting \{what} right after `\{prev.lexeme}`, on the same line, but found a line break or a comment",
        t.span(),
        hint="Move \{what} onto the same line as `\{prev.lexeme}`.",
      )
    }
  }
}

///|
/// The grammar's mandatory `SP` (or `WS`) right after the token just
/// consumed: a few spots need at least one separator, not zero
/// (`metadata"key"`, `apply Foo{...}`).
fn Parser::expect_sp_present(
  self : Parser,
  what : String,
) -> Unit raise ParseError {
  if self.adjacent() {
    self.fail(
      "SM-PARSE-001",
      "MISSING WHITESPACE",
      "I was expecting whitespace before \{what} but found \{self.found()} right after `\{self.tokens[self.pos - 1].lexeme}`",
      self.here(),
    )
  }
}

///|
/// The grammar's `BR`: after a statement there must be a line break or a
/// comment before the next token (or the end of the file).
fn Parser::expect_br(self : Parser) -> Unit raise ParseError {
  guard self.pos > 0 else { return }
  guard self.peek() is Some(next) else { return }
  if !self.has_br_before() {
    self.fail(
      "SM-PARSE-003",
      "MISSING LINE BREAK",
      "I was expecting a line break here but found \{self.found()}",
      next.span,
      notes=[
        "Each statement must end with a line break (or a comment, which ends at a line break). Commas are whitespace in Smithy, so a comma does not separate statements.",
      ],
      hint="Put `\{next.lexeme}` on its own line.",
    )
  }
}

///|
fn Parser::enter(self : Parser) -> Unit raise ParseError {
  self.depth = self.depth.deeper()
  if self.depth > max_nesting {
    self.fail(
      "SM-PARSE-010",
      "TOO MUCH NESTING",
      "this is nested more than \{max_nesting.0} levels deep",
      self.here(),
      hint="Flatten the value; nothing in Smithy needs nesting this deep.",
    )
  }
}

///|
fn Parser::leave(self : Parser) -> Unit {
  self.depth = self.depth.shallower()
}

///|
/// The pending doc comments that start before `offset`, in order.
fn Parser::take_docs_before(
  self : Parser,
  offset : @span.Offset,
) -> Array[@ast.DocComment] {
  let out = []
  while self.doc_head < self.doc_comments.length() &&
        self.doc_comments[self.doc_head].span.start < offset {
    out.push(self.doc_comments[self.doc_head])
    self.doc_head += 1
  }
  out
}

///|
/// Report every pending doc comment before `offset` as detached.
fn Parser::detach_docs_before(self : Parser, offset : @span.Offset) -> Unit {
  for d in self.take_docs_before(offset) {
    self.report(
      "SM-PARSE-009",
      Warning,
      "DETACHED DOC COMMENT",
      "this documentation comment is not followed by a shape or member",
      d.span,
      notes=[
        "A `///` comment documents the shape, member or enum member that comes right after it. Nothing here can take documentation, so I ignored it.",
      ],
      hint="Move it right before the shape it documents, or make it a `//` comment.",
    )
  }
}

///|
/// `ShapeId = RootShapeId [ShapeIdMember]`, assembled from adjacent tokens:
/// `a.b#Name$member`. A dotted name without `#` is an error.
fn Parser::parse_shape_id(
  self : Parser,
) -> @ast.Node[@ast.ShapeId] raise ParseError {
  let first = self.expect_identifier("a shape ID")
  let start = first.span.start
  let mut end = first.span.end()
  let parts = [first.value]
  let mut namespace : String? = None
  let mut name = first.value
  let mut saw_dot = false
  while self.at_kind(Dot) && self.adjacent() {
    saw_dot = true
    ignore(self.advance())
    guard self.adjacent() && self.at_kind(Identifier) else {
      self.fail(
        "SM-PARSE-005",
        "INVALID SHAPE ID",
        "I was expecting a namespace segment after `.`",
        self.here(),
        hint="A namespace looks like `com.example`, with no spaces around the dots.",
      )
    }
    let seg = self.expect_identifier("a namespace segment")
    parts.push(seg.value)
    end = seg.span.end()
  }
  if self.at_kind(Pound) && self.adjacent() {
    ignore(self.advance())
    guard self.adjacent() && self.at_kind(Identifier) else {
      self.fail(
        "SM-PARSE-005",
        "INVALID SHAPE ID",
        "I was expecting a shape name after `#`",
        self.here_anchored(),
        example="smithy.api#String",
      )
    }
    let n = self.expect_identifier("a shape name")
    namespace = Some(parts.join("."))
    name = n.value
    end = n.span.end()
  } else if saw_dot && self.at_kind(Pound) {
    // The `#` is there, just not adjacent: a space inside the ID, not a
    // missing one.
    self.fail(
      "SM-PARSE-001",
      "UNEXPECTED TOKEN",
      "a shape ID cannot contain spaces; I was expecting `#` right after `\{parts.join(".")}` with no space before it",
      self.here(),
      hint="Remove the space before `#`.",
    )
  } else if saw_dot {
    self.fail(
      "SM-PARSE-005",
      "INVALID SHAPE ID",
      "`\{parts.join(".")}` looks like a namespace, but a shape ID needs `#` and a shape name after it",
      start.to(end),
      hint="Write `\{parts.join(".")}#Name`, or just `Name` for a shape in this namespace.",
    )
  }
  let mut member : String? = None
  if self.at_kind(Dollar) && self.adjacent() {
    ignore(self.advance())
    guard self.adjacent() && self.at_kind(Identifier) else {
      self.fail(
        "SM-PARSE-005",
        "INVALID SHAPE ID",
        "I was expecting a member name after `$`",
        self.here(),
        example="Foo$bar",
      )
    }
    let m = self.expect_identifier("a member name")
    member = Some(m.value)
    end = m.span.end()
  }
  @ast.Node::new({ namespace, name, member, }, start.to(end))
}

///|
/// End of the last consumed syntax token. `advance` can also skip scanner
/// holes, whose spans must not become part of the construct just parsed.
fn Parser::previous_end(self : Parser) -> @span.Offset {
  let mut i = self.pos - 1
  while i >= 0 {
    if self.tokens[i].kind != Error {
      return self.tokens[i].span.end()
    }
    i -= 1
  }
  @span.Offset::zero()
}
