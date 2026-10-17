///|
fn tree_of(text : String) -> @traversal.Tree raise {
  guard @traversal.Tree::new(@parser.parse_text(text)) is Some(t) else {
    fail("no tree")
  }
  t
}

///|
test "a tree gives parents, ancestors and paths" {
  let tree = tree_of(three_shapes)
  let member = tree.root().field("shapes")[2].field("members")[0]
  let target = member.field("target")[0]
  assert_eq(tree.parent(target).map(n => n.kind()), Some("member"))
  assert_eq(tree.field_of(target), Some("target"))
  assert_eq(tree.step(member), Some({ field: "members", index: 0, }))
  assert_eq(tree.ancestors(target).map(n => n.kind()), [
    "member", "structure", "file",
  ])
  assert_eq(tree.path(target).map(n => n.kind()), [
    "file", "structure", "member", "shape_id",
  ])
  assert_eq(tree.parent(tree.root()), None)
  assert_eq(tree.step(tree.root()), None)
}

///|
test "node_path gives a node's path from the root, or None for a node not in the tree" {
  let tree = tree_of(three_shapes)
  let target = tree.root().field("shapes")[2].field("members")[0].field(
      "target",
    )[0]
  assert_eq(
    tree.node_path(target).map(p => p.to_string()),
    Some("shapes[2].members[0].target[0]"),
  )
  let other = root_of(tiny).field("shapes")[0]
  assert_eq(tree.node_path(other), None)
}

///|
test "node_at on a doc comment finds the doc node" {
  let tree = tree_of(documented)
  guard tree.node_at(off(documented, "/// Doc").advance(@span.Length::one()))
    is Some(n) else {
    fail("nothing at the doc comment")
  }
  assert_eq(n.category(), "doc")
  assert_eq(tree.parent(n).map(p => p.kind()), Some("structure"))
}

///|
test "node_at on a member name finds the name" {
  let tree = tree_of(three_shapes)
  guard tree.node_at(off(three_shapes, "x: A")) is Some(Name(n)) else {
    fail("no name at x")
  }
  assert_eq(n.value, "x")
}

///|
test "node_at between members finds the shape, and outside every statement finds the file" {
  let tree = tree_of(three_shapes)
  guard tree.node_at(off(three_shapes, "{")) is Some(n) else { fail("nothing") }
  assert_eq(n.kind(), "structure")
  guard tree.node_at(off(three_shapes, "\n\nstring A")) is Some(f) else {
    fail("nothing")
  }
  assert_eq(f.kind(), "file")
}

///|
test "tokens_in gives the tokens inside a span" {
  let tree = tree_of(three_shapes)
  let member = tree.root().field("shapes")[2].field("members")[0]
  assert_eq(tree.tokens_in(member.span()).map(t => t.lexeme), ["x", ":", "A"])
}

///|
test "Tree::new is None when the parser gives no AST" {
  assert_true(@traversal.Tree::new(@parser.parse_text("}\n")) is None)
}

///|
test "a 95-deep value builds a Tree" {
  let tree = tree_of(deep_value(95))
  let mut deepest = tree.root()
  // The last array entered in pre-order is the innermost one.
  @traversal.walk(tree.root(), n => {
    if n.kind() == "array" {
      deepest = n
    }
    Continue
  })
  assert_eq(tree.ancestors(deepest).length() >= 95, true)
  assert_true(tree.node_path(deepest) is Some(_))
}

///|
test "a node from another parse of the same text is not in the tree" {
  let tree = tree_of(three_shapes)
  let other = root_of(three_shapes)
  let member = other.field("shapes")[2].field("members")[0]
  let target = member.field("target")[0]
  assert_eq(tree.parent(target), None)
  assert_eq(tree.node_path(target), None)
  assert_eq(tree.ancestors(target).length(), 0)
  assert_eq(tree.root().field("shapes")[2].field_of(member), None)
  // The tree's own nodes are still found.
  let own = tree.root().field("shapes")[2].field("members")[0]
  assert_eq(tree.root().field("shapes")[2].field_of(own), Some("members"))
}

///|
test "identity checks reject equal nodes from another parse for every node variant" {
  let own = all_nodes(root_of(every_form))
  let other = all_nodes(root_of(every_form))
  assert_eq(own.length(), other.length())
  for i, node in own {
    assert_eq(node, other[i])
    assert_true(same_node(node, node))
    assert_false(same_node(node, other[i]), msg=tag(node))
  }
}
