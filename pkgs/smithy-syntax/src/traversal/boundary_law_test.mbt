///|
/// Whether every child lies inside its parent's span and the children start
/// in order, at every node.
fn nested_in_order(text : String) -> Bool {
  guard maybe_root(text) is Some(root) else { return true }
  all_nodes(root)
  .iter()
  .all(n => {
    let p = n.span()
    let cs = n.children()
    cs
    .iter()
    .all(c => {
      let s = c.span()
      p.start <= s.start && s.end() <= p.end()
    }) &&
    (1)
    .until(cs.length())
    .all(i => cs[i - 1].span().start <= cs[i].span().start)
  })
}

///|
test "every child lies inside its parent for the fixed models" {
  assert_true(nested_in_order(every_form))
  assert_true(nested_in_order(documented))
  assert_true(nested_in_order(inline_docs))
  assert_true(nested_in_order(@lawkit.small_model()))
}

///|
test "law: every child lies inside its parent and children are in source order" {
  @quickcheck.check(
    (m : @lawkit.EditedModel) => nested_in_order(m.text()),
    count=300,
    max_size=16,
    seed=4043,
  )
  @quickcheck.check(
    (t : @lawkit.SmithyText) => nested_in_order(t.text()),
    count=400,
    max_size=16,
    seed=4044,
  )
}
