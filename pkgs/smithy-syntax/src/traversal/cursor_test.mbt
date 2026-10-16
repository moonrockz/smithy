///|
test "a cursor starts at its node with depth 0 and no field" {
  let c = @traversal.TreeCursor::new(root_of(tiny))
  assert_eq(c.depth(), 0)
  assert_eq(c.field_name(), None)
  assert_eq(c.node().kind(), "file")
  assert_eq(c.path().to_string(), "")
}

///|
test "goto_first_child, goto_next_sibling and goto_parent move and report fields" {
  let c = @traversal.TreeCursor::new(root_of(tiny))
  assert_true(c.goto_first_child())
  assert_eq(c.field_name(), Some("control"))
  assert_true(c.goto_next_sibling())
  assert_eq(c.field_name(), Some("namespace"))
  assert_true(c.goto_next_sibling())
  assert_eq(c.field_name(), Some("shapes"))
  assert_true(c.goto_first_child())
  assert_eq(c.field_name(), Some("traits"))
  assert_eq(c.depth(), 2)
  assert_eq(c.path().to_string(), "shapes[0].traits[0]")
  assert_true(c.goto_parent())
  assert_eq(c.node().kind(), "string")
}

///|
test "goto_last_child and goto_previous_sibling" {
  let c = @traversal.TreeCursor::new(root_of(tiny))
  assert_true(c.goto_last_child())
  assert_eq(c.field_name(), Some("shapes"))
  assert_true(c.goto_previous_sibling())
  assert_eq(c.field_name(), Some("namespace"))
}

///|
test "a move that has nowhere to go returns false and leaves the cursor in place" {
  let c = @traversal.TreeCursor::new(root_of(tiny))
  assert_false(c.goto_parent())
  assert_false(c.goto_next_sibling())
  assert_false(c.goto_previous_sibling())
  assert_true(c.goto_first_child())
  assert_true(c.goto_first_child())
  // The control key: a leaf.
  assert_false(c.goto_first_child())
  assert_false(c.goto_last_child())
  assert_eq(c.field_name(), Some("key"))
  assert_eq(c.path().to_string(), "control[0].key[0]")
}

///|
test "goto_first_child_for picks the child that contains the offset, or the first after it" {
  let c = @traversal.TreeCursor::new(root_of(three_shapes))
  assert_true(c.goto_first_child_for(off(three_shapes, "string B")))
  assert_eq(c.path().to_string(), "shapes[1]")
  c.reset(root_of(three_shapes))
  // A blank line between statements: the next statement.
  assert_true(c.goto_first_child_for(off(three_shapes, "\n\nstring B")))
  assert_eq(c.path().to_string(), "shapes[1]")
}

///|
test "goto_node_at moves to the innermost node, and stays when the node does not contain the offset" {
  let c = @traversal.TreeCursor::new(root_of(three_shapes))
  assert_true(c.goto_node_at(off(three_shapes, "x: A")))
  assert_eq(c.path().to_string(), "shapes[2].members[0].name[0]")
  assert_false(c.goto_node_at(off(three_shapes, "string A")))
  assert_eq(c.path().to_string(), "shapes[2].members[0].name[0]")
}

///|
test "reset moves the cursor to a new start node" {
  let c = @traversal.TreeCursor::new(root_of(tiny))
  ignore(c.goto_first_child())
  let shape = root_of(three_shapes).field("shapes")[2]
  c.reset(shape)
  assert_eq(c.depth(), 0)
  assert_eq(c.node(), shape)
  assert_eq(c.field_name(), None)
}

///|
test "a copy moves independently of its cursor" {
  let c = @traversal.TreeCursor::new(root_of(tiny))
  ignore(c.goto_first_child())
  let d = c.copy()
  ignore(d.goto_next_sibling())
  assert_eq(c.field_name(), Some("control"))
  assert_eq(d.field_name(), Some("namespace"))
}

///|
test "a cursor tours a 95-deep value" {
  let root = root_of(deep_value(95))
  let (seen, home) = cursor_tour(root)
  assert_true(home)
  assert_eq(seen.length(), all_nodes(root).length())
}
