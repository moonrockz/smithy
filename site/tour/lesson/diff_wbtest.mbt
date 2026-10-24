///|
test "changed_lines: one changed line" {
  assert_eq(changed_lines("a\nb\nc", "a\nB\nc"), [2])
}

///|
test "changed_lines: an added line" {
  assert_eq(changed_lines("a\nc", "a\nb\nc"), [2])
}

///|
test "changed_lines: nothing before means nothing is highlighted" {
  assert_eq(changed_lines("", "a\nb"), [])
}

///|
test "changed_lines: same text" {
  assert_eq(changed_lines("a\nb", "a\nb"), [])
}

///|
test "changed_lines: a removed line highlights nothing in the new text" {
  assert_eq(changed_lines("a\nb\nc", "a\nc"), [])
}

///|
test "changed_lines: changes at the start, in the middle and at the end" {
  assert_eq(changed_lines("a\nb\nc\nd\ne", "A\nb\nC\nd\nE\nf"), [1, 3, 5, 6])
}

///|
test "changed_lines: a repeated line matches once" {
  assert_eq(changed_lines("x\ny", "x\nx\ny"), [2])
}

///|
test "changed_lines: an output of more than 2000 lines is not highlighted" {
  let before = Array::makei(2001, i => "line \{i}")
  let after = before.copy()
  after[1000] = "changed"
  assert_eq(changed_lines(before.join("\n"), after.join("\n")), [])
  // 2000 lines is still in the bound.
  let before = Array::makei(2000, i => "line \{i}")
  let after = before.copy()
  after[1000] = "changed"
  assert_eq(changed_lines(before.join("\n"), after.join("\n")), [1001])
}
