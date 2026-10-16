///|
let three_shapes : String =
  #|namespace a
  #|
  #|string A
  #|
  #|string B
  #|
  #|structure C {
  #|    x: A
  #|}
  #|

///|
test "a start node's path is empty" {
  let root = @traversal.NodePath::root()
  assert_eq(root.depth(), 0)
  assert_eq(root.to_string(), "")
  assert_eq(root.last(), None)
  assert_eq(root.parent(), None)
  assert_true(root.resolve(root_of(tiny)) is Some(File(_, _)))
}

///|
test "a member target's path reads like the JSON AST" {
  let path = @traversal.NodePath::root()
    .child("shapes", 2)
    .child("members", 0)
    .child("target", 0)
  assert_eq(path.to_string(), "shapes[2].members[0].target[0]")
  guard path.resolve(root_of(three_shapes)) is Some(ShapeIdRef(id)) else {
    fail("no target")
  }
  assert_eq(id.value.name, "A")
}

///|
test "a child path does not change its parent" {
  let parent = @traversal.NodePath::root().child("shapes", 0)
  let a = parent.child("members", 0)
  let b = parent.child("traits", 0)
  let steps = parent.steps()
  steps.clear()
  assert_eq(parent.to_string(), "shapes[0]")
  assert_eq(a.to_string(), "shapes[0].members[0]")
  assert_eq(b.to_string(), "shapes[0].traits[0]")
}

///|
test "a path resolves to None where a step does not exist" {
  let root = root_of(three_shapes)
  assert_eq(@traversal.NodePath::root().child("shapes", 3).resolve(root), None)
  assert_eq(@traversal.NodePath::root().child("nope", 0).resolve(root), None)
}

///|
test "a path's debug form lists its steps from the start node" {
  let path = @traversal.NodePath::root().child("shapes", 0).child("members", 1)
  debug_inspect(
    path,
    content="{ steps: [{ field: \"shapes\", index: 0 }, { field: \"members\", index: 1 }] }",
  )
  debug_inspect(@traversal.NodePath::root(), content="{ steps: [] }")
}

///|
test "an appended path resolves from the node where the first part ends" {
  let root = root_of(three_shapes)
  let to_member = @traversal.NodePath::from_steps([
    { field: "shapes", index: 2, },
    { field: "members", index: 0, },
  ])
  let to_target = @traversal.NodePath::root().child("target", 0)
  let whole = to_member.append(to_target)
  assert_eq(whole.to_string(), "shapes[2].members[0].target[0]")
  assert_eq(
    whole.resolve(root),
    to_member.resolve(root).bind(n => to_target.resolve(n)),
  )
}
