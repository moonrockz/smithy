///|
test "ancestors of every member of a commented shape take linear time" {
  let sb = StringBuilder()
  sb.write_string("namespace a\n\nstructure Big {\n")
  for i in 0..<8000 {
    sb.write_string("    // note\n    m\{i}: String\n")
  }
  sb.write_string("}\n")
  let tree = tree_of(sb.to_string())
  let members = tree.root().field("shapes")[0].field("members")
  let start = @env.now()
  let mut total = 0
  for m in members {
    total = total + tree.ancestors(m).length()
    total = total + tree.node_path(m).map(p => p.depth()).unwrap_or(0)
  }
  let elapsed = @env.now() - start
  assert_eq(total, 8000 * 4)
  // A file span recomputed over every comment on each lookup made this
  // quadratic (seconds).
  assert_true(elapsed < 500, msg="took \{elapsed} ms")
}

///|
/// A tree far deeper than the parser allows: `depth` nested arrays, each
/// span inside its parent's, built by hand.
fn deep_tree(depth : Int32) -> @traversal.NodeRef raise {
  guard @span.Offset::new(depth - 1) is Some(at) &&
    @span.Length::new(2) is Some(two) else {
    fail("bad span")
  }
  let none : Array[@ast.NodeValue] = []
  let mut v : @ast.NodeValue = Array(none[:], @span.Span::new(at, two))
  for i = depth - 2; i >= 0; i = i - 1 {
    guard @span.Offset::new(i) is Some(start) &&
      @span.Length::new(2 * (depth - i)) is Some(length) else {
      fail("bad span")
    }
    v = Array([v][:], @span.Span::new(start, length))
  }
  Value(v)
}

///|
struct Counter {
  mut n : Int32
}

///|
impl @traversal.Visitor for Counter with fn visit_value(self, _) {
  self.n = self.n + 1
  Continue
}

///|
impl @traversal.Handler for Counter with fn on_enter(self, _) {
  self.n = self.n + 1
  Continue
}

///|
test "every style handles a 10000-deep tree without recursion" {
  let depth = 10000
  let root = deep_tree(depth)
  let mut walked = 0
  @traversal.walk(root, _ => {
    walked = walked + 1
    Continue
  })
  assert_eq(walked, depth)
  assert_eq(@traversal.fold(root, 0, (a, _) => (a + 1, Continue)), depth)
  let count = (_ : @traversal.NodeRef, rs : ArrayView[Int32]) => {
    1 + rs.iter().fold(init=0, (a, b) => a + b)
  }
  assert_eq(@traversal.reduce(root, count), depth)
  assert_eq(@traversal.reduce_pruned(root, _ => Continue, count), Some(depth))
  assert_eq(@traversal.EventReader::new(root).iter().count(), 2 * depth)
  let pushed = { n: 0, }
  @traversal.push_events(@traversal.EventReader::new(root), pushed)
  assert_eq(pushed.n, depth)
  let visited = { n: 0, }
  @traversal.accept(root, visited)
  assert_eq(visited.n, depth)
  let c = @traversal.TreeCursor::new(root)
  while c.goto_first_child() {
    ()
  }
  assert_eq(c.depth(), depth - 1)
  assert_eq(c.path().depth(), depth - 1)
  let d = @traversal.TreeCursor::new(root)
  guard @span.Offset::new(depth - 1) is Some(inner) else { fail("bad offset") }
  assert_true(d.goto_node_at(inner))
  assert_eq(d.depth(), depth - 1)
}
