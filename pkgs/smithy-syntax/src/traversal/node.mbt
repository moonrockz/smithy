///|
/// A read-only reference to one node of a parse result. Each case holds the
/// AST value it points to (nothing is copied). Generic code uses `category`,
/// `kind`, `span`, `children` and `field`; typed code matches the cases.
///
/// Kinds and field names follow the Smithy JSON AST where it has a name (a
/// shape's kind is its `type`, a member has a `target`), and the IDL grammar
/// for the rest. `(category, kind)` identifies a node type.
///
/// The file node also holds the comments that the AST does not keep: every
/// `//` comment and every `///` comment that documents nothing.
///
/// ```mbt check
/// test {
///   let r = @parser.parse_text(
///     (
///       #|$version: "2"
///       #|namespace a
///       #|
///       #|string Name
///       #|
///     ),
///   )
///   let root = @traversal.NodeRef::of_result(r).unwrap()
///   inspect("\{root.category()}/\{root.kind()}", content="file/file")
///   guard root is File(file, _) else { fail("not a file") }
///   inspect(file.statements.length(), content="1")
/// }
/// ```
pub(all) enum NodeRef {
  File(@ast.IdlFile, ArrayView[@scanner.Comment])
  Control(@ast.ControlStatement)
  Metadata(@ast.MetadataStatement)
  Namespace(@ast.NamespaceStatement)
  Use(@ast.UseStatement)
  Shape(@ast.ShapeStatement)
  Apply(@ast.ApplyStatement)
  Inline(@ast.InlineShape)
  Mixins(@ast.Mixins)
  Member(@ast.Member)
  EnumMember(@ast.EnumMember)
  Property(@ast.OperationProperty)
  Trait(@ast.Trait)
  Value(@ast.NodeValue)
  Entry(@ast.NodeKvp)
  ShapeIdRef(@ast.Node[@ast.ShapeId])
  Name(@ast.Node[String])
  Doc(@ast.DocComment)
  Comment(@scanner.Comment)
} derive(Eq, Debug)

///|
/// The file node of `result`, or `None` when the parser read no AST. The
/// comments come from the CST trivia, in source order, without the doc
/// comments that the AST attaches to a shape, member or inline shape.
pub fn NodeRef::of_result(result : @parser.ParseResult) -> NodeRef? {
  guard result.ast is Some(file) else { return None }
  let attached : Set[@span.Span] = Set([])
  fn attach(docs : ArrayView[@ast.DocComment]) {
    for d in docs {
      attached.add(d.span)
    }
  }

  for s in file.statements {
    guard s is Shape(st) else { continue }
    attach(st.docs)
    match st.shape {
      Enum(members~, ..) =>
        for m in members {
          attach(m.docs)
        }
      Aggregate(members~, ..) =>
        for m in members {
          attach(m.docs)
        }
      Operation(properties~, ..) =>
        for p in properties {
          if p is (Input(Inline(i), _) | Output(Inline(i), _)) {
            attach(i.docs)
            for m in i.members {
              attach(m.docs)
            }
          }
        }
      _ => ()
    }
  }
  let comments : Array[@scanner.Comment] = []
  fn gather(trivia : ArrayView[@scanner.Trivia]) {
    for t in trivia {
      if t is Comment(c) && !(c.kind == Doc && attached.contains(c.span)) {
        comments.push(c)
      }
    }
  }

  gather(result.cst.trivia)
  for token in result.cst.tokens {
    gather(token.trivia_before)
    gather(token.trivia_after)
  }
  Some(File(file, comments[:]))
}

///|
/// The node's category: `file`, `control`, `metadata`, `namespace`, `use`,
/// `shape`, `mixins`, `member`, `operation_property`, `trait`, `value`,
/// `entry`, `shape_id`, `name`, `doc` or `comment`.
pub fn NodeRef::category(self : NodeRef) -> String {
  match self {
    File(_, _) => "file"
    Control(_) => "control"
    Metadata(_) => "metadata"
    Namespace(_) => "namespace"
    Use(_) => "use"
    Shape(_) | Apply(_) | Inline(_) => "shape"
    Mixins(_) => "mixins"
    Member(_) | EnumMember(_) => "member"
    Property(_) => "operation_property"
    Trait(_) => "trait"
    Value(_) => "value"
    Entry(_) => "entry"
    ShapeIdRef(_) => "shape_id"
    Name(_) => "name"
    Doc(_) => "doc"
    Comment(_) => "comment"
  }
}

