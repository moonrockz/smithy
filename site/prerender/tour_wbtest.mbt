///|
fn fixture_lesson(
  number : Int32,
  section : String,
  files : Array[@model.LessonFile],
) -> @model.Lesson {
  let slug = "l\{number}"
  {
    dir: @model.lesson_dir(number, slug),
    number,
    slug,
    title: "Lesson \{number}",
    section,
    output: Some(@samples.Output::JsonAst),
    selector: None,
    spec: "https://smithy.io/2.0/spec/idl.html",
    text: "# Lesson \{number}\n\nText.\n",
    files,
    cases: [],
  }
}

///|
fn fixture_tour() -> @model.Tour {
  let one : Array[@model.LessonFile] = [
    { name: "model.smithy", text: "namespace a\n", },
  ]
  let two : Array[@model.LessonFile] = [
    { name: "a.smithy", text: "namespace a\n", },
    { name: "b.smithy", text: "namespace b\n", },
  ]
  {
    lessons: [
      fixture_lesson(1, "Basics", one),
      fixture_lesson(2, "Basics", one),
      fixture_lesson(3, "Data modelling", two),
    ],
  }
}

///|
fn fixture_config(channel : String) -> @data.SiteConfig {
  config_of(
    parse_args([
      "prerender", "--content", "..", "--channel", channel, "--site-root", "/smithy/",
      "--release-version", "v0.5.0", "--ref", "abc123", "--out", "dist",
    ]).unwrap(),
  )
}

///|
test "the contents lists the sections in order" {
  let contents = tour_contents(fixture_tour())
  assert_eq(contents.sections.map(s => s.0), ["Basics", "Data modelling"])
  assert_eq(contents.sections[0].1.map(l => l.slug), ["l1", "l2"])
  assert_eq(contents.sections[1].1, [{ slug: "l3", title: "Lesson 3", }])
}

///|
test "a lesson page knows its place, its neighbours and its Worker" {
  let tour = fixture_tour()
  let config = fixture_config("next")
  let page = lesson_page(config, tour, tour.lessons[1])
  assert_eq(page.slug, "l2")
  assert_eq(page.number, 2)
  assert_eq(page.total, 3)
  assert_eq(page.previous, Some({ slug: "l1", title: "Lesson 1", }))
  assert_eq(page.next, Some({ slug: "l3", title: "Lesson 3", }))
  assert_eq(page.worker, "/smithy/next/playground/worker.js?v=abc123")
  assert_eq(page.digest, @model.digest(tour.lessons[1].files))
  assert_eq(page.files, tour.lessons[1].files)
  assert_eq(page.playground, Some("/smithy/next/playground/"))
  let first = lesson_page(config, tour, tour.lessons[0])
  assert_eq(first.previous, None)
}

///|
test "the storage key holds the channel, so the channels keep separate edits" {
  let tour = fixture_tour()
  let release = lesson_page(fixture_config("release"), tour, tour.lessons[1])
  let next = lesson_page(fixture_config("next"), tour, tour.lessons[1])
  assert_eq(release.storage_key, "smithy-tour:release:l2")
  assert_eq(next.storage_key, "smithy-tour:next:l2")
}

///|
test "a lesson of two files has no playground link" {
  let tour = fixture_tour()
  let page = lesson_page(fixture_config("next"), tour, tour.lessons[2])
  assert_eq(page.playground, None)
  assert_eq(page.next, None)
}

///|
test "the tour of this checkout loads, and a missing folder is an error that names it" {
  guard load_tour("..") is Ok(tour) else { fail("the tour did not load") }
  assert_eq(tour.lessons[0].slug, "hello-smithy")
  guard load_tour("nowhere") is Err(message) else {
    fail("a missing folder loaded")
  }
  assert_true(message.contains("nowhere/site/tour/lessons"))
}

///|
test "the search entry of the contents names every lesson" {
  let entry = tour_entry(fixture_tour())
  assert_eq(entry.route, Tour)
  assert_eq(entry.anchor, "")
  assert_true(entry.text.contains("Lesson 1"))
  assert_true(entry.text.contains("Lesson 3"))
}
