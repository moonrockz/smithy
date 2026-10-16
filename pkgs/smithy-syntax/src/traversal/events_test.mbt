///|
fn short(e : @traversal.Event) -> String {
  match e {
    Enter(e) => "+\{e.category}:\{e.field.unwrap_or("-")}"
    Leave(e) => "-\{e.node.category()}"
  }
}

///|
test "an event reader gives walk's events with fields" {
  let r = @traversal.EventReader::new(root_of(tiny))
  let got = r.iter().map(short).to_array().join(" ")
  assert_eq(
    got, "+file:- +control:control +name:key -name +value:value -value -control +namespace:namespace +name:name -name -namespace +shape:shapes +trait:traits +shape_id:id -shape_id -trait +name:name -name -shape -file",
  )
}

///|
test "skip_children right after an Enter makes the next event its Leave" {
  let r = @traversal.EventReader::new(root_of(tiny))
  assert_true(r.next() is Some(Enter(_)))
  assert_true(r.next() is Some(Enter({ category: "control", .. })))
  r.skip_children()
  assert_true(r.next() is Some(Leave({ node: Control(_), .. })))
  assert_true(r.next() is Some(Enter({ category: "namespace", .. })))
}

///|
test "skip_children elsewhere does nothing" {
  let a = @traversal.EventReader::new(root_of(tiny))
  let b = @traversal.EventReader::new(root_of(tiny))
  // Read past the first name's Leave, then skip: nothing is pending.
  for _ in 0..<4 {
    ignore(a.next())
    ignore(b.next())
  }
  a.skip_children()
  assert_eq(a.iter().map(short).to_array(), b.iter().map(short).to_array())
}

///|
test "a finished reader returns None every time" {
  let r = @traversal.EventReader::new(root_of(tiny))
  while r.next() is Some(_) {
    ()
  }
  assert_true(r.next() is None)
  assert_true(r.next() is None)
}

///|
test "two readers over one tree do not affect each other" {
  let root = root_of(tiny)
  let a = @traversal.EventReader::new(root)
  let b = @traversal.EventReader::new(root)
  let xs = []
  let ys = []
  while true {
    let x = a.next()
    let y = b.next()
    if x is Some(e) {
      xs.push(short(e))
    }
    if y is Some(e) {
      ys.push(short(e))
    }
    if x is None && y is None {
      break
    }
  }
  assert_eq(xs, ys)
  assert_eq(xs, @traversal.EventReader::new(root).iter().map(short).to_array())
}

///|
test "events carry the depth and path of their node" {
  let r = @traversal.EventReader::new(root_of(tiny))
  let got = []
  for e in r.iter() {
    if e is Enter(e) && e.category == "shape_id" {
      got.push("\{e.depth} \{e.path}")
    }
  }
  assert_eq(got, ["3 shapes[0].traits[0].id[0]"])
}

///|
test "a documented shape's Enter starts at its first doc comment" {
  let r = @traversal.EventReader::new(root_of(documented))
  for e in r.iter() {
    if e is Enter(e) && e.category == "shape" {
      assert_eq(e.start, off(documented, "/// Doc"))
      return
    }
  }
  fail("no shape event")
}

///|
test "iter continues where next stopped, and ends after the root's Leave" {
  let r = @traversal.EventReader::new(root_of(tiny))
  ignore(r.next())
  ignore(r.next())
  let rest = r.iter().map(short).to_array()
  assert_eq(rest[0], "+name:key")
  assert_eq(rest[rest.length() - 1], "-file")
  assert_true(r.next() is None)
}

///|
test "an event reader handles a 95-deep value" {
  let root = root_of(deep_value(95))
  let n = @traversal.EventReader::new(root).iter().count()
  assert_eq(n, 2 * all_nodes(root).length())
}
