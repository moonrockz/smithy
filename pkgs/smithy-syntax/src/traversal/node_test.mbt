///|
/// Every statement form, shape family and node value kind.
let every_form : String =
  #|$version: "2"
  #|metadata m = [1, 2.5, true, false, null, "s", Foo]
  #|namespace a.b
  #|use smithy.api#String
  #|
  #|// a line comment
  #|/// Doc
  #|@tags(["x"])
  #|@doc("""
  #|    text
  #|    """)
  #|@range(min: 1)
  #|structure Foo with [Mix] {
  #|    bar: String = "x"
  #|    $baz
  #|}
  #|
  #|string Name
  #|bigDecimal Price
  #|enum Color {
  #|    RED = "red"
  #|}
  #|intEnum Level {
  #|    LOW = 1
  #|}
  #|service Shop {
  #|    version: "1"
  #|}
  #|operation Op {
  #|    input := {
  #|        a: String
  #|    }
  #|    output: Foo
  #|    errors: [E]
  #|}
  #|/// detached
  #|apply Foo @sensitive
  #|

///|
/// Every node of a file by plain recursion over the AST (test-only; the
/// trees here are shallow). It checks `category` and `kind` before
/// `children` exists.
fn every_node(root : @traversal.NodeRef) -> Array[@traversal.NodeRef] {
  let out = []
  fn id(x : @ast.Node[@ast.ShapeId]) {
    out.push(@traversal.ShapeIdRef(x))
  }

  fn name(x : @ast.Node[String]) {
    out.push(@traversal.Name(x))
  }

  fn value(v : @ast.NodeValue) {
    out.push(@traversal.Value(v))
    match v {
      Array(xs, _) =>
        for x in xs {
          value(x)
        }
      Object(kvps, _) =>
        for k in kvps {
          out.push(@traversal.Entry(k))
          name(k.key)
          value(k.value)
        }
      _ => ()
    }
  }

  fn entry(k : @ast.NodeKvp) {
    out.push(@traversal.Entry(k))
    name(k.key)
    value(k.value)
  }

  fn traits(ts : ArrayView[@ast.Trait]) {
    for t in ts {
      out.push(@traversal.Trait(t))
      id(t.id)
      match t.body {
        Some(Node(v)) => value(v)
        Some(Structure(kvps)) =>
          for k in kvps {
            entry(k)
          }
        None => ()
      }
    }
  }

  fn docs(ds : ArrayView[@ast.DocComment]) {
    for d in ds {
      out.push(@traversal.Doc(d))
    }
  }

  fn mixins(m : @ast.Mixins?) {
    if m is Some(m) {
      out.push(@traversal.Mixins(m))
      for x in m.ids {
        id(x)
      }
    }
  }

  fn members(ms : ArrayView[@ast.Member]) {
    for m in ms {
      out.push(@traversal.Member(m))
      docs(m.docs)
      traits(m.traits)
      name(m.name)
      if m.target is Explicit(t) {
        id(t)
      }
      if m.default is Some(v) {
        value(v)
      }
    }
  }

  guard root is File(f, comments) else { return out }
  out.push(root)
  for c in comments {
    out.push(@traversal.Comment(c))
  }
  for c in f.control {
    out.push(@traversal.Control(c))
    name(c.key)
    value(c.value)
  }
  for m in f.metadata {
    out.push(@traversal.Metadata(m))
    name(m.key)
    value(m.value)
  }
  if f.namespace is Some(ns) {
    out.push(@traversal.Namespace(ns))
    name(ns.namespace)
  }
  for u in f.uses {
    out.push(@traversal.Use(u))
    id(u.id)
  }
  for s in f.statements {
    match s {
      Apply(a) => {
        out.push(@traversal.Apply(a))
        id(a.target)
        traits(a.traits)
      }
      Shape(st) => {
        out.push(@traversal.Shape(st))
        docs(st.docs)
        traits(st.traits)
        name(st.shape.name())
        match st.shape {
          Simple(mixins=m, ..) => mixins(m)
          Enum(mixins=m, members=ms, ..) => {
            mixins(m)
            for em in ms {
              out.push(@traversal.EnumMember(em))
              docs(em.docs)
              traits(em.traits)
              name(em.name)
              if em.value is Some(v) {
                value(v)
              }
            }
          }
          Aggregate(for_resource=r, mixins=m, members=ms, ..) => {
            if r is Some(r) {
              id(r)
            }
            mixins(m)
            members(ms)
          }
          Entity(mixins=m, body~, ..) => {
            mixins(m)
            value(body)
          }
          Operation(mixins=m, properties~, ..) => {
            mixins(m)
            for p in properties {
              out.push(@traversal.Property(p))
              match p {
                Input(Reference(t), _) | Output(Reference(t), _) => id(t)
                Input(Inline(i), _) | Output(Inline(i), _) => {
                  out.push(@traversal.Inline(i))
                  docs(i.docs)
                  traits(i.traits)
                  if i.for_resource is Some(r) {
                    id(r)
                  }
                  mixins(i.mixins)
                  members(i.members)
                }
                Errors(ids, _) =>
                  for x in ids {
                    id(x)
                  }
              }
            }
          }
        }
      }
    }
  }
  out
}

