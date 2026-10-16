///|
/// The version of smithy-syntax, the same as `version` in `moon.mod`.
pub fn version() -> String {
  "0.1.0"
}

///|
/// Spans (UTF-16 unit offsets), positions and source text.
pub using @span {
  type Span,
  type Offset,
  type Length,
  type Line,
  type Column,
  type Position,
  type SourceText,
}

///|
/// Diagnostics: severity, labels and the problem record.
pub using @diagnostic {type Severity, type Label, type Diagnostic}

///|
/// The one-line description of a diagnostic code, or `None`.
pub fn diagnostic_description(code : String) -> String? {
  @diagnostic.description(code)
}

///|
/// The scanner: tokens, trivia and lexical errors.
pub using @scanner {
  type TokenStream,
  type Token,
  type TokenKind,
  type Trivia,
  type Comment,
  type CommentKind,
  type Piece,
  type Step,
}

///|
/// Scan `source` into tokens with trivia. Lossless: `to_source()` is the text.
pub fn tokenize(source : SourceText) -> TokenStream {
  @scanner.tokenize(source)
}

///|
/// The AST.
pub using @ast {
  type IdlFile,
  type ControlStatement,
  type MetadataStatement,
  type NamespaceStatement,
  type UseStatement,
  type Statement,
  type ShapeStatement,
  type ApplyStatement,
  type Shape,
  type ShapeKind,
  type SimpleType,
  type EnumType,
  type AggregateType,
  type EntityType,
  type Mixins,
  type Trait,
  type TraitBody,
  type Member,
  type MemberTarget,
  type EnumMember,
  type InlineShape,
  type OperationTarget,
  type OperationProperty,
  type NodeValue,
  type NodeKvp,
  type NumberLiteral,
  type NumberValue,
  type Keyword,
  type ShapeId,
  type DocComment,
  type Node,
}

///|
/// The CST: every token grouped per statement.
pub using @cst {type IdlCst, type StatementCst, type StatementKind}

///|
/// The parser's result, version, recursion depth and error.
pub using @parser {type ParseResult, type ParseError, type Version, type Depth}

///|
/// Parse a source text with recovery per statement.
pub fn parse(source : SourceText) -> ParseResult {
  @parser.parse(source)
}

///|
/// Parse Smithy IDL text. `name` is shown in rendered diagnostics.
///
/// ```mbt check
/// test {
///   let r = @syntax.parse_idl(
///     (
///       #|$version: "2"
///       #|namespace com.foo
///       #|
///       #|string Name
///       #|
///     ),
///     name="a.smithy",
///   )
///   inspect(r.has_errors(), content="false")
/// }
/// ```
pub fn parse_idl(text : String, name? : String) -> ParseResult {
  @parser.parse(@span.SourceText::new(text, name?))
}

///|
/// Render one diagnostic as a single line, for editors (`path:line:col:
/// severity[code]: message`).
pub fn render_short(d : Diagnostic, source : SourceText) -> String {
  @report.render_short(d, source)
}

///|
/// Render one diagnostic without colour, as the Elm/Rust-style layout.
pub fn render_plain(d : Diagnostic, source : SourceText) -> String {
  @report.render_plain(d, source)
}

///|
/// Render one diagnostic for a terminal, with ANSI colour by default.
pub fn render_terminal(
  d : Diagnostic,
  source : SourceText,
  color~ : Bool = true,
) -> String {
  @report.render_terminal(d, source, color~)
}

///|
/// Render into any core `Logger`, for callers with their own sink.
pub fn render_terminal_to(
  d : Diagnostic,
  source : SourceText,
  logger : &Logger,
  color~ : Bool = true,
) -> Unit {
  @report.render_terminal_to(d, source, logger, color~)
}

///|
/// Render every diagnostic in order, ending with an error/warning count.
pub fn render_all(
  ds : ArrayView[Diagnostic],
  source : SourceText,
  color~ : Bool = true,
) -> String {
  @report.render_all(ds, source, color~)
}
