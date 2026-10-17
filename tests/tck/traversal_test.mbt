///|
test "every TCK case walks and every node is entered once" {
  let no_ast = []
  let mut walked = 0
  for c in @tck.cases() {
    let r = @syntax.parse_idl(c.text)
    guard @syntax.Tree::new(r) is Some(tree) else {
      no_ast.push(c.path)
      assert_true(r.has_errors(), msg=c.path)
      assert_false(c.kind is Valid || c.kind is Recovery, msg=c.path)
      continue
    }
    walked += 1
    let root = tree.root()
    let mut entered = 0
    let mut paths_ok = true
    let tags : Set[String] = Set([])
    let duplicates = []
    @syntax.walk(root, n => {
      entered = entered + 1
      let span = n.span()
      let tag = "\{n.category()}/\{n.kind()}@\{span.start.0}+\{span.length.0}"
      if tags.contains(tag) {
        duplicates.push(tag)
      }
      tags.add(tag)
      paths_ok = paths_ok &&
        tree.node_path(n).bind(p => p.resolve(root)) == Some(n)
      Continue
    })
    let counted = @syntax.reduce(root, (_, rs : ArrayView[Int32]) => {
      1 + rs.iter().fold(init=0, (a, b) => a + b)
    })
    assert_eq(duplicates, [], msg=c.path)
    assert_eq(tags.length(), entered, msg=c.path)
    assert_eq(entered, counted, msg=c.path)
    assert_true(paths_ok, msg=c.path)
  }
  assert_eq(walked + no_ast.length(), @tck.cases().length())
  debug_inspect(
    no_ast,
    content=(
      #|[
      #|  "invalid/control/control-colon-newline.smithy",
      #|  "invalid/control/control-missing-value.smithy",
      #|  "invalid/control/control-newline.smithy",
      #|  "invalid/control/control-with-invalid-key2.smithy",
      #|  "invalid/control/control-with-no-colon.smithy",
      #|  "invalid/control/no-newline-after-control.smithy",
      #|  "invalid/metadata/invalid-object-shape-id-key.smithy",
      #|  "invalid/metadata/invalid-object-text-block-key.smithy",
      #|  "invalid/metadata/metadata-with-invalid-key.smithy",
      #|  "invalid/namespace/namespace-before-traits.smithy",
      #|  "invalid/namespace/namespace-syntax-error.smithy",
      #|  "invalid/parse-errors/syntax-error-token.smithy",
      #|  "invalid/traits/traits-on-metadata.smithy",
      #|  "invalid/traits/traits-on-namespace.smithy",
      #|  "invalid/version/invalid-version-type.smithy",
      #|  "invalid/version/unsupported-version.smithy",
      #|]
    ),
  )
}
