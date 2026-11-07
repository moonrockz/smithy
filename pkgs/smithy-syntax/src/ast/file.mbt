///|
/// `$key: value`.
#derive(Eq, Debug)
pub(all) struct ControlStatement {
  key : Node[String]
  value : NodeValue
  span : @span.Span
}

///|
/// `metadata key = value`.
#derive(Eq, Debug)
pub(all) struct MetadataStatement {
  key : Node[String]
  value : NodeValue
  span : @span.Span
}

///|
/// `namespace a.b.c`.
#derive(Eq, Debug)
pub(all) struct NamespaceStatement {
  namespace : Node[String]
  span : @span.Span
}

///|
/// `use a.b#Name`.
#derive(Eq, Debug)
pub(all) struct UseStatement {
  id : Node[ShapeId]
  span : @span.Span
}

///|
/// Doc comments and traits, then the shape.
#derive(Eq, Debug)
pub(all) struct ShapeStatement {
  docs : ArrayView[DocComment]
  traits : ArrayView[Trait]
  shape : Shape
  span : @span.Span
}

///|
/// `apply Target @trait` or `apply Target { @a @b }`.
#derive(Eq, Debug)
pub(all) struct ApplyStatement {
  target : Node[ShapeId]
  traits : ArrayView[Trait]
  block : Bool
  span : @span.Span
}

///|
/// A shape or apply statement in the shape section.
#derive(Eq, Debug)
pub(all) enum Statement {
  Shape(ShapeStatement)
  Apply(ApplyStatement)
}

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
#derive(Eq, Debug)
pub(all) struct IdlFile {
  control : ArrayView[ControlStatement]
  metadata : ArrayView[MetadataStatement]
  namespace : NamespaceStatement?
  uses : ArrayView[UseStatement]
  statements : ArrayView[Statement]
  span : @span.Span
}

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
