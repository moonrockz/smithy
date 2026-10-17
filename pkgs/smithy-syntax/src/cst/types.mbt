///|
/// What a statement's tokens parsed as. `Skipped` is a run the parser
/// reported and skipped (recovery per statement).
pub(all) enum StatementKind {
  Control
  Metadata
  Namespace
  Use
  Shape(@ast.ShapeKind)
  Apply
  Skipped
} derive(Eq, Debug)

///|
/// `Control`, `Shape(structure)`, ... for tests and tools.
pub impl Show for StatementKind with fn output(self, logger) {
  match self {
    Control => logger.write_string("Control")
    Metadata => logger.write_string("Metadata")
    Namespace => logger.write_string("Namespace")
    Use => logger.write_string("Use")
    Shape(k) => logger.write_string("Shape(\{k})")
    Apply => logger.write_string("Apply")
    Skipped => logger.write_string("Skipped")
  }
}

///|
/// The tokens of one statement, with their trivia. `name` is the control
/// key, metadata key, namespace, used shape ID, shape name or apply
/// target; `None` for a skipped run. `span` runs from the first token's
/// start to the last token's end, trivia excluded; empty at 0 with no token.
pub(all) struct StatementCst {
  kind : StatementKind
  name : String?
  tokens : ArrayView[@scanner.Token]
  span : @span.Span
} derive(Eq, Debug)

///|
/// Group `tokens` as one statement; the span runs from the first token's start to the last token's end.
pub fn StatementCst::new(
  kind~ : StatementKind,
  name~ : String?,
  tokens~ : ArrayView[@scanner.Token],
) -> StatementCst {
  let span = if tokens.length() == 0 {
    @span.Offset::zero().to(@span.Offset::zero())
  } else {
    tokens[0].span.start.to(tokens[tokens.length() - 1].span.end())
  }
  { kind, name, tokens, span, }
}

///|
/// The text of the statement's tokens with their trivia.
pub fn StatementCst::to_source(self : StatementCst) -> String {
  let sb = StringBuilder()
  for t in self.tokens {
    sb.write_string(t.to_source())
  }
  sb.to_string()
}

///|
/// Every token of a file, grouped per statement. `statements` tile
/// `tokens` in order; `trivia` is the stream's trivia for a text with no
/// token.
pub(all) struct IdlCst {
  tokens : ArrayView[@scanner.Token]
  trivia : ArrayView[@scanner.Trivia]
  statements : ArrayView[StatementCst]
} derive(Eq, Debug)

///|
/// The CST of a scanned stream with its statements.
pub fn IdlCst::new(
  stream : @scanner.TokenStream,
  statements : Array[StatementCst],
) -> IdlCst {
  { tokens: stream.tokens, trivia: stream.trivia, statements: statements[:], }
}

///|
/// The scanned text, byte for byte.
pub fn IdlCst::to_source(self : IdlCst) -> String {
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
/// The runs the parser skipped.
pub fn IdlCst::skipped(self : IdlCst) -> Array[StatementCst] {
  self.statements.iter().filter(s => s.kind == Skipped).collect()
}