///|
test "category and kind follow the kind table" {
  let seen = Map([])
  for root in kind_roots() {
    for n in every_node(root) {
      seen["\{n.category()}/\{n.kind()}"] = true
    }
  }
  assert_true(seen.contains("comment/doc"))
  assert_true(seen.contains("operation_property/output"))
  for row in @traversal.kind_table() {
    let key = "\{row.0}/\{row.1}"
    assert_true(seen.contains(key), msg="missing \{key}")
  }
}

///|
test "true and false are both boolean values" {
  let kinds = every_node(root_of(every_form))
    .filter(n => n.category() == "value")
    .map(n => n.kind())
  assert_eq(kinds.filter(k => k == "boolean").length(), 2)
  assert_eq(kinds.filter(k => k == "null").length(), 1)
}

///|
let documented : String =
  #|$version: "2"
  #|namespace a
  #|
  #|/// Doc
  #|@tags(["x"])
  #|structure Foo {
  #|    /// m
  #|    bar: String
  #|}
  #|
  #|string Plain
  #|

///|
test "a documented shape starts at its first doc comment" {
  let nodes = every_node(root_of(documented))
  guard nodes.search_by(n => n.kind() == "structure") is Some(i) else {
    fail("no structure")
  }
  guard nodes[i] is Shape(s) else { fail("not a shape") }
  assert_eq(nodes[i].span().start, off(documented, "/// Doc"))
  assert_eq(s.span.start, off(documented, "@tags"))
  assert_eq(nodes[i].span().end(), s.span.end())
}

///|
test "a documented member starts at its first doc comment" {
  let nodes = every_node(root_of(documented))
  guard nodes.search_by(n => n.category() == "member") is Some(i) else {
    fail("no member")
  }
  assert_eq(nodes[i].span().start, off(documented, "/// m"))
}

///|
test "a shape with no docs has its AST span" {
  let nodes = every_node(root_of(documented))
  guard nodes.search_by(n => n.category() == "shape" && n.kind() == "string")
    is Some(i) else {
    fail("no string shape")
  }
  guard nodes[i] is Shape(s) else { fail("not a shape") }
  assert_eq(nodes[i].span(), s.span)
}

///|
let inline_docs : String =
  #|$version: "2"
  #|namespace a
  #|
  #|operation Op {
  #|    input :=
  #|    /// in
  #|    {
  #|        a: String
  #|    }
  #|}
  #|

///|
test "an input property covers the docs of its inline shape" {
  let nodes = every_node(root_of(inline_docs))
  let doc = off(inline_docs, "/// in")
  guard nodes.search_by(n => n.category() == "operation_property") is Some(p) else {
    fail("no property")
  }
  guard nodes.search_by(n => n.kind() == "inline") is Some(i) else {
    fail("no inline shape")
  }
  assert_true(nodes[p].span().start <= doc && nodes[p].span().end() > doc)
  assert_true(nodes[i].span().start <= doc && nodes[i].span().end() > doc)
}

///|
test "the file holds line comments and detached doc comments" {
  let text =
    #|$version: "2"
    #|// top
    #|namespace a
    #|
    #|/// Doc
    #|structure Foo {}
    #|
    #|/// lost
    #|apply Foo @sensitive
    #|
  guard root_of(text) is File(_, comments) else { fail("not a file") }
  let got = comments.map(c => {
    let k = match c.kind {
      Line => "line"
      Doc => "doc"
    }
    "\{k} \{c.text.trim()}"
  })
  assert_eq(got, ["line top", "doc lost"])
}

///|
test "a comment-only file covers its comments" {
  let root = root_of("// only\n")
  guard root is File(_, comments) else { fail("not a file") }
  assert_eq(comments.length(), 1)
  assert_eq(root.span().start.0, 0)
  assert_eq(root.span().length.0, 7)
}

///|
test "of_result is None when the parser gives no AST" {
  let r = @parser.parse_text("}\n")
  assert_true(r.ast is None)
  assert_true(@traversal.NodeRef::of_result(r) is None)
}

///|
test "an empty text gives a file node with no comments" {
  guard root_of("") is File(_, comments) else { fail("not a file") }
  assert_eq(comments.length(), 0)
}

///|
/// Valid models together exercising every row of the traversal kind table.
fn kind_roots() -> Array[@traversal.NodeRef] raise {
  let extras =
    #|$version: "2"
    #|namespace kinds
    #|blob Blob
    #|boolean Boolean
    #|document Document
    #|byte Byte
    #|short Short
    #|integer Integer
    #|long Long
    #|float Float
    #|double Double
    #|bigInteger BigInteger
    #|timestamp Timestamp
    #|list List { member: String }
    #|map Map { key: String value: String }
    #|union Union { choice: String }
    #|resource Resource {}
  let models = [
    every_form, extras, "namespace kinds\nset Set { member: String }",
  ]
  let roots = []
  for text in models {
    let result = @parser.parse_text(text)
    assert_false(result.has_errors())
    roots.push(@traversal.NodeRef::of_result(result).unwrap())
  }
  roots
}
