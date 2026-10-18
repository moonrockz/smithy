///|
/// A half-open range of UTF-16 offsets in the original expression.
pub(all) struct Span {
  start : Int32
  end : Int32
} derive(Eq, Debug)

///|
pub(all) enum ErrorCode {
  Syntax
  InvalidType
  InvalidValue
  InvalidArity
  UnknownFunction
} derive(Eq, Debug)

///|
pub fn ErrorCode::to_string(self : ErrorCode) -> String {
  match self {
    Syntax => "syntax"
    InvalidType => "invalid-type"
    InvalidValue => "invalid-value"
    InvalidArity => "invalid-arity"
    UnknownFunction => "unknown-function"
  }
}

///|
pub(all) struct Diagnostic {
  code : ErrorCode
  message : String
  span : Span
} derive(Eq, Debug)

///|
/// One-based line and UTF-16 column in the supplied expression source.
pub fn Diagnostic::line_column(
  self : Diagnostic,
  source : String,
) -> (Int32, Int32) {
  let mut line = 1
  let mut column = 1
  for i in 0..<self.span.start.min(source.length()).max(0) {
    let c = source.code_unit_at(i)
    if c == 13 {
      line += 1
      column = 1
    } else if c == 10 {
      if i == 0 || source.code_unit_at(i - 1) != 13 {
        line += 1
      }
      column = 1
    } else {
      column += 1
    }
  }
  (line, column)
}

///|
pub(all) suberror JmespathError {
  JmespathError(Diagnostic)
} derive(Eq, Debug)

///|
pub(all) enum Operator {
  Pipe
  Or
  And
  Equal
  NotEqual
  Less
  LessEqual
  Greater
  GreaterEqual
} derive(Eq, Debug)

///|
pub(all) struct Node {
  kind : NodeKind
  span : Span
} derive(Eq, Debug)

///|
/// Projections retain their input and per-element expression separately.
/// ExpressionRef nodes represent function arguments such as sort_by(items, &name).
pub(all) enum NodeKind {
  Identity
  Field(String)
  Literal(Json)
  Subexpression(Node, Node)
  Index(Node, Int32)
  Slice(Node, Int32?, Int32?, Int32?)
  Projection(Node, Node)
  ObjectProjection(Node, Node)
  Flatten(Node)
  Filter(Node, Node, Node)
  MultiList(Array[Node])
  MultiHash(Array[(String, Node)])
  Function(String, Array[Node])
  ExpressionRef(Node)
  Binary(Operator, Node, Node)
  Not(Node)
} derive(Eq, Debug)

///|
/// A reusable parsed expression. The AST is public for downstream analyzers.
pub(all) struct Expression {
  source : String
  root : Node
} derive(Eq, Debug)

///|
fn node(kind : NodeKind, start : Int32, end : Int32) -> Node {
  { kind, span: { start, end, }, }
}

///|
fn problem(
  code : ErrorCode,
  span : Span,
  message : String,
) -> Unit raise JmespathError {
  raise JmespathError({ code, span, message, })
}
