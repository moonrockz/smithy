///|
fn children_match_steps(text : String) -> Bool {
  guard maybe_root(text) is Some(root) else { return true }
  all_nodes(root)
  .iter()
  .all(n => {
    let steps = n.children_with_fields()
    n.children() == steps.map(x => x.1) &&
    steps
    .iter()
    .all(x => {
      let f = n.field(x.0.field)
      x.0.index < f.length() && f[x.0.index] == x.1
    })
  })
}

///|
test "law: children is children_with_fields without the steps, and each step names its child" {
  @quickcheck.check(
    (m : @lawkit.EditedModel) => children_match_steps(m.text()),
    count=200,
    max_size=16,
    seed=4041,
  )
  @quickcheck.check(
    (t : @lawkit.SmithyText) => children_match_steps(t.text()),
    count=300,
    max_size=16,
    seed=4042,
  )
}
