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
) -> Result[Bool, String] {
  let model_errors = events.any(e => e.severity.blocks_output())
  let runs = has_output && !model_errors && blocked is None
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
}

///|
test "the tour has lessons" {
  match @source.read_tour(lessons_root, repo="..") {
    Ok(tour) => assert_true(tour.lessons.length() > 0)
    Err(e) => fail("I cannot read the tour: " + e)
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
      let where_ = lesson.case_id(case).to_string()
      let files = files_of(lesson.case_files(case))
      let actual = match
        @core.handle(
          session,
          @core.lesson_validate(seq=1, files~, output=lesson.output),
        ) {
        Diagnostics(items~, ..) => compared(items)
        Blocked(reason~, ..) =>
          fail(where_ + ": validation was blocked: " + reason)
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
          lesson.output is Some(_),
          expected,
          case.expect.output_contains,
          blocked=case.expect.blocked,
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
