///|
fn diag(code : String, line : Int32, message : String) -> Diagnostic {
  {
    severity: "WARNING",
    code,
    message,
    file: "model.smithy",
    start_line: line,
    start_column: 1,
    end_line: line,
    end_column: 13,
    shape: Some("a#Payload"),
  }
}

///|
test "group: repeats at one place join the row of the first, in list order" {
  let a1 = diag("NoBlob", 9, "attached to `a#Out1`")
  let b = diag("Ranged", 12, "range")
  let a2 = diag("NoBlob", 9, "attached to `a#Out2`")
  let a3 = diag("NoBlob", 9, "attached to `a#Out3`")
  let groups = group_diagnostics([a1, b, a2, a3], true)
  assert_eq(groups, [
    { first: a1, repeats: [a2, a3], },
    { first: b, repeats: [], },
  ])
  assert_eq(groups.map(g => g.size()), [3, 1])
}

///|
test "group: another code, severity or place is not a repeat" {
  let a = diag("NoBlob", 9, "x")
  let other_code = diag("Other", 9, "x")
  let other_line = diag("NoBlob", 10, "x")
  let other_severity = { ..a, severity: "ERROR", }
  let other_column = { ..a, start_column: 2, }
  let groups = group_diagnostics(
    [a, other_code, other_line, other_severity, other_column],
    true,
  )
  assert_eq(groups.length(), 5)
}

///|
test "group: without grouping, each diagnostic has its own row" {
  let a1 = diag("NoBlob", 9, "one")
  let a2 = diag("NoBlob", 9, "two")
  assert_eq(group_diagnostics([a1, a2], false), [
    { first: a1, repeats: [], },
    { first: a2, repeats: [], },
  ])
  assert_eq(group_diagnostics([], true), [])
}

///|
test "message: the names between backticks are names, the rest is text" {
  assert_eq(
    message_parts(
      "Trait `range` cannot be applied to `a#Rec$b`. This trait may only be applied to shapes that match",
    ),
    [
      Text("Trait "),
      Name("range"),
      Text(" cannot be applied to "),
      Name("a#Rec$b"),
      Text(". This trait may only be applied to shapes that match"),
    ],
  )
  assert_eq(message_parts("`a#B`"), [Name("a#B")])
  assert_eq(message_parts("No names here."), [Text("No names here.")])
  assert_eq(message_parts(""), [])
}

///|
test "message: a backtick without its pair and an empty pair stay text" {
  assert_eq(message_parts("Use ` here"), [Text("Use ` here")])
  assert_eq(message_parts("`a` and ` b"), [Name("a"), Text(" and ` b")])
  assert_eq(message_parts("an `` empty pair"), [Text("an `` empty pair")])
}

///|
test "message: shape IDs without backticks are names too" {
  assert_eq(
    message_parts(
      "I could not resolve shape example.chat#Intger, referenced by example.chat#PostMessageOutput$count.",
    ),
    [
      Text("I could not resolve shape "),
      Name("example.chat#Intger"),
      Text(", referenced by "),
      Name("example.chat#PostMessageOutput$count"),
      Text("."),
    ],
  )
  assert_eq(message_parts("smithy.api#String"), [Name("smithy.api#String")])
  assert_eq(message_parts("(a#B)"), [Text("("), Name("a#B"), Text(")")])
}

///|
test "message: a # that is not in a shape ID stays text" {
  assert_eq(message_parts("Use # here"), [Text("Use # here")])
  assert_eq(message_parts("a# and #b and 1a#B"), [Text("a# and #b and 1a#B")])
  assert_eq(message_parts("ends with a#B$"), [
    Text("ends with "),
    Name("a#B"),
    Text("$"),
  ])
}
