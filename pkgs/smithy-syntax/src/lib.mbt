///|
/// The version of smithy-syntax, maintained from the root `moon.mod` by
/// `scripts/versions.mbtx set` and checked by `validate:versions`.
pub fn version() -> String {
  "0.2.0"
}

///|
/// Typed Smithy JSON AST records. The IDL AST and JSON AST are separate
/// representations; converting between them requires the semantic loader.
pub using @json_ast {
  type JsonAst,
  type JsonShape,
  type JsonShapeKind,
  type JsonReference,
  type JsonMember,
  type JsonOperation,
  type JsonService,
  type JsonResource,
}

///|
/// Parse a Smithy JSON AST document from text.
pub fn parse_json_ast(text : String) -> JsonAst raise {
  @json_ast.parse(text)
}

///|
/// Decode a Smithy JSON AST value, with JSON Pointer paths on errors.
pub fn decode_json_ast(value : Json) -> JsonAst raise @json.JsonDecodeError {
  @json_ast.decode(value)
}

///|
/// Encode a typed Smithy JSON AST document.
pub fn encode_json_ast(document : JsonAst) -> Json {
  @json_ast.encode(document)
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
/// The parser's result and declared version.
pub using @parser {type ParseResult, type Version}

///|
/// The traversal: the node model, the cursor, the tree and the event types.
pub using @traversal {
  type NodeRef,
  type Control,
  type PathStep,
  type NodePath,
  type EnterEvent,
  type LeaveEvent,
  type Event,
  type EventReader,
  type Tree,
  type TreeCursor,
  trait EventSource,
  trait Handler,
  trait Visitor,
}

///|
/// Visit `root` and every node below it in pre-order; see `@traversal.walk`.
pub fn walk(
  root : NodeRef,
  enter : (NodeRef) -> Control,
  leave~ : (NodeRef) -> Unit = _ => (),
) -> Unit {
  @traversal.walk(root, enter, leave~)
}

///|
/// Thread an accumulator through a walk; see `@traversal.fold`.
pub fn[A] fold(
  root : NodeRef,
  init : A,
  enter : (A, NodeRef) -> (A, Control),
  leave~ : (A, NodeRef) -> A = (a, _) => a,
) -> A {
  @traversal.fold(root, init, enter, leave~)
}

///|
/// Reduce `root` bottom up; see `@traversal.reduce`.
pub fn[R] reduce(root : NodeRef, f : (NodeRef, ArrayView[R]) -> R) -> R {
  @traversal.reduce(root, f)
}

///|
/// Reduce bottom up, steered by `enter`; see `@traversal.reduce_pruned`.
pub fn[R] reduce_pruned(
  root : NodeRef,
  enter : (NodeRef) -> Control,
  f : (NodeRef, ArrayView[R]) -> R,
) -> R? {
  @traversal.reduce_pruned(root, enter, f)
}

///|
/// Call one `Visitor` method per node; see `@traversal.accept`.
pub fn[V : Visitor] accept(root : NodeRef, visitor : V) -> Unit {
  @traversal.accept(root, visitor)
}

///|
/// Drive an event source into a handler; see `@traversal.push_events`.
pub fn[S : EventSource, H : Handler] push_events(
  source : S,
  handler : H,
) -> Unit {
  @traversal.push_events(source, handler)
}

///|
/// Every node type: (category, kind, fields); see `@traversal.kind_table`.
pub fn kind_table() -> Array[(String, String, Array[String])] {
  @traversal.kind_table()
}

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

///|
/// Every registered diagnostic code, in table order.
pub fn codes() -> ArrayView[String] {
  @diagnostic.codes()
}

///|
/// Parse an existing lossless token stream, with recovery per statement.
pub fn parse_tokens(stream : TokenStream) -> ParseResult {
  @parser.parse_tokens(stream)
}

///|
/// Render every diagnostic and the summary into a caller's sink.
pub fn render_all_to(
  ds : ArrayView[Diagnostic],
  source : SourceText,
  logger : &Logger,
  color~ : Bool = true,
) -> Unit {
  @report.render_all_to(ds, source, logger, color~)
}
