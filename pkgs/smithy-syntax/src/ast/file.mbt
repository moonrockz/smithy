///|
/// `$key: value`.
pub(all) struct ControlStatement {
  key : Node[String]
  value : NodeValue
  span : @span.Span
} derive(Eq, Debug)

///|
/// `metadata key = value`.
pub(all) struct MetadataStatement {
  key : Node[String]
  value : NodeValue
  span : @span.Span
} derive(Eq, Debug)

///|
/// `namespace a.b.c`.
pub(all) struct NamespaceStatement {
  namespace : Node[String]
  span : @span.Span
} derive(Eq, Debug)

///|
/// `use a.b#Name`.
pub(all) struct UseStatement {
  id : Node[ShapeId]
  span : @span.Span
} derive(Eq, Debug)

///|
/// Doc comments and traits, then the shape.
pub(all) struct ShapeStatement {
  docs : ArrayView[DocComment]
  traits : ArrayView[Trait]
  shape : Shape
  span : @span.Span
} derive(Eq, Debug)

///|
/// `apply Target @trait` or `apply Target { @a @b }`.
pub(all) struct ApplyStatement {
  target : Node[ShapeId]
  traits : ArrayView[Trait]
  block : Bool
  span : @span.Span
} derive(Eq, Debug)

///|
/// A shape or apply statement in the shape section.
pub(all) enum Statement {
  Shape(ShapeStatement)
  Apply(ApplyStatement)
} derive(Eq, Debug)

///|
/// The statement's span.
pub fn Statement::span(self : Statement) -> @span.Span {
  match self {
    Shape(s) => s.span
    Apply(a) => a.span
  }
}

///|
/// One IDL file: control section, metadata section, then the shape section
/// (`namespace`, `use` statements, shape and apply statements).
pub(all) struct IdlFile {
  control : ArrayView[ControlStatement]
  metadata : ArrayView[MetadataStatement]
  namespace : NamespaceStatement?
  uses : ArrayView[UseStatement]
  statements : ArrayView[Statement]
  span : @span.Span
} derive(Eq, Debug)

///|
/// The shape statements, without the apply statements.
pub fn IdlFile::shapes(self : IdlFile) -> Array[ShapeStatement] {
  let out = []
  for s in self.statements {
    if s is Shape(sh) {
      out.push(sh)
    }
  }
  out
}

///|
/// The value of the `$key` control statement, else `None`.
pub fn IdlFile::control_value(self : IdlFile, key : String) -> NodeValue? {
  for c in self.control {
    if c.key.value == key {
      return Some(c.value)
    }
  }
  None
}
