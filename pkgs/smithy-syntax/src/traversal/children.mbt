///|
/// Whether two references point to the same node of the same parse: the AST
/// values are the same objects. Equal values from another parse of the same
/// text are other nodes. No structural comparison, so this never recurses.
fn same(a : NodeRef, b : NodeRef) -> Bool {
  match (a, b) {
    (File(x, _), File(y, _)) => physical_equal(x, y)
    (Control(x), Control(y)) => physical_equal(x, y)
    (Metadata(x), Metadata(y)) => physical_equal(x, y)
    (Namespace(x), Namespace(y)) => physical_equal(x, y)
    (Use(x), Use(y)) => physical_equal(x, y)
    (Shape(x), Shape(y)) => physical_equal(x, y)
    (Apply(x), Apply(y)) => physical_equal(x, y)
    (Inline(x), Inline(y)) => physical_equal(x, y)
    (Mixins(x), Mixins(y)) => physical_equal(x, y)
    (Member(x), Member(y)) => physical_equal(x, y)
    (EnumMember(x), EnumMember(y)) => physical_equal(x, y)
    (Property(x), Property(y)) => physical_equal(x, y)
    (Trait(x), Trait(y)) => physical_equal(x, y)
    (Value(x), Value(y)) => physical_equal(x, y)
    (Entry(x), Entry(y)) => physical_equal(x, y)
    (ShapeIdRef(x), ShapeIdRef(y)) => physical_equal(x, y)
    (Name(x), Name(y)) => physical_equal(x, y)
    (Doc(x), Doc(y)) => physical_equal(x, y)
    (Comment(x), Comment(y)) => physical_equal(x, y)
    _ => false
  }
}

///|
fn docs(xs : ArrayView[@ast.DocComment]) -> Array[NodeRef] {
  xs.iter().map(x => Doc(x)).to_array()
}

///|
fn traits(xs : ArrayView[@ast.Trait]) -> Array[NodeRef] {
  xs.iter().map(x => Trait(x)).to_array()
}

///|
fn members(xs : ArrayView[@ast.Member]) -> Array[NodeRef] {
  xs.iter().map(x => Member(x)).to_array()
}

///|
fn ids(xs : ArrayView[@ast.Node[@ast.ShapeId]]) -> Array[NodeRef] {
  xs.iter().map(x => ShapeIdRef(x)).to_array()
}

///|
fn entry_nodes(xs : ArrayView[@ast.NodeKvp]) -> Array[NodeRef] {
  xs.iter().map(x => Entry(x)).to_array()
}

///|
fn optional_id(x : @ast.Node[@ast.ShapeId]?) -> Array[NodeRef] {
  match x {
    Some(x) => [ShapeIdRef(x)]
    None => []
  }
}

///|
fn optional_value(x : @ast.NodeValue?) -> Array[NodeRef] {
  match x {
    Some(x) => [Value(x)]
    None => []
  }
}

///|
fn optional_mixins(x : @ast.Mixins?) -> Array[NodeRef] {
  match x {
    Some(x) => [Mixins(x)]
    None => []
  }
}

///|
fn shape_entries(s : @ast.ShapeStatement) -> Array[(String, Array[NodeRef])] {
  let head = [
    ("docs", docs(s.docs)),
    ("traits", traits(s.traits)),
    ("name", [Name(s.shape.name())]),
  ]
  let tail = match s.shape {
    Simple(mixins~, ..) => [("mixins", optional_mixins(mixins))]
    Enum(mixins~, members~, ..) =>
      [
        ("mixins", optional_mixins(mixins)),
        ("members", members.iter().map(m => EnumMember(m)).to_array()),
      ]
    Aggregate(for_resource~, mixins~, members=ms, ..) =>
      [
        ("for", optional_id(for_resource)),
        ("mixins", optional_mixins(mixins)),
        ("members", members(ms)),
      ]
    Entity(mixins~, body~, ..) =>
      [("mixins", optional_mixins(mixins)), ("value", [Value(body)])]
    Operation(mixins~, properties~, ..) =>
      [
        ("mixins", optional_mixins(mixins)),
        ("properties", properties.iter().map(p => Property(p)).to_array()),
      ]
  }
  head + tail
}

///|
fn operation_target(t : @ast.OperationTarget) -> NodeRef {
  match t {
    Reference(id) => ShapeIdRef(id)
    Inline(i) => Inline(i)
  }
}

