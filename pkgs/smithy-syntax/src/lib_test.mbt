///|
test "the module reports its version" {
  inspect(@syntax.version(), content="0.1.0")
}

///|
test "the root re-exports the traversal" {
  let r = @syntax.parse_idl(
    (
      #|$version: "2"
      #|namespace a
      #|
      #|string Name
      #|
    ),
  )
  guard @syntax.NodeRef::of_result(r) is Some(root) else { fail("no root") }
  let mut n = 0
  @syntax.walk(root, _ => {
    n = n + 1
    Continue
  })
  inspect(n, content="8")
  inspect(
    @syntax.reduce(root, (_, rs : ArrayView[Int32]) => {
      1 + rs.iter().fold(init=0, (a, b) => a + b)
    }),
    content="8",
  )
  inspect(@syntax.fold(root, 0, (a, _) => (a + 1, Continue)), content="8")
  debug_inspect(
    @syntax.reduce_pruned(root, _ => Stop, (_, _) => 0),
    content="None",
  )
  inspect(@syntax.Tree::new(r).unwrap().root().kind(), content="file")
  inspect(@syntax.kind_table().length(), content="51")
  inspect(@syntax.NodePath::root().child("shapes", 0), content="shapes[0]")
}
