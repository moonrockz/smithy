///|
fn fold_events(root : @traversal.NodeRef, p : Policy) -> Array[String] {
  @traversal.fold(
    root,
    [],
    (events, n) => {
      let k = events.filter(e => e.has_prefix("+")).length()
      events.push("+" + tag(n))
      (events, decide(p, k))
    },
    leave=(events, n) => {
      events.push("-" + tag(n))
      events
    },
  )
}

///|
/// The leave tags of a walk under `p`, and whether a `Stop` ended it.
fn walk_leaves(root : @traversal.NodeRef, p : Policy) -> (Array[String], Bool) {
  let leaves = []
  let mut k = 0
  let mut stopped = false
  @traversal.walk(
    root,
    _ => {
      let c = decide(p, k)
      k = k + 1
      if c is Stop {
        stopped = true
      }
      c
    },
    leave=n => leaves.push(tag(n)),
  )
  (leaves, stopped)
}

///|
fn fold_laws(text : String, p : Policy) -> Bool {
  guard maybe_root(text) is Some(root) else { return true }
  // fold's enter and leave order is walk's.
  let p = policy_for(root, p)
  let same_order = fold_events(root, p) == walk_events(root, p)
  // reduce calls f once per node, in walk's leave order.
  let calls = []
  let count = @traversal.reduce(root, (n, rs) => {
    calls.push(tag(n))
    1 + rs.iter().fold(init=0, (a, b) => a + b)
  })
  let (all_leaves, _) = walk_leaves(root, Policy([Continue], None))
  let reduce_order = calls == all_leaves
  // a counting reduce equals a counting fold.
  let counts = count == @traversal.fold(root, 0, (a, _) => (a + 1, Continue))
  // reduce_pruned with Continue throughout is Some of reduce.
  let plain = @traversal.reduce(root, outline)
  let pruned_all = @traversal.reduce_pruned(root, _ => Continue, outline) ==
    Some(plain)
  // reduce_pruned finishes the nodes walk leaves under the same policy.
  let pruned_calls = []
  let mut k = 0
  let result = @traversal.reduce_pruned(
    root,
    _ => {
      k = k + 1
      decide(p, k - 1)
    },
    (n, _) => {
      pruned_calls.push(tag(n))
      0
    },
  )
  let (leaves, stopped) = walk_leaves(root, p)
  let pruned = pruned_calls == leaves && (result is None) == stopped
  same_order && reduce_order && counts && pruned_all && pruned
}

///|
test "law: fold, reduce and reduce_pruned agree with walk" {
  @quickcheck.check(
    (input : (@lawkit.EditedModel, Policy)) => {
      fold_laws(input.0.text(), input.1)
    },
    count=200,
    max_size=16,
    seed=5055,
  )
  @quickcheck.check(
    (input : (@lawkit.SmithyText, Policy)) => fold_laws(input.0.text(), input.1),
    count=300,
    max_size=16,
    seed=5056,
  )
}
