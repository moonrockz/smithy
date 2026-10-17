///|
fn walk_agrees(text : String, p : Policy) -> Bool {
  guard maybe_root(text) is Some(root) else { return true }
  let p = policy_for(root, p)
  walk_events(root, p) == model(root, p)
}

///|
test "law: walk agrees with the recursive model for every Control policy" {
  @quickcheck.check(
    (input : (@lawkit.EditedModel, Policy)) => {
      walk_agrees(input.0.text(), input.1)
    },
    count=200,
    max_size=16,
    seed=5051,
  )
  @quickcheck.check(
    (input : (@lawkit.SmithyText, Policy)) => {
      walk_agrees(input.0.text(), input.1)
    },
    count=300,
    max_size=16,
    seed=5052,
  )
}

///|
fn continue_is_preorder(text : String) -> Bool {
  guard maybe_root(text) is Some(root) else { return true }
  let entered = []
  @traversal.walk(root, n => {
    entered.push(tag(n))
    Continue
  })
  entered == all_nodes(root).map(tag)
}

///|
test "law: with Continue, walk enters in children() pre-order" {
  @quickcheck.check(
    (m : @lawkit.EditedModel) => continue_is_preorder(m.text()),
    count=200,
    max_size=16,
    seed=5053,
  )
  @quickcheck.check(
    (t : @lawkit.SmithyText) => continue_is_preorder(t.text()),
    count=300,
    max_size=16,
    seed=5054,
  )
}
