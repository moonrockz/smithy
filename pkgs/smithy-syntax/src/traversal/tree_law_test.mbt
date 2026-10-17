///|
/// Whether `a` is `b` or below it in the tree.
fn at_or_below(
  tree : @traversal.Tree,
  a : @traversal.NodeRef,
  b : @traversal.NodeRef,
) -> Bool {
  same_node(a, b) || tree.ancestors(a).iter().any(x => same_node(x, b))
}

///|
fn tree_laws(text : String) -> Bool {
  guard @traversal.Tree::new(@parser.parse_text(text)) is Some(tree) else {
    return true
  }
  let root = tree.root()
  all_nodes(root)
  .iter()
  .all(n => {
    // parent inverts children.
    let kids = n.children_with_fields()
    let parents = kids
      .iter()
      .all(x => {
        tree.parent(x.1).map(parent => same_node(parent, n)) == Some(true) &&
        tree.step(x.1) == Some(x.0)
      })
    // node_path resolves to the node.
    let path = tree
      .node_path(n)
      .bind(p => p.resolve(root))
      .map(resolved => same_node(resolved, n)) ==
      Some(true)
    // node_at at the start finds the node or a descendant.
    let at = n.span().is_empty() ||
      (tree.node_at(n.span().start) is Some(m) && at_or_below(tree, m, n))
    parents && path && at
  })
}

///|
test "law: the tree's parents, paths and node_at agree with children" {
  @quickcheck.check(
    (m : @lawkit.EditedModel) => tree_laws(m.text()),
    count=150,
    max_size=16,
    seed=9091,
  )
  @quickcheck.check(
    (t : @lawkit.SmithyText) => tree_laws(t.text()),
    count=300,
    max_size=16,
    seed=9092,
  )
}