///|
/// The JSON AST `type` of a shape: its IDL keyword.
fn shape_kind(shape : @ast.Shape) -> String {
  match shape {
    Simple(kind~, ..) => kind.keyword()
    Enum(kind=Enum, ..) => "enum"
    Enum(kind=IntEnum, ..) => "intEnum"
    Aggregate(kind=List, ..) => "list"
    Aggregate(kind=Map, ..) => "map"
    Aggregate(kind=Union, ..) => "union"
    Aggregate(kind=Structure, ..) => "structure"
    Aggregate(kind=Set, ..) => "set"
    Entity(kind=Service, ..) => "service"
    Entity(kind=Resource, ..) => "resource"
    Operation(..) => "operation"
  }
}

///|
/// The node's kind within its category. A shape's kind is its JSON AST
/// `type` (`structure`, `intEnum`, `bigDecimal`, …, or `apply` and
/// `inline`); a value's kind is its JSON node type (`boolean` for `true` and
/// `false`), or `textBlock` and `shapeId`.
pub fn NodeRef::kind(self : NodeRef) -> String {
  match self {
    Shape(s) => shape_kind(s.shape)
    Apply(_) => "apply"
    Inline(_) => "inline"
    Member(_) => "member"
    EnumMember(_) => "enumMember"
    Property(Input(_, _)) => "input"
    Property(Output(_, _)) => "output"
    Property(Errors(_, _)) => "errors"
    Value(Array(_, _)) => "array"
    Value(Object(_, _)) => "object"
    Value(Number(_, _)) => "number"
    Value(Keyword(True, _)) | Value(Keyword(False, _)) => "boolean"
    Value(Keyword(Null, _)) => "null"
    Value(String(_, _)) => "string"
    Value(TextBlock(_, _)) => "textBlock"
    Value(ShapeId(_, _)) => "shapeId"
    Comment(c) =>
      match c.kind {
        Line => "line"
        Doc => "doc"
      }
    _ => self.category()
  }
}

///|
/// `span` widened to start at the first doc comment when that comes first.
fn with_docs(
  span : @span.Span,
  docs : ArrayView[@ast.DocComment],
) -> @span.Span {
  if docs.length() > 0 && docs[0].span.start < span.start {
    docs[0].span.start.to(span.end())
  } else {
    span
  }
}

///|
/// The node's source span, widened over what the AST span leaves out, so a
/// node's span covers all of its children. Doc comments are trivia, so the
/// parser's span of a shape, member, enum member or inline shape starts
/// after them; here it starts at the first doc comment. An operation
/// property covers the docs of its inline shape, and the file covers every
/// comment. Every other node has its AST span.
pub fn NodeRef::span(self : NodeRef) -> @span.Span {
  match self {
    File(f, comments) => {
      let mut s = f.span
      for c in comments {
        s = s.join(c.span)
      }
      s
    }
    Control(c) => c.span
    Metadata(m) => m.span
    Namespace(n) => n.span
    Use(u) => u.span
    Shape(s) => with_docs(s.span, s.docs)
    Apply(a) => a.span
    Inline(i) => with_docs(i.span, i.docs)
    Mixins(m) => m.span
    Member(m) => with_docs(m.span, m.docs)
    EnumMember(m) => with_docs(m.span, m.docs)
    Property(Input(Inline(i), s)) | Property(Output(Inline(i), s)) =>
      with_docs(s, i.docs)
    Property(Input(_, s)) | Property(Output(_, s)) | Property(Errors(_, s)) => s
    Trait(t) => t.span
    Value(v) => v.span()
    Entry(e) => e.span
    ShapeIdRef(n) => n.span
    Name(n) => n.span
    Doc(d) => d.span
    Comment(c) => c.span
  }
}
