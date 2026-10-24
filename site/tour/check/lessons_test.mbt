///|
/// The tests run in `site/`.
let lessons_root : String = "tour/lessons"

///|
fn files_of(files : Array[@model.LessonFile]) -> Array[(String, String)] {
  files.map(f => (f.name, f.text))
}

///|
fn show(items : Array[String]) -> String {
  "[" + items.join(", ") + "]"
}

///|
fn show_events(events : Array[@model.EventKey]) -> String {
  show(events.map(e => e.to_string()))
}

///|
/// The keys of the compared findings, sorted.
fn compared(items : Array[@core.Diagnostic]) -> Array[@model.EventKey] {
  let keys = items.filter_map(d => {
    @model.EventKey::of_finding(d.code, d.severity, d.shape)
  })
  keys.sort_by(@model.compare_events)
  keys
}

///|
/// Whether the output of a case runs. A case that names output strings must
/// be able to run it, or the claim would never be checked.
fn output_plan(
  has_output : Bool,
  events : Array[@model.EventKey],
  output_contains : Array[String],
  blocked~ : String? = None,
  findings~ : Array[String] = [],
) -> Result[Bool, String] {
  let model_errors = events.any(e => e.severity.blocks_output())
  let runs = has_output && !model_errors && blocked is None
  if findings.length() > 0 && !runs {
    return Err("the expected events have an ERROR or a DANGER")
  }
  if output_contains.length() > 0 && !runs {
    Err(
      if has_output {
        "the expected events have an ERROR or a DANGER"
      } else {
        "the lesson has no output"
      },
    )
  } else {
    Ok(runs)
  }
}

///|
/// The answer to a case that expects a blocked output must be a block for a
/// reason other than model errors, and the reason must have the text.
fn check_blocked(
  where_ : String,
  text : String,
  response : @core.Response,
) -> Unit raise {
  match response {
    Blocked(reason~, kind=Other, ..) =>
      if !reason.contains(text) {
        fail(where_ + ": the block reason has no \"" + text + "\": " + reason)
      }
    Blocked(reason~, ..) =>
      fail(where_ + ": the output is blocked by model errors: " + reason)
    _ => fail(where_ + ": I expected a blocked output, but the output ran")
  }
}

///|
/// Whether `f` fails with a message that has `text`. Any other failure is a
/// broken fixture, not the failure that the test wants.
fn raises_with(text : String, f : () -> Unit raise) -> Bool {
  try f() catch {
    e => e.to_string().contains(text)
  } noraise {
    _ => false
  }
}

///|
fn raises(f : () -> Unit raise) -> Bool {
  try f() catch {
    _ => true
  } noraise {
    _ => false
  }
}

///|
test "a blocked case does not run the output" {
  assert_eq(output_plan(true, [], [], blocked=Some("x")), Ok(false))
  assert_eq(output_plan(true, [], []), Ok(true))
  assert_true(output_plan(true, [], ["y"], blocked=Some("x")) is Err(_))
}

///|
test "check_blocked accepts only a matching Other block" {
  let other = @core.Response::Blocked(
    seq=1,
    reason="I found no service",
    kind=Other,
  )
  check_blocked("w", "no service", other)
  assert_true(raises(() => check_blocked("w", "another", other)))
  let errors = @core.Response::Blocked(
    seq=1,
    reason="no service",
    kind=ModelErrors,
  )
  assert_true(raises(() => check_blocked("w", "no service", errors)))
  let ran = @core.Response::Transformed(
    seq=1,
    files=[],
    warnings=[],
    service=None,
  )
  assert_true(raises(() => check_blocked("w", "x", ran)))
}

///|
test "output strings need an output that can run" {
  let event = fn(severity) -> @model.EventKey {
    { id: "A", severity, shape: None, }
  }
  assert_eq(output_plan(true, [], ["x"]), Ok(true))
  assert_eq(output_plan(true, [event(Warning)], ["x"]), Ok(true))
  assert_eq(output_plan(true, [event(Error)], []), Ok(false))
  assert_eq(output_plan(false, [], []), Ok(false))
  assert_true(output_plan(false, [], ["x"]) is Err(_))
  assert_true(output_plan(true, [event(Danger)], ["x"]) is Err(_))
  assert_true(output_plan(true, [event(Error)], ["x"]) is Err(_))
  assert_eq(output_plan(true, [], [], findings=["A|error||x#Y"]), Ok(true))
  assert_true(
    output_plan(true, [event(Error)], [], findings=["A|error||x#Y"]) is Err(_),
  )
}

///|
test "the tour has lessons" {
  match @source.read_tour(lessons_root, repo="..") {
    Ok(tour) => assert_true(tour.lessons.length() > 0)
    Err(e) => fail("I cannot read the tour: " + e)
  }
}

