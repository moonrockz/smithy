///|
fn outline(n : @traversal.NodeRef, rs : ArrayView[String]) -> String {
  if rs.length() == 0 {
    n.kind()
  } else {
    n.kind() + "(" + rs.iter().join(",") + ")"
  }
}

///|
let two_members : String =
  #|namespace a
  #|
  #|structure Foo {
  #|    a: String
  #|    b: Integer
  #|}
  #|

///|
test "fold counts the nodes" {
  let root = root_of(tiny)
  let n = @traversal.fold(root, 0, (a, _) => (a + 1, Continue))
  assert_eq(n, 10)
  assert_eq(n, all_nodes(root).length())
}

///|
test "fold threads the accumulator through enter and leave" {
  let depths = @traversal.fold(
    root_of(tiny),
    (0, 0),
    (a, _) => ((a.0 + 1, if a.0 + 1 > a.1 { a.0 + 1 } else { a.1 }), Continue),
    leave=(a, _) => (a.0 - 1, a.1),
  )
  assert_eq(depths, (0, 4))
}

///|
test "reduce builds the shape outline bottom up" {
  assert_eq(
    @traversal.reduce(root_of(two_members), outline),
    "file(namespace(name),structure(name,member(name,shape_id),member(name,shape_id)))",
  )
}

///|
test "reduce_pruned with SkipChildren calls f with no results" {
  let got = @traversal.reduce_pruned(
    root_of(two_members),
    n => if n.category() == "member" { SkipChildren } else { Continue },
    outline,
  )
  assert_eq(got, Some("file(namespace(name),structure(name,member,member))"))
}

///|
test "reduce_pruned Stop gives None and no more calls" {
  let calls = []
  let got = @traversal.reduce_pruned(
    root_of(two_members),
    n => if n.category() == "member" { Stop } else { Continue },
    (n, rs) => {
      calls.push(n.kind())
      outline(n, rs)
    },
  )
  assert_eq(got, None)
  assert_eq(calls, ["name", "namespace", "name"])
}

///|
test "a 95-deep array value walks, folds and reduces" {
  let root = root_of(deep_value(95))
  let mut arrays = 0
  @traversal.walk(root, n => {
    if n.kind() == "array" {
      arrays = arrays + 1
    }
    Continue
  })
  assert_eq(arrays, 95)
  let depth = @traversal.reduce(root, (n, rs) => {
    let deepest = rs.iter().fold(init=0, (a, b) => if b > a { b } else { a })
    if n.kind() == "array" {
      deepest + 1
    } else {
      deepest
    }
  })
  assert_eq(depth, 95)
  assert_eq(
    @traversal.fold(root, 0, (a, _) => (a + 1, Continue)),
    all_nodes(root).length(),
  )
}
