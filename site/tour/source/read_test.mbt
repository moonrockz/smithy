///|
fn read(name : String) -> Result[@model.Tour, String] {
  @source.read_tour("tour/source/testdata/\{name}")
}

///|
fn expect_err(name : String, parts : Array[String]) -> Unit raise {
  match read(name) {
    Ok(_) => fail("I expected an error for \{name}, but the tour was read")
    Err(msg) =>
      for part in parts {
        if !msg.contains(part) {
          fail("The error \"\{msg}\" does not contain \"\{part}\"")
        }
      }
  }
}

///|
test "valid tree of 2 lessons" {
  let tour = match read("valid") {
    Ok(t) => t
    Err(msg) => fail(msg)
  }
  assert_eq(tour.lessons.map(l => l.dir), ["01-hello", "02-more"])
  let first = tour.lessons[0]
  assert_eq(first.number, 1)
  assert_eq(first.slug, "hello")
  assert_eq(first.output, Some(@samples.Output::JsonAst))
  assert_eq(tour.lessons[1].output, None)
  // A name that starts with `.` is not part of the lesson.
  assert_eq(first.files.map(f => f.name), ["model.smithy"])
  assert_eq(first.cases.map(c => c.name), ["start", "bad-name"])
  assert_eq(first.cases[1].expect.events, [
    { id: "TraitTarget", severity: Error, shape: Some("example#A$b"), },
  ])
  assert_eq(first.cases[1].expect.output_contains, ["x"])
  let merged = first.case_files(first.cases[1])
  assert_eq(merged.map(f => f.text), ["namespace example\nstructure A {}\n"])
}

///|
test "no cases/start" {
  expect_err("no-start", ["01-a", "cases/start"])
}

///|
test "a case without expect.json" {
  expect_err("no-expect", ["01-a/cases/start", "expect.json"])
}

///|
test "two lessons with the same slug" {
  expect_err("dup-slug", ["01-same", "02-same"])
}

///|
test "a gap in the numbers" {
  expect_err("gap", ["03-c", "2"])
}

///|
test "unknown output name" {
  expect_err("bad-output", ["01-a", "Nope"])
}

///|
test "lesson.md whose first line is not the title" {
  expect_err("bad-title", ["01-a/lesson.md", "# A"])
}

///|
test "a severity outside WARNING, DANGER and ERROR" {
  expect_err("bad-severity", ["01-a/cases/start", "NOTE"])
}

///|
test "a folder name that does not end with the slug" {
  expect_err("bad-dir", ["01-a", "01-b"])
}

///|
test "two lessons with the same number" {
  expect_err("same-number", ["01-a and 01-b", "number 1"])
}

///|
test "an unknown key in lesson.json" {
  expect_err("unknown-lesson-key", ["01-a/lesson.json", "\"outptu\""])
}

///|
test "an unknown key in expect.json" {
  expect_err("unknown-expect-key", [
    "01-a/cases/start/expect.json", "\"output_contain\"",
  ])
}

///|
test "an empty needle matches every output" {
  expect_err("empty-needle", ["01-a/cases/start", "empty"])
}

///|
test "a selector for an output that is not Selector" {
  expect_err("selector-without-output", ["01-a", "\"selector\"", "Selector"])
}

///|
test "a sub-folder of the starting files" {
  expect_err("files-sub-folder", ["01-a/files/more", "folder"])
}

///|
test "a sub-folder of the files of a case" {
  expect_err("case-sub-folder", ["01-a/cases/start/files/more", "folder"])
}

///|
test "a lesson file whose name does not end in .smithy" {
  expect_err("not-smithy", ["01-a/files/model.json", ".smithy"])
}
