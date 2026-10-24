///|
let base : String =
  #|$version: "2"
  #|namespace example
  #|structure A { x: String }

///|
fn diff_of(
  old : String,
  new : String,
  old_name~ : String = "old/model.smithy",
  new_name~ : String = "new/model.smithy",
) -> Response {
  handle(
    Session::new(),
    DiffModels(seq=4, old=[(old_name, old)], new=[(new_name, new)]),
  )
}

///|
test "the same model gives no event and is not breaking" {
  guard diff_of(base, base) is Diffed(seq~, old~, new~, events~, breaking~) else {
    fail("expected Diffed")
  }
  assert_eq(seq, 4)
  assert_eq(old, [])
  assert_eq(new, [])
  assert_eq(events, Some([]))
  assert_false(breaking)
}

///|
test "an added structure gives AddedShape as a NOTE" {
  guard diff_of(base, base + "\nstructure B {}")
    is Diffed(events~, breaking~, ..) else {
    fail("expected Diffed")
  }
  let added = events.unwrap().filter(e => e.id == "AddedShape")
  assert_eq(added.length(), 1)
  assert_eq(added[0].severity, "NOTE")
  assert_eq(added[0].shape, Some("example#B"))
  assert_false(breaking)
}

///|
test "a removed structure gives RemovedShape as an ERROR and is breaking" {
  guard diff_of(base + "\nstructure B {}", base)
    is Diffed(events=Some(events), breaking~, ..) else {
    fail("expected Diffed with events")
  }
  let removed = events.filter(e => e.id == "RemovedShape")
  assert_eq(removed.length(), 1)
  assert_eq(removed[0].severity, "ERROR")
  assert_eq(removed[0].shape, Some("example#B"))
  let line = removed[0].cli_line()
  assert_true(line.has_prefix("[ERROR] example#B: Removed "))
  assert_true(line.has_suffix(" | RemovedShape"))
  assert_true(breaking)
}

///|
test "a model with errors is not compared, and its findings name its file" {
  guard diff_of(
      "$version: \"2\"\nnamespace example\nstructure A { x: Missing }", base,
    )
    is Diffed(old~, new~, events~, breaking~, ..) else {
    fail("expected Diffed")
  }
  assert_eq(events, None)
  assert_false(breaking)
  assert_true(
    old.any(d => d.severity == "ERROR" && d.file == "old/model.smithy"),
  )
  assert_eq(new, [])
}

///|
test "a model with errors on the new side names its file" {
  guard diff_of(base, "namespace example\nstructure A { x: Missing }")
    is Diffed(old~, new~, events~, ..) else {
    fail("expected Diffed")
  }
  assert_eq(events, None)
  assert_eq(old, [])
  assert_true(
    new.any(d => d.severity == "ERROR" && d.file == "new/model.smithy"),
  )
}

///|
test "cli_line escapes the line breaks of the message" {
  assert_eq(
    { id: "X", severity: "NOTE", shape: None, message: "a\r\nb\nc", }.cli_line(),
    "[NOTE] -: a\\nb\\nc | X",
  )
}

///|
fn suppressions(order : String) -> String {
  "$version: \"2.0\"\n" +
  "metadata suppressions = [{ id: \"ChangedMemberOrder\", namespace: \"example\" }]\n" +
  "namespace example\n" +
  "structure Foo {\n" +
  order +
  "}\n"
}

///|
test "a SUPPRESSED event is not in the answer" {
  guard diff_of(
      suppressions("a: String\nb: String\nc: String\n"),
      suppressions("c: String\na: String\nb: String\n"),
    )
    is Diffed(events=Some(events), ..) else {
    fail("expected Diffed with events")
  }
  assert_false(events.any(e => e.severity == "SUPPRESSED"))
  assert_false(events.any(e => e.id == "ChangedMemberOrder"))
}
