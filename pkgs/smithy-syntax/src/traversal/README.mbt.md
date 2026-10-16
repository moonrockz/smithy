# traversal

A read-only node model over the Smithy IDL AST, and traversal styles that
all agree. `NodeRef` points into the AST (nothing is copied). With the same
`Control` decisions, `walk`, `fold`, `accept`, an `EventReader`,
`push_events` and `reduce_pruned` give the same enter and leave order, and a
full `TreeCursor` navigation enters the same nodes. No walk recurses: each
one keeps its own stack, so deep trees work on every target.

Kinds and field names follow the Smithy JSON AST where it has a name (a
shape's kind is its JSON `type`; a member has a `target`), and the IDL
grammar for the rest. `(category, kind)` identifies a node type.

## The node model

```mbt check
///|
test "fields and children" {
  let r = @parser.parse_text(
    (
      #|$version: "2"
      #|namespace a
      #|
      #|/// A person.
      #|structure Person {
      #|    name: String
      #|}
      #|
    ),
  )
  let root = @traversal.NodeRef::of_result(r).unwrap()
  let person = root.field("shapes")[0]
  inspect("\{person.category()}/\{person.kind()}", content="shape/structure")
  inspect(
    person.children().map(c => c.category()).join(" "),
    content="doc name member",
  )
}
```

Spans: `span()` is the AST span, widened so that it covers every child. The
parser's span of a shape, member, enum member or inline shape starts after
its doc comments, because doc comments are trivia; `span()` starts at the
first doc comment. An operation property covers the docs of its inline
shape, and the file covers every comment. The file node holds every `//`
comment and every `///` comment that documents nothing.

## Walk, fold and reduce

```mbt check
///|
test "walk, fold and reduce" {
  let r = @parser.parse_text("namespace a\n\n@t\nstring S\n")
  let root = @traversal.NodeRef::of_result(r).unwrap()
  let log = []
  @traversal.walk(root, n => {
    log.push(n.category())
    if n.category() == "trait" {
      SkipChildren
    } else {
      Continue
    }
  })
  inspect(log.join(" "), content="file namespace name shape trait name")
  let count = @traversal.fold(root, 0, (a, _) => (a + 1, Continue))
  inspect(count, content="7")
  // Bottom up: each node with the results of its children.
  let leaves = @traversal.reduce(root, (_, rs : ArrayView[Int32]) => {
    if rs.length() == 0 {
      1
    } else {
      rs.iter().fold(init=0, (a, b) => a + b)
    }
  })
  inspect(leaves, content="3")
  // reduce_pruned can skip a subtree, or stop with None.
  let pruned = @traversal.reduce_pruned(
    root,
    n => if n.category() == "trait" { SkipChildren } else { Continue },
    (_, rs : ArrayView[Int32]) => 1 + rs.iter().fold(init=0, (a, b) => a + b),
  )
  debug_inspect(pruned, content="Some(6)")
}
```

## Events

```mbt check
///|
test "pull events" {
  let r = @parser.parse_text("namespace a\n\nstring S\n")
  let root = @traversal.NodeRef::of_result(r).unwrap()
  let reader = @traversal.EventReader::new(root)
  let log = []
  while reader.next() is Some(e) {
    match e {
      Enter(e) => {
        log.push("+\{e.path}")
        if e.category == "namespace" {
          reader.skip_children()
        }
      }
      Leave(_) => ()
    }
  }
  inspect(
    log.join(" "),
    content="+ +namespace[0] +shapes[0] +shapes[0].name[0]",
  )
}
```

`push_events(source, handler)` drives any `EventSource` into a `Handler`;
`accept(root, visitor)` calls one `Visitor` method per node category
(`visit_file`, `visit_statement`, `visit_shape`, `visit_member`,
`visit_trait`, `visit_value`, `visit_comment`, `visit_other`). Both traits
have defaults, so a type implements only the methods it needs:

```mbt check
///|
struct TraitIds(Array[String])

///|
impl @traversal.Visitor for TraitIds with fn visit_trait(self, n) {
  if n is Trait(t) {
    self.0.push(t.id.value.to_string())
  }
  SkipChildren
}

///|
test "a visitor" {
  let r = @parser.parse_text(
    "namespace a\n\n@required\n@length(min: 1)\nstring S\n",
  )
  let ids = TraitIds([])
  @traversal.accept(@traversal.NodeRef::of_result(r).unwrap(), ids)
  debug_inspect(ids.0, content="[\"required\", \"length\"]")
}
```

A `Handler` for `push_events` steers the run with the `Control` of
`on_enter`:

```mbt check
///|
struct Paths(Array[String])

///|
impl @traversal.Handler for Paths with fn on_enter(self, e) {
  self.0.push(e.path.to_string())
  if e.category == "shape" {
    SkipChildren
  } else {
    Continue
  }
}

///|
test "push events into a handler" {
  let r = @parser.parse_text("namespace a\n\nstring S\n")
  let root = @traversal.NodeRef::of_result(r).unwrap()
  let paths = Paths([])
  @traversal.push_events(@traversal.EventReader::new(root), paths)
  debug_inspect(
    paths.0,
    content="[\"\", \"namespace[0]\", \"namespace[0].name[0]\", \"shapes[0]\"]",
  )
}
```

## Tree, cursor and paths

```mbt check
///|
test "tree, cursor and path" {
  let text =
    #|namespace a
    #|
    #|structure Foo {
    #|    x: String
    #|}
    #|
  let tree = @traversal.Tree::new(@parser.parse_text(text)).unwrap()
  let at = @span.Offset::new(text.find("x:").unwrap()).unwrap()
  let name = tree.node_at(at).unwrap()
  inspect(tree.node_path(name).unwrap(), content="shapes[0].members[0].name[0]")
  let c = @traversal.TreeCursor::new(tree.root())
  inspect(c.goto_node_at(at), content="true")
  inspect(c.path(), content="shapes[0].members[0].name[0]")
}
```

## Kind table

One row per `(category, kind)`. Fields are in `fields()` order. A feature
checks this table against `kind_table()`.

<!-- kinds:start -->
| Category | Kind | Fields |
|---|---|---|
| `file` | `file` | control, metadata, namespace, uses, shapes, comments |
| `control` | `control` | key, value |
| `metadata` | `metadata` | key, value |
| `namespace` | `namespace` | name |
| `use` | `use` | target |
| `shape` | `blob` | docs, traits, name, mixins |
| `shape` | `boolean` | docs, traits, name, mixins |
| `shape` | `document` | docs, traits, name, mixins |
| `shape` | `string` | docs, traits, name, mixins |
| `shape` | `byte` | docs, traits, name, mixins |
| `shape` | `short` | docs, traits, name, mixins |
| `shape` | `integer` | docs, traits, name, mixins |
| `shape` | `long` | docs, traits, name, mixins |
| `shape` | `float` | docs, traits, name, mixins |
| `shape` | `double` | docs, traits, name, mixins |
| `shape` | `bigInteger` | docs, traits, name, mixins |
| `shape` | `bigDecimal` | docs, traits, name, mixins |
| `shape` | `timestamp` | docs, traits, name, mixins |
| `shape` | `enum` | docs, traits, name, mixins, members |
| `shape` | `intEnum` | docs, traits, name, mixins, members |
| `shape` | `list` | docs, traits, name, for, mixins, members |
| `shape` | `map` | docs, traits, name, for, mixins, members |
| `shape` | `union` | docs, traits, name, for, mixins, members |
| `shape` | `structure` | docs, traits, name, for, mixins, members |
| `shape` | `set` | docs, traits, name, for, mixins, members |
| `shape` | `service` | docs, traits, name, mixins, value |
| `shape` | `resource` | docs, traits, name, mixins, value |
| `shape` | `operation` | docs, traits, name, mixins, properties |
| `shape` | `apply` | target, traits |
| `shape` | `inline` | docs, traits, for, mixins, members |
| `mixins` | `mixins` | targets |
| `member` | `member` | docs, traits, name, target, default |
| `member` | `enumMember` | docs, traits, name, value |
| `operation_property` | `input` | target |
| `operation_property` | `output` | target |
| `operation_property` | `errors` | targets |
| `trait` | `trait` | id, value, entries |
| `value` | `array` | elements |
| `value` | `object` | entries |
| `value` | `number` | — |
| `value` | `boolean` | — |
| `value` | `null` | — |
| `value` | `string` | — |
| `value` | `textBlock` | — |
| `value` | `shapeId` | — |
| `entry` | `entry` | key, value |
| `shape_id` | `shape_id` | — |
| `name` | `name` | — |
| `doc` | `doc` | — |
| `comment` | `line` | — |
| `comment` | `doc` | — |
<!-- kinds:end -->
