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
    engine: Model,
    extension: false,
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
  assert_true(tour.lessons.length() > 0)
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

///|
test "a lesson spec that is a docs path links to the docs page" {
  let tour = fixture_tour()
  let config = fixture_config("next")
  let lesson = { ..tour.lessons[0], spec: "pkgs/smithy-openrpc/README.mbt.md", }
  let page = lesson_page(config, tour, lesson)
  assert_eq(page.spec, @route.href(config.base, Doc("smithy-openrpc")))
  let web = lesson_page(config, tour, tour.lessons[1])
  assert_eq(web.spec, "https://smithy.io/2.0/spec/idl.html")
}

///|
test "a lesson with an OpenAPI output has no playground link" {
  let tour = fixture_tour()
  for output in [@samples.Output::OpenApi30, @samples.Output::OpenApi31] {
    let lesson = { ..tour.lessons[0], output: Some(output), }
    let page = lesson_page(fixture_config("next"), tour, lesson)
    assert_eq(page.playground, None)
  }
}

///|
test "a static lesson page has no files and no playground link" {
  let lesson = {
    ..fixture_lesson(4, "Basics", []),
    engine: Static,
    output: None,
  }
  let tour : @model.Tour = { lessons: [lesson], }
  let page = lesson_page(fixture_config("next"), tour, lesson)
  assert_eq(page.files, [])
  assert_eq(page.playground, None)
  assert_eq(page.engine, Static)
  assert_true(page.is_static())
  let model = lesson_page(
    fixture_config("next"),
    fixture_tour(),
    fixture_tour().lessons[0],
  )
  assert_eq(model.engine, Model)
  assert_true(!model.is_static())
}

///|
test "the query file of a Selector lesson does not count as a model file for the playground link" {
  let tour = fixture_tour()
  let files : Array[@model.LessonFile] = [
    { name: "model.smithy", text: "namespace a\n", },
    { name: "query.selector", text: "structure\n", },
  ]
  let lesson = { ..fixture_lesson(4, "S", files), output: Some(Selector), }
  let page = lesson_page(fixture_config("next"), tour, lesson)
  assert_true(page.playground is Some(_))
}

///|
test "a value lesson page has its engine and no playground link, also with one model file" {
  let setup : @model.ValueSetup = {
    file: "order.json",
    shape: "example#Order",
    options: @samples.ValueOptions::default(),
  }
  let files : Array[@model.LessonFile] = [
    { name: "model.smithy", text: "namespace a\n", },
    { name: "order.json", text: "{}\n", },
  ]
  let lesson = {
    ..fixture_lesson(5, "Values", files),
    engine: Value(setup),
    output: None,
  }
  let tour : @model.Tour = { lessons: [lesson], }
  let page = lesson_page(fixture_config("next"), tour, lesson)
  assert_eq(page.engine, Value(setup))
  assert_eq(page.playground, None)
}

///|
test "a transcript lesson page has no playground link" {
  let files : Array[@model.LessonFile] = [
    { name: "exchange.json", text: "{}", },
  ]
  let lesson = {
    ..fixture_lesson(4, "Weather", files),
    engine: Transcript({ file: "exchange.json", protocol: "example#P", }),
  }
  let tour : @model.Tour = { lessons: [lesson], }
  let page = lesson_page(fixture_config("next"), tour, lesson)
  assert_eq(page.playground, None)
}