///|
/// The fields of the node and the children in each, in kind-table order.
fn NodeRef::entries(self : NodeRef) -> Array[(String, Array[NodeRef])] {
  match self {
    File(f, comments) =>
      [
        ("control", f.control.iter().map(c => Control(c)).to_array()),
        ("metadata", f.metadata.iter().map(m => Metadata(m)).to_array()),
        (
          "namespace",
          match f.namespace {
            Some(n) => [Namespace(n)]
            None => []
          },
        ),
        ("uses", f.uses.iter().map(u => Use(u)).to_array()),
        (
          "shapes",
          f.statements
          .iter()
          .map(s => {
            match s {
              Shape(st) => Shape(st)
              Apply(a) => Apply(a)
            }
          })
          .to_array(),
        ),
        ("comments", comments.iter().map(c => Comment(c)).to_array()),
      ]
    Control(c) => [("key", [Name(c.key)]), ("value", [Value(c.value)])]
    Metadata(m) => [("key", [Name(m.key)]), ("value", [Value(m.value)])]
    Namespace(n) => [("name", [Name(n.namespace)])]
    Use(u) => [("target", [ShapeIdRef(u.id)])]
    Shape(s) => shape_entries(s)
    Apply(a) =>
      [("target", [ShapeIdRef(a.target)]), ("traits", traits(a.traits))]
    Inline(i) =>
      [
        ("docs", docs(i.docs)),
        ("traits", traits(i.traits)),
        ("for", optional_id(i.for_resource)),
        ("mixins", optional_mixins(i.mixins)),
        ("members", members(i.members)),
      ]
    Mixins(m) => [("targets", ids(m.ids))]
    Member(m) =>
      [
        ("docs", docs(m.docs)),
        ("traits", traits(m.traits)),
        ("name", [Name(m.name)]),
        (
          "target",
          match m.target {
            Explicit(t) => [ShapeIdRef(t)]
            Elided => []
          },
        ),
        ("default", optional_value(m.default)),
      ]
    EnumMember(m) =>
      [
        ("docs", docs(m.docs)),
        ("traits", traits(m.traits)),
        ("name", [Name(m.name)]),
        ("value", optional_value(m.value)),
      ]
    Property(Input(t, _)) | Property(Output(t, _)) =>
      [("target", [operation_target(t)])]
    Property(Errors(xs, _)) => [("targets", ids(xs))]
    Trait(t) => {
      let (value, entries) = match t.body {
        Some(Node(v)) => ([Value(v)], [])
        Some(Structure(kvps)) => ([], entry_nodes(kvps))
        None => ([], [])
      }
      [("id", [ShapeIdRef(t.id)]), ("value", value), ("entries", entries)]
    }
    Value(Array(xs, _)) =>
      [("elements", xs.iter().map(x => Value(x)).to_array())]
    Value(Object(kvps, _)) => [("entries", entry_nodes(kvps))]
    Entry(e) => [("key", [Name(e.key)]), ("value", [Value(e.value)])]
    _ => []
  }
}

///|
/// The node's field names, in kind-table order, whether or not they hold a
/// child. A leaf has none.
///
/// ```mbt check
/// test {
///   let r = @parser.parse_text(
///     (
///       #|$version: "2"
///       #|namespace a
///       #|
///       #|structure Foo {
///       #|    bar: String
///       #|}
///       #|
///     ),
///   )
///   let shape = @traversal.NodeRef::of_result(r).unwrap().field("shapes")[0]
///   inspect(
///     shape.fields().join(" "),
///     content="docs traits name for mixins members",
///   )
///   inspect(shape.field("for").length(), content="0")
///   let member = shape.field("members")[0]
///   inspect(member.field("target")[0].kind(), content="shape_id")
/// }
/// ```
pub fn NodeRef::fields(self : NodeRef) -> Array[String] {
  self.entries().map(e => e.0)
}

///|
/// The nodes in field `name` (a new array; empty for an absent or unknown
/// field).
pub fn NodeRef::field(self : NodeRef, name : String) -> Array[NodeRef] {
  for e in self.entries() {
    if e.0 == name {
      return e.1
    }
  }
  []
}

///|
/// `xs` in the start order of `node(x)`; among equal starts, in their order
/// in `xs`. Most nodes list their fields in source order, so `xs` comes back
/// as it is when it is in order already, and is sorted only otherwise.
fn[T] in_source_order(xs : Array[T], node : (T) -> NodeRef) -> Array[T] {
  let mut sorted = true
  for i in 1..<xs.length() {
    if node(xs[i - 1]).span().start > node(xs[i]).span().start {
      sorted = false
      break
    }
  }
  if sorted {
    return xs
  }
  // Array::sort_by is not stable, so the original position breaks ties.
  let keyed = xs.mapi((i, x) => (i, x))
  keyed.sort_by((a, b) => {
    let c = node(a.1).span().start.compare(node(b.1).span().start)
    if c != 0 {
      c
    } else {
      a.0.compare(b.0)
    }
  })
  keyed.map(x => x.1)
}

