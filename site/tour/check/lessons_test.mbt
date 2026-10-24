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
) -> Result[Bool, String] {
  let blocked = events.any(e => e.severity.blocks_output())
  let runs = has_output && !blocked
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
  match @source.read_tour(lessons_root) {
    Ok(tour) => assert_true(tour.lessons.length() > 0)
    Err(e) => fail("I cannot read the tour: " + e)
  }
}

///|
test "every lesson case gives the findings and the output that its expect.json names" {
  let tour = match @source.read_tour(lessons_root) {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the tour: " + e)
  }
  let session = @core.Session::new()
  for lesson in tour.lessons {
    for case in lesson.cases {
      let where_ = lesson.case_id(case).to_string()
      let files = files_of(lesson.case_files(case))
      let actual = match @core.handle(session, ValidateFiles(seq=1, files~)) {
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
        ) {
        Ok(runs) => runs
        Err(reason) => fail(where_ + ": output_contains cannot run: " + reason)
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
