///|
/// Random path steps: a field ("a" or "b") and an index below 4.
struct Steps(Array[(Bool, UInt32)]) derive(Debug)

///|
impl @quickcheck.Arbitrary for Steps with fn arbitrary(size, rs) {
  Steps(Array::makei(size, _ => (rs.next_uint() % 2 == 0, rs.next_uint() % 4)))
}

///|
impl @quickcheck.Shrink for Steps

///|
fn steps_of(xs : ArrayView[(Bool, UInt32)]) -> Array[@traversal.PathStep] {
  xs
  .iter()
  .map(x => {
    let step : @traversal.PathStep = {
      field: if x.0 {
        "a"
      } else {
        "b"
      },
      index: x.1.reinterpret_as_int(),
    }
    step
  })
  .to_array()
}

///|
test "law: a child path's parent is the path, and its steps grow by the new step" {
  @quickcheck.check(
    (s : Steps) => {
      let Steps(xs) = s
      let mut path = @traversal.NodePath::root()
      let built : Array[@traversal.PathStep] = []
      steps_of(xs)
      .iter()
      .all(step => {
        let next = path.child(step.field, step.index)
        built.push(step)
        let ok = next.parent() == Some(path) &&
          next.last() == Some(step) &&
          next.depth() == path.depth() + 1 &&
          next.steps() == built &&
          next.to_string() == built.map(t => "\{t.field}[\{t.index}]").join(".")
        path = next
        ok
      })
    },
    count=100,
    max_size=24,
    seed=6061,
  )
}

///|
test "law: from_steps builds the path whose steps it gets" {
  @quickcheck.check(
    (s : Steps) => {
      let Steps(xs) = s
      let steps = steps_of(xs)
      let mut built = @traversal.NodePath::root()
      for step in steps {
        built = built.child(step.field, step.index)
      }
      let path = @traversal.NodePath::from_steps(steps)
      path.steps() == steps && path == built && path.depth() == steps.length()
    },
    count=100,
    max_size=24,
    seed=6062,
  )
}

///|
test "law: append puts the steps of its argument after its own" {
  @quickcheck.check(
    (s : Steps) => {
      let Steps(xs) = s
      let third = xs.length() / 3
      let a = steps_of(xs[:third])
      let b = steps_of(xs[third:2 * third])
      let c = steps_of(xs[2 * third:])
      let pa = @traversal.NodePath::from_steps(a)
      let pb = @traversal.NodePath::from_steps(b)
      let pc = @traversal.NodePath::from_steps(c)
      let root = @traversal.NodePath::root()
      pa.append(pb).steps() == [..a, ..b] &&
      pa.append(pb).depth() == a.length() + b.length() &&
      pa.append(root) == pa &&
      root.append(pa) == pa &&
      pa.append(pb).append(pc) == pa.append(pb.append(pc)) &&
      pa.append(root.child("a", 1)) == pa.child("a", 1)
    },
    count=100,
    max_size=24,
    seed=6063,
  )
}

///|
fn paths_resolve(text : String) -> Bool {
  guard maybe_root(text) is Some(root) else { return true }
  // Every node's path, built by an explicit stack, resolves back to it.
  let stack = [(root, @traversal.NodePath::root())]
  while stack.pop() is Some((n, path)) {
    guard path.resolve(root) is Some(m) && same_node(m, n) else { return false }
    for x in n.children_with_fields() {
      stack.push((x.1, path.child(x.0.field, x.0.index)))
    }
  }
  true
}

///|
test "law: every node's path resolves to it from the root" {
  @quickcheck.check(
    (m : @lawkit.EditedModel) => paths_resolve(m.text()),
    count=200,
    max_size=16,
    seed=6064,
  )
  @quickcheck.check(
    (t : @lawkit.SmithyText) => paths_resolve(t.text()),
    count=300,
    max_size=16,
    seed=6065,
  )
}
