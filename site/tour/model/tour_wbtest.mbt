///|
fn lesson_of(
  number : Int32,
  section : String,
  files : Array[LessonFile],
  cases : Array[Case],
) -> Lesson {
  {
    dir: "0\{number}-l",
    number,
    slug: "l\{number}",
    title: "L\{number}",
    section,
    output: None,
    selector: None,
    spec: "https://smithy.io/2.0/",
    text: "# L\{number}\n",
    files,
    cases,
  }
}

///|
test "digest of one file" {
  assert_eq(
    digest([{ name: "model.smithy", text: "a", }]),
    "e81ec9371e234ce734b998b890b939d156cd3b8884c6417ddd66232e8ec1166d", // printf 'model.smithy\0a\0' | shasum -a 256
  )
}

///|
test "digest does not depend on the order of the files" {
  let a : LessonFile = { name: "a.smithy", text: "x", }
  let b : LessonFile = { name: "b.smithy", text: "y", }
  assert_eq(digest([a, b]), digest([b, a]))
  assert_true(digest([a, b]) != digest([a]))
}

///|
test "case_files replaces a starting file and adds a new one, sorted by name" {
  let lesson = lesson_of(
    1,
    "Basics",
    [{ name: "model.smithy", text: "old", }, { name: "b.smithy", text: "b", }],
    [],
  )
  let c : Case = {
    name: "c",
    files: [
      { name: "model.smithy", text: "new", },
      { name: "a.smithy", text: "a", },
    ],
    expect: { events: [], output_contains: [], },
  }
  let names = lesson.case_files(c).map(f => f.name + "=" + f.text)
  assert_eq(names, ["a.smithy=a", "b.smithy=b", "model.smithy=new"])
}

///|
test "a severity has a name, and ERROR and DANGER block the output" {
  assert_eq([Warning, Danger, Error].map(s => s.name()), [
    "WARNING", "DANGER", "ERROR",
  ])
  assert_eq(Severity::parse("DANGER"), Some(Danger))
  assert_eq(Severity::parse("NOTE"), None)
  assert_eq(Severity::parse("SUPPRESSED"), None)
  assert_eq(Severity::parse("error"), None)
  assert_eq([Warning, Danger, Error].map(s => s.blocks_output()), [
    false, true, true,
  ])
}

///|
test "an event key reads and writes id|SEVERITY|shape" {
  let key : EventKey = {
    id: "TraitTarget",
    severity: Error,
    shape: Some("ex#A$b"),
  }
  assert_eq(key.to_string(), "TraitTarget|ERROR|ex#A$b")
  assert_eq(EventKey::parse("TraitTarget|ERROR|ex#A$b"), Some(key))
  let none : EventKey = { id: "Model", severity: Error, shape: None, }
  assert_eq(none.to_string(), "Model|ERROR|-")
  assert_eq(EventKey::parse("Model|ERROR|-"), Some(none))
  for
    bad in [
      "Model|NOTE|-", "Model|ERROR", "a|ERROR|b|c", "|ERROR|-", "a|ERROR|",
    ] {
    assert_eq(EventKey::parse(bad), None)
  }
}

///|
test "the key of a finding is None when its severity is not compared" {
  assert_eq(
    EventKey::of_finding("A", "WARNING", None),
    Some({ id: "A", severity: Warning, shape: None, }),
  )
  assert_eq(EventKey::of_finding("A", "NOTE", None), None)
  assert_eq(EventKey::of_finding("A", "SUPPRESSED", Some("ex#A")), None)
}

///|
test "a case id is the lesson folder and the case name" {
  let id : CaseId = { dir: "01-hello-smithy", name: "start", }
  assert_eq(id.to_string(), "01-hello-smithy/start")
  assert_eq(CaseId::parse("01-hello-smithy/start"), Some(id))
  for bad in ["01-a", "01-a/", "/start", "01-a/b/c"] {
    assert_eq(CaseId::parse(bad), None)
  }
}

///|
test "sections groups consecutive lessons" {
  let tour : Tour = {
    lessons: [
      lesson_of(1, "Basics", [], []),
      lesson_of(2, "Basics", [], []),
      lesson_of(3, "Data", [], []),
    ],
  }
  let sections = tour.sections()
  assert_eq(sections.length(), 2)
  assert_eq(sections[0].0, "Basics")
  assert_eq(sections[0].1.map(l => l.slug), ["l1", "l2"])
  assert_eq(sections[1].0, "Data")
  assert_eq(sections[1].1.map(l => l.slug), ["l3"])
}

