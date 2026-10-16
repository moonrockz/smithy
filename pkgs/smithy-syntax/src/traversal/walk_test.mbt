///|
let tiny : String =
  #|$version: "2"
  #|namespace a
  #|
  #|@t
  #|string S
  #|

///|
test "walk logs enter and leave and skips the children of a trait" {
  let log = []
  @traversal.walk(
    root_of(tiny),
    n => {
      log.push("+" + n.category())
      if n.category() == "trait" {
        SkipChildren
      } else {
        Continue
      }
    },
    leave=n => log.push("-" + n.category()),
  )
  assert_eq(
    log.join(" "),
    "+file +control +name -name +value -value -control +namespace +name -name -namespace +shape +trait -trait +name -name -shape -file",
  )
}

///|
test "walk stops at the first name with no more leave calls" {
  let log = []
  @traversal.walk(
    root_of(tiny),
    n => {
      log.push("+" + n.category())
      if n.category() == "name" {
        Stop
      } else {
        Continue
      }
    },
    leave=n => log.push("-" + n.category()),
  )
  assert_eq(log.join(" "), "+file +control +name")
}

///|
test "walk leaves the same node object it entered" {
  let open : Array[@traversal.NodeRef] = []
  let mut ok = true
  @traversal.walk(
    root_of(tiny),
    n => {
      open.push(n)
      Continue
    },
    leave=n => {
      guard open.pop() is Some(m) else {
        ok = false
        return
      }
      ok = ok && physical_equal(m, n)
    },
  )
  assert_true(ok)
  assert_eq(open.length(), 0)
}

///|
test "SkipChildren on the root still leaves it" {
  let log = []
  @traversal.walk(
    root_of(tiny),
    n => {
      log.push("+" + n.category())
      SkipChildren
    },
    leave=n => log.push("-" + n.category()),
  )
  assert_eq(log.join(" "), "+file -file")
}
