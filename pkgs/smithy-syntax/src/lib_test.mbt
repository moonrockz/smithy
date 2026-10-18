///|
test "the module reports its version" {
  inspect(@syntax.version(), content="0.2.0")
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

///|
test "the facade exposes token parsing, codes and streaming all diagnostics" {
  let source = @syntax.SourceText::new("namespace a use b#C")
  let result = @syntax.parse_tokens(@syntax.tokenize(source))
  assert_eq(result, @syntax.parse(source))
  assert_true(@syntax.codes().contains(result.diagnostics[0].code))
  let sink = StringBuilder()
  @syntax.render_all_to(result.diagnostics, source, sink, color=false)
  assert_eq(
    sink.to_string(),
    @syntax.render_all(result.diagnostics, source, color=false),
  )
  assert_eq(source, @syntax.SourceText::new(source.text()))
}