///|
test "find by slug" {
  let tour : Tour = { lessons: [lesson_of(1, "Basics", [], [])], }
  assert_true(tour.find("l1") is Some(_))
  assert_true(tour.find("nope") is None)
}

///|
test "neighbours of the first and the last lesson" {
  let l1 = lesson_of(1, "Basics", [], [])
  let l2 = lesson_of(2, "Basics", [], [])
  let l3 = lesson_of(3, "Basics", [], [])
  let tour : Tour = { lessons: [l1, l2, l3], }
  let (p1, n1) = tour.neighbours(l1)
  assert_true(p1 is None)
  assert_eq(n1.map(l => l.slug), Some("l2"))
  let (p2, n2) = tour.neighbours(l2)
  assert_eq(p2.map(l => l.slug), Some("l1"))
  assert_eq(n2.map(l => l.slug), Some("l3"))
  let (p3, n3) = tour.neighbours(l3)
  assert_eq(p3.map(l => l.slug), Some("l2"))
  assert_true(n3 is None)
}

///|
test "compare_code_units orders by code unit, not by length" {
  assert_eq(compare_code_units("02-more", "01-hello"), 1)
  assert_eq(compare_code_units("a", "ab"), -1)
  assert_eq(compare_code_units("b", "ab"), 1)
  assert_eq(compare_code_units("ab", "ab"), 0)
}

///|
test "case_files sorts names of different length by code unit" {
  let lesson = lesson_of(
    1,
    "Basics",
    [
      { name: "zz.smithy", text: "z", },
      { name: "a-long-name.smithy", text: "a", },
    ],
    [],
  )
  let c : Case = {
    name: "c",
    files: [],
    expect: { events: [], output_contains: [], },
  }
  assert_eq(lesson.case_files(c).map(f => f.name), [
    "a-long-name.smithy", "zz.smithy",
  ])
}

///|
test "lesson_dir and slug_of_source agree" {
  assert_eq(lesson_dir(1, "hello-smithy"), "01-hello-smithy")
  assert_eq(lesson_dir(12, "domain-modelling"), "12-domain-modelling")
  assert_eq(
    lesson_source(2, "simple-shapes"),
    "site/tour/lessons/02-simple-shapes/lesson.md",
  )
  assert_eq(
    slug_of_source("site/tour/lessons/02-simple-shapes/lesson.md"),
    Some("simple-shapes"),
  )
  assert_eq(slug_of_source("site/tour/lessons/02-simple-shapes/model.md"), None)
  assert_eq(slug_of_source("site/tour/lessons/x/lesson.md"), None)
  assert_eq(slug_of_source("site/tour/lessons/02-/lesson.md"), None)
  assert_eq(slug_of_source("site/tour/lessons/a/b/lesson.md"), None)
  assert_eq(slug_of_source("docs/lesson.md"), None)
  assert_eq(slug_of_source("site/tour/lessons/lesson.md"), None)
  assert_eq(slug_of_source("site/tour/lessons//lesson.md"), None)
}

///|
test "the page types round-trip through JSON" {
  let page : TourPage = Page({
    slug: "l2",
    title: "L2",
    section: "Basics",
    number: 2,
    total: 3,
    output: Some(@samples.Output::JsonSchema),
    selector: None,
    spec: "https://smithy.io/2.0/",
    files: [{ name: "model.smithy", text: "namespace a\n", }],
    digest: "d",
    previous: Some({ slug: "l1", title: "L1", }),
    next: None,
    worker: "/smithy/playground/worker.js?v=x",
    storage_key: "smithy-tour:next:l2",
    playground: Some("/smithy/playground/"),
  })
  let contents : TourPage = Contents({
    sections: [("Basics", [{ slug: "l1", title: "L1", }])],
  })
  for p in [page, contents] {
    let back : TourPage = @json.from_json(p.to_json())
    assert_eq(back, p)
  }
}

///|
test "output_text gives one file as it is" {
  assert_eq(output_text([("model.json", "{}\n")]), "{}\n")
}

///|
test "output_text joins two files with a line break" {
  assert_eq(output_text([("a.smithy", "A\n"), ("b.smithy", "B\n")]), "A\n\nB\n")
  assert_eq(output_text([]), "")
}