///|
/// All child nodes in source order (a new array), each with its step: its
/// field and its index in that field. Children that start at the same place
/// keep their field order. The nodes are the ones that `children` gives.
///
/// Use it to get the field of every child in one call. `field_of` looks
/// through all the fields on each call.
///
/// ```mbt check
/// test {
///   let r = @parser.parse_text(
///     (
///       #|$version: "2"
///       #|namespace a
///       #|
///       #|structure Foo {
///       #|    a: String
///       #|    b: String
///       #|}
///       #|
///     ),
///   )
///   let shape = @traversal.NodeRef::of_result(r).unwrap().field("shapes")[0]
///   let labels = shape
///     .children_with_fields()
///     .map(x => "\{x.0.field}[\{x.0.index}]:\{x.1.kind()}")
///   inspect(
///     labels.join(" "),
///     content="name[0]:name members[0]:member members[1]:member",
///   )
/// }
/// ```
pub fn NodeRef::children_with_fields(
  self : NodeRef,
) -> Array[(PathStep, NodeRef)] {
  let all : Array[(PathStep, NodeRef)] = []
  for e in self.entries() {
    for i, c in e.1 {
      all.push(({ field: e.0, index: i, }, c))
    }
  }
  in_source_order(all, x => x.1)
}

///|
/// All child nodes in source order (a new array). Doc comments come before
/// the traits they precede, and the file's comments sit among its
/// statements.
pub fn NodeRef::children(self : NodeRef) -> Array[NodeRef] {
  let all = []
  for e in self.entries() {
    all.append(e.1)
  }
  in_source_order(all, x => x)
}

///|
/// The field of this node that holds `child`, or `None` when `child` is not a
/// child of this node. It looks through all the fields on each call; to get
/// the field of every child, use `children_with_fields`.
pub fn NodeRef::field_of(self : NodeRef, child : NodeRef) -> String? {
  for e in self.entries() {
    if e.1.iter().any(c => same(c, child)) {
      return Some(e.0)
    }
  }
  None
}

///|
/// Every node type: (category, kind, fields), one row per kind. Kinds and
/// fields follow the Smithy JSON AST where it has a name, and the IDL grammar
/// for the rest.
///
/// ```mbt check
/// test {
///   let rows = @traversal.kind_table()
///   let row = rows.filter(r => r.0 == "member" && r.1 == "member")[0]
///   debug_inspect(
///     row.2,
///     content="[\"docs\", \"traits\", \"name\", \"target\", \"default\"]",
///   )
///   // `boolean` is a shape kind and a value kind.
///   let booleans = rows.filter(r => r.1 == "boolean").map(r => r.0)
///   debug_inspect(booleans, content="[\"shape\", \"value\"]")
/// }
/// ```
pub fn kind_table() -> Array[(String, String, Array[String])] {
  let rows : Array[(String, String, Array[String])] = [
    (
      "file",
      "file",
      ["control", "metadata", "namespace", "uses", "shapes", "comments"],
    ),
    ("control", "control", ["key", "value"]),
    ("metadata", "metadata", ["key", "value"]),
    ("namespace", "namespace", ["name"]),
    ("use", "use", ["target"]),
  ]
  for
    t in [
      "blob", "boolean", "document", "string", "byte", "short", "integer", "long",
      "float", "double", "bigInteger", "bigDecimal", "timestamp",
    ] {
    rows.push(("shape", t, ["docs", "traits", "name", "mixins"]))
  }
  for t in ["enum", "intEnum"] {
    rows.push(("shape", t, ["docs", "traits", "name", "mixins", "members"]))
  }
  for t in ["list", "map", "union", "structure", "set"] {
    rows.push(
      ("shape", t, ["docs", "traits", "name", "for", "mixins", "members"]),
    )
  }
  for t in ["service", "resource"] {
    rows.push(("shape", t, ["docs", "traits", "name", "mixins", "value"]))
  }
  rows.append([
    ("shape", "operation", ["docs", "traits", "name", "mixins", "properties"]),
    ("shape", "apply", ["target", "traits"]),
    ("shape", "inline", ["docs", "traits", "for", "mixins", "members"]),
    ("mixins", "mixins", ["targets"]),
    ("member", "member", ["docs", "traits", "name", "target", "default"]),
    ("member", "enumMember", ["docs", "traits", "name", "value"]),
    ("operation_property", "input", ["target"]),
    ("operation_property", "output", ["target"]),
    ("operation_property", "errors", ["targets"]),
    ("trait", "trait", ["id", "value", "entries"]),
    ("value", "array", ["elements"]),
    ("value", "object", ["entries"]),
  ])
  for t in ["number", "boolean", "null", "string", "textBlock", "shapeId"] {
    rows.push(("value", t, []))
  }
  rows.append([
    ("entry", "entry", ["key", "value"]),
    ("shape_id", "shape_id", []),
    ("name", "name", []),
    ("doc", "doc", []),
    ("comment", "line", []),
    ("comment", "doc", []),
  ])
  rows
}
