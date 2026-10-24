///|
fn read(name : String) -> Result[@model.Tour, String] {
  @source.read_tour("tour/source/testdata/\{name}", repo="..")
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

///|
test "a case that expects a blocked output" {
  let tour = match read("blocked") {
    Ok(t) => t
    Err(msg) => fail(msg)
  }
  let cases = tour.lessons[0].cases
  assert_eq(cases.map(c => c.name), ["start", "b"])
  assert_eq(cases[0].expect.blocked, None)
  assert_eq(cases[1].expect.blocked, Some("x"))
}

///|
test "blocked together with output_contains" {
  expect_err("blocked-and-contains", [
    "01-a/cases/b", "blocked", "output_contains",
  ])
}

///|
test "blocked in a lesson without an output" {
  expect_err("blocked-no-output", ["01-a/cases/b", "needs a lesson output"])
}

///|
test "blocked with an ERROR event" {
  expect_err("blocked-with-error", ["01-a/cases/b", "blocked", "ERROR"])
}

///|
test "a spec that is neither a smithy.io URL nor a docs page" {
  expect_err("bad-spec", [
    "01-a: \"spec\" must be a smithy.io URL or the repository path of a docs page, not \"https://example.com/x\"",
  ])
}

///|
test "a spec that is the repository path of a docs page" {
  match read("docs-spec") {
    Ok(tour) =>
      assert_eq(tour.lessons[0].spec, "pkgs/smithy-openrpc/README.mbt.md")
    Err(msg) => fail(msg)
  }
}

///|
fn expect_bad_spec(name : String, spec : String) -> Unit raise {
  expect_err(name, [
    "01-a: \"spec\" must be a smithy.io URL or the repository path of a docs page, not \"\{spec}\"",
  ])
}

///|
test "a spec that is the path of a file that the site does not publish" {
  expect_bad_spec(
    "unpublished-spec", "site/tour/lessons/01-hello-smithy/lesson.md",
  )
  expect_bad_spec("working-doc-spec", "docs/superpowers/plan.md")
}

///|
test "an include of the CLI block becomes a tabs fence" {
  let tour = match read("include-ok") {
    Ok(t) => t
    Err(msg) => fail(msg)
  }
  let text = tour.lessons[0].text
  assert_true(text.contains("```tabs"))
  assert_false(text.contains("```include"))
}

///|
test "an include of a missing file" {
  expect_err("include-missing-file", [
    "01-", "lesson.md", "I could not find the file apps/smithy/NOPE.md",
  ])
}

///|
test "an include of a missing marker" {
  expect_err("include-missing-marker", [
    "lesson.md", "<!-- tour:start no-such-block -->",
  ])
}

///|
test "a hand-written console block" {
  expect_err("hand-written", ["lesson.md", "`console`"])
}

///|
test "an include block that the reader cannot expand" {
  expect_err("include-unexpanded", [
    "01-hello/lesson.md", "I found an include block that I cannot expand",
  ])
}

///|
test "a value lesson reads its setup and the findings of a case" {
  let tour = match read("value-ok") {
    Ok(t) => t
    Err(msg) => fail(msg)
  }
  let lesson = tour.lessons[0]
  assert_eq(
    lesson.engine,
    Value({
      file: "order.json",
      shape: "example#Order",
      options: { unknown_members: Ignore, member_names: Smithy, },
    }),
  )
  assert_eq(lesson.output, None)
  assert_eq(lesson.files.map(f => f.name), ["model.smithy", "order.json"])
  assert_eq(lesson.cases[0].expect.findings, [])
  assert_eq(lesson.cases[1].expect.findings, [
    "Range|error|/quantity|example#Order", "InvalidJson|stopped|-", "Hint|advisory||example#Order",
    "InvalidTarget|stopped|--shape",
  ])
  assert_eq(lesson.cases[1].expect.output_contains, ["Range"])
  let merged = lesson.case_files(lesson.cases[1])
  assert_eq(merged.map(f => f.text), [
    "namespace example\nstructure Order { quantity: Integer }\n", "{\"quantity\": 0}\n",
  ])
}

///|
test "a value lesson that names a missing file" {
  expect_err("value-bad-file", ["01-a", "missing.json"])
}

///|
test "a lesson with an output and a value" {
  expect_err("value-and-output", ["01-a", "at most one of output, value"])
}

///|
test "a value setup with an unknown key" {
  expect_err("value-unknown-key", ["01-a", "colour"])
}

///|
test "a value setup with an unknown option" {
  expect_err("value-bad-option", ["01-a", "member_names", "camel"])
}

///|
test "a value file must end with .json" {
  expect_err("value-file-not-json", ["01-a", "order.smithy", ".json"])
}

///|
test "a value lesson case needs findings" {
  expect_err("value-no-findings", ["01-a/cases/start", "findings"])
}

///|
test "a finding key has the form of a found or a stopped finding" {
  expect_err("bad-finding-key", ["01-a/cases/start", "Range|error|a#B"])
}

///|
test "findings are for a value or message lesson" {
  expect_err("findings-in-model-lesson", [
    "01-a/cases/start", "\"findings\" is for a value or message lesson",
  ])
}

///|
test "diff is for a diff lesson" {
  expect_err("diff-in-model-lesson", [
    "01-a/cases/start", "\"diff\" is for a diff lesson",
  ])
}

///|
test "a model file must end with .smithy" {
  expect_err("json-model-file", ["01-a/files/extra.json", ".smithy"])
}

///|
test "a case cannot add a json file that no setup names" {
  expect_err("value-case-adds-json", [
    "01-a/cases/start/files/other.json", ".smithy",
  ])
}

///|
test "a static lesson has no files and no cases" {
  let tour = match read("static-ok") {
    Ok(t) => t
    Err(msg) => fail(msg)
  }
  let lesson = tour.lessons[0]
  assert_eq(lesson.engine, Static)
  assert_eq(lesson.extension, true)
  assert_eq(lesson.files, [])
  assert_eq(lesson.cases.length(), 0)
  assert_eq(lesson.output, None)
}

///|
test "a static lesson with files or cases" {
  expect_err("static-with-files", [
    "01-a", "a static lesson has no files/ and no cases/", "its blocks come from include blocks",
  ])
  expect_err("static-with-cases", [
    "01-a", "a static lesson has no files/ and no cases/",
  ])
}

///|
test "a static lesson with an output" {
  expect_err("static-with-output", ["01-a", "static", "output"])
}

///|
test "extension is for a static lesson" {
  expect_err("extension-not-static", ["01-a", "\"extension\"", "static"])
}

///|
test "a Selector lesson keeps its query in a file" {
  let tour = match read("query-ok") {
    Ok(t) => t
    Err(msg) => fail(msg)
  }
  let lesson = tour.lessons[0]
  assert_eq(lesson.files.map(f => f.name), ["model.smithy", "query.selector"])
  let merged = lesson.case_files(lesson.cases[1])
  assert_eq(@model.query_of(merged, fixed=lesson.selector), Some("operation\n"))
}

///|
test "a query file needs the output Selector" {
  expect_err("query-no-output", ["01-a", "needs the output Selector"])
}

///|
test "a query file and a selector together are an error" {
  expect_err("query-and-selector", ["01-a", "both"])
}

///|
test "the output Selector needs a query" {
  expect_err("query-missing", ["01-a", "needs a selector"])
}

///|
test "a lesson has at most one query file" {
  expect_err("query-two", ["01-a", "more than one"])
}

///|
test "a case cannot add a query file" {
  expect_err("query-case-adds", ["01-a/cases/more", "other.selector"])
}
