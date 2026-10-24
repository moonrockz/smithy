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
  assert_eq(first.cases.map(c => c.name), ["start", "bad-name"])
  assert_eq(first.cases[1].expect.events, ["TraitTarget|ERROR|example#A$b"])
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
  expect_err("dup-slug", ["01-a", "02-b"])
}

///|
test "a gap in the numbers" {
  expect_err("gap", ["03-c", "2"])
}

///|
test "unknown output name" {
  expect_err("bad-output", ["Nope"])
}

///|
test "lesson.md whose first line is not the title" {
  expect_err("bad-title", ["01-a/lesson.md", "# A"])
}

///|
test "a severity outside WARNING, DANGER and ERROR" {
  expect_err("bad-severity", ["NOTE"])
}