///|
/// The keys of the findings of a value check, sorted, and the CLI lines.
fn data_keys(findings : Array[@core.DataFinding]) -> Array[String] {
  let keys = findings.map(f => {
    match f {
      Found(code~, severity~, path~, shape~, ..) =>
        @model.found_key(code, severity, path, shape)
      Stopped(code~, source~, ..) => @model.stopped_key(code, source)
    }
  })
  keys.sort_by(@model.compare_code_units)
  keys
}

///|
/// Check one case of a lesson: its events, its findings and its output text.
fn check_case(
  session : @core.Session,
  lesson : @model.Lesson,
  case : @model.Case,
) -> Unit raise {
  let where_ = lesson.case_id(case).to_string()
  let all_files = lesson.case_files(case)
  let files = files_of(@model.model_files(lesson.engine, all_files))
  let actual = match
    @core.handle(
      session,
      @core.lesson_validate(seq=1, files~, output=lesson.output),
    ) {
    Diagnostics(items~, ..) => compared(items)
    Blocked(reason~, ..) => fail(where_ + ": validation was blocked: " + reason)
    _ => fail(where_ + ": unexpected answer")
  }
  let expected = case.expect.events.copy()
  expected.sort_by(@model.compare_events)
  if actual != expected {
    fail(
      where_ +
      ": events differ.\n  expected: " +
      show_events(expected) +
      "\n  actual:   " +
      show_events(actual),
    )
  }
  let runs = match
    output_plan(
      lesson.output is Some(_) || lesson.engine is Value(_),
      expected,
      case.expect.output_contains,
      blocked=case.expect.blocked,
      findings=case.expect.findings,
    ) {
    Ok(runs) => runs
    Err(reason) => fail(where_ + ": output_contains cannot run: " + reason)
  }
  match (case.expect.blocked, lesson.output) {
    (Some(text), Some(output)) =>
      check_blocked(
        where_,
        text,
        @core.handle(
          session,
          TransformFiles(seq=3, files~, output~, selector=lesson.selector),
        ),
      )
    _ => ()
  }
  match lesson.engine {
    Value(setup) =>
      if runs {
        let value = match all_files.search_by(f => f.name == setup.file) {
          Some(i) => all_files[i].text
          None => fail(where_ + ": the case has no file " + setup.file)
        }
        let findings = match
          @core.handle(
            session,
            CheckValue(
              seq=2,
              files~,
              shape=setup.shape,
              value~,
              options=setup.options,
            ),
          ) {
          DataChecked(findings~, ..) => findings
          Blocked(reason~, ..) =>
            fail(where_ + ": the value check was blocked: " + reason)
          _ => fail(where_ + ": unexpected answer")
        }
        let keys = data_keys(findings)
        let wanted = case.expect.findings.copy()
        wanted.sort_by(@model.compare_code_units)
        if keys != wanted {
          fail(
            where_ +
            ": findings differ.\n  expected: " +
            show(wanted) +
            "\n  actual:   " +
            show(keys),
          )
        }
        let text = findings.map(f => f.cli_line(file=setup.file)).join("\n")
        for needle in case.expect.output_contains {
          if !text.contains(needle) {
            fail(where_ + ": the output has no " + needle + "\n" + text)
          }
        }
      }
    Model =>
      match lesson.output {
        Some(output) if runs => {
          let text = match
            @core.handle(
              session,
              TransformFiles(seq=2, files~, output~, selector=lesson.selector),
            ) {
            Transformed(files=out, ..) => @model.output_text(out)
            Blocked(reason~, ..) =>
              fail(where_ + ": the output was blocked: " + reason)
            _ => fail(where_ + ": unexpected answer")
          }
          for needle in case.expect.output_contains {
            if !text.contains(needle) {
              fail(where_ + ": the output has no " + needle + "\n" + text)
            }
          }
        }
        _ => ()
      }
  }
}

///|
test "every lesson case gives the findings and the output that its expect.json names" {
  let tour = match @source.read_tour(lessons_root, repo="..") {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the tour: " + e)
  }
  let session = @core.Session::new()
  for lesson in tour.lessons {
    for case in lesson.cases {
      check_case(session, lesson, case)
    }
  }
}

///|
test "a value lesson case gives the findings that its expect.json names" {
  let tour = match
    @source.read_tour("tour/source/testdata/value-level1", repo="..") {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the fixture: " + e)
  }
  let lesson = tour.lessons[0]
  assert_true(lesson.engine is Value(_))
  assert_eq(lesson.text.contains(@model.extension_note), true)
  let session = @core.Session::new()
  for case in lesson.cases {
    check_case(session, lesson, case)
  }
  // A claim that the check does not give is an error.
  let start = lesson.cases[0]
  let wrong : @model.Case = {
    ..start,
    expect: {
      ..start.expect,
      findings: ["Range|error|/quantity|example#Order"],
    },
  }
  assert_true(
    raises_with("findings differ", () => check_case(session, lesson, wrong)),
  )
  let wrong_text : @model.Case = {
    ..start,
    expect: { ..start.expect, output_contains: ["no such text"], },
  }
  assert_true(
    raises_with("the output has no", () => {
      check_case(session, lesson, wrong_text)
    }),
  )
}

