///|
test "every TCK case walks and every node is entered once" {
  for c in @tck.cases() {
    let r = @syntax.parse_idl(c.text)
    guard @syntax.Tree::new(r) is Some(tree) else { continue }
    let root = tree.root()
    let mut entered = 0
    let mut paths_ok = true
    @syntax.walk(root, n => {
      entered = entered + 1
      paths_ok = paths_ok &&
        tree.node_path(n).bind(p => p.resolve(root)) == Some(n)
      Continue
    })
    let counted = @syntax.reduce(root, (_, rs : ArrayView[Int32]) => {
      1 + rs.iter().fold(init=0, (a, b) => a + b)
    })
    assert_eq(entered, counted, msg=c.path)
    assert_true(paths_ok, msg=c.path)
  }
}
