///|
fn cursor_laws(text : String) -> Bool {
  guard @traversal.Tree::new(@parser.parse_text(text)) is Some(tree) else {
    return true
  }
  let root = tree.root()
  // A full navigation enters children() pre-order and ends at the start.
  let (seen, home) = cursor_tour(root)
  let tour = home && seen == all_nodes(root).map(tag)
  // goto_node_at agrees with Tree::node_at, and its path with node_path.
  let at = all_nodes(root)
    .iter()
    .all(n => {
      let p = n.span().start
      let c = @traversal.TreeCursor::new(root)
      match tree.node_at(p) {
        Some(m) =>
          c.goto_node_at(p) &&
          c.node() == m &&
          Some(c.path()) == tree.node_path(m)
        None => !c.goto_node_at(p) && c.depth() == 0
      }
    })
  // A copy moves independently.
  let c = @traversal.TreeCursor::new(root)
  ignore(c.goto_first_child())
  let before = c.path()
  let d = c.copy()
  ignore(d.goto_first_child())
  ignore(d.goto_next_sibling())
  tour && at && c.path() == before
}

///|
test "law: a cursor tours the tree, goto_node_at agrees with node_at, and copies are independent" {
  @quickcheck.check(
    (m : @lawkit.EditedModel) => cursor_laws(m.text()),
    count=150,
    max_size=16,
    seed=1011,
  )
  @quickcheck.check(
    (t : @lawkit.SmithyText) => cursor_laws(t.text()),
    count=300,
    max_size=16,
    seed=1012,
  )
}

///|
/// A failed move leaves node, path and depth as they were.
fn failed_moves_stay(text : String) -> Bool {
  guard maybe_root(text) is Some(root) else { return true }
  let c = @traversal.TreeCursor::new(root)
  let moves : Array[(@traversal.TreeCursor) -> Bool] = [
    c => c.goto_first_child(),
    c => c.goto_last_child(),
    c => c.goto_next_sibling(),
    c => c.goto_previous_sibling(),
    c => c.goto_parent(),
  ]
  let mut ok = true
  // Walk the tour, trying every move at every stop on a copy.
  for _ in 0..<64 {
    for m in moves {
      let d = c.copy()
      let path = d.path()
      let depth = d.depth()
      let node = d.node()
      if !m(d) {
        ok = ok && d.path() == path && d.depth() == depth && d.node() == node
      }
    }
    if !c.goto_first_child() && !c.goto_next_sibling() {
      while !c.goto_next_sibling() {
        if !c.goto_parent() {
          return ok
        }
      }
    }
  }
  ok
}

///|
test "law: every move that returns false leaves the cursor in place" {
  @quickcheck.check(
    (m : @lawkit.EditedModel) => failed_moves_stay(m.text()),
    count=150,
    max_size=16,
    seed=1013,
  )
}