///|
test "a value case with an ERROR or a DANGER cannot claim findings" {
  let tour = match
    @source.read_tour("tour/source/testdata/value-level1", repo="..") {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the fixture: " + e)
  }
  let lesson = tour.lessons[0]
  let broken = lesson.cases.search_by(c => c.name == "model-error")
  guard broken is Some(i) else { fail("the fixture has no model-error case") }
  let case = lesson.cases[i]
  assert_true(case.expect.events.any(e => e.severity.blocks_output()))
  let claims : @model.Case = {
    ..case,
    expect: {
      ..case.expect,
      findings: ["Range|error|/quantity|example#Order"],
    },
  }
  assert_true(
    raises_with("output_contains cannot run", () => {
      check_case(@core.Session::new(), lesson, claims)
    }),
  )
  let says : @model.Case = {
    ..case,
    expect: { ..case.expect, output_contains: ["Range"], },
  }
  assert_true(
    raises_with("output_contains cannot run", () => {
      check_case(@core.Session::new(), lesson, says)
    }),
  )
}

///|
/// The folders of the value and message lessons whose text has no extension
/// note.
fn lessons_without_note(tour : @model.Tour) -> Array[String] {
  tour.lessons
  .filter(l => !(l.engine is Model) && !l.text.contains(@model.extension_note))
  .map(l => l.dir)
}

///|
test "a value or message lesson says that the check is our extension" {
  let tour = match @source.read_tour(lessons_root, repo="..") {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the tour: " + e)
  }
  assert_eq(lessons_without_note(tour), [])
  // The fixture has the note; the same lesson without the note is found.
  let fixture = match
    @source.read_tour("tour/source/testdata/value-level1", repo="..") {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the fixture: " + e)
  }
  assert_eq(lessons_without_note(fixture), [])
  let stripped : @model.Tour = {
    lessons: fixture.lessons.map(l => {
      ..l,
      text: l.text.replace_all(old=@model.extension_note, new="> Note:"),
    }),
  }
  assert_eq(lessons_without_note(stripped), ["01-order", "02-member"])
}

///|
test "a value check stops with the source that the CLI names" {
  let tour = match
    @source.read_tour("tour/source/testdata/value-level1", repo="..") {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the fixture: " + e)
  }
  let lesson = tour.lessons[0]
  let session = @core.Session::new()
  let i = lesson.cases.search_by(c => c.name == "missing-target")
  guard i is Some(i) else { fail("the fixture has no missing-target case") }
  check_case(session, lesson, lesson.cases[i])
}

///|
test "a value lesson can name a member as its target" {
  let tour = match
    @source.read_tour("tour/source/testdata/value-level1", repo="..") {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the fixture: " + e)
  }
  let lesson = tour.lessons[1]
  guard lesson.engine is Value(setup) else { fail("not a value lesson") }
  assert_eq(setup.shape, "example#Order$quantity")
  let session = @core.Session::new()
  for case in lesson.cases {
    check_case(session, lesson, case)
  }
}

///|
test "lesson 01 includes its own starting model" {
  let tour = match @source.read_tour(lessons_root, repo="..") {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the tour: " + e)
  }
  let lesson = tour.lessons[0]
  assert_eq(lesson.slug, "hello-smithy")
  let doc = @markdown.parse(lesson.text, {
    source: "",
    resolve: _ => None,
    repo_url: "",
    git_ref: "",
  })
  let mut cli : @markdown.Snippet? = None
  let mut api : @markdown.Snippet? = None
  @markdown.walk_blocks(doc.blocks, block => {
    if block is Tabs(_, tabs) {
      for tab in tabs {
        for s in tab.snippets {
          if tab.label == "CLI" && s.file is Some(_) && cli is None {
            cli = Some(s)
          }
          if tab.label == "MoonBit" && s.lang == "mbt" && api is None {
            api = Some(s)
          }
        }
      }
    }
  })
  guard cli is Some(snippet) else {
    fail("lesson 01 has no CLI tab with a file")
  }
  guard api is Some(api_snippet) else { fail("lesson 01 has no MoonBit tab") }
  // The README blocks have no final newline; the lesson file has one. A Windows
  // checkout gives the lesson file CRLF line ends, and the snippets have LF.
  let model = lesson.files[0].text
    .replace_all(old="\r\n", new="\n")
    .trim_end(chars="\n")
    .to_owned()
  assert_eq(snippet.code, model)
  // The first run of `#|` lines of the API block is its copy of the model.
  let copy : Array[String] = []
  let mut started = false
  for line in api_snippet.code.split("\n") {
    let t = line.trim().to_owned()
    if t.has_prefix("#|") {
      started = true
      copy.push(t[2:].to_owned())
    } else if started {
      break
    }
  }
  assert_eq(copy.join("\n"), model)
}
