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
/// The compared events of a case must be those that its expect.json names.
fn check_events(
  where_ : String,
  case : @model.Case,
  actual : Array[@model.EventKey],
) -> Unit raise {
  let expected = case.expect.events.copy()
  expected.sort_by(@model.compare_events)
  let actual = actual.copy()
  actual.sort_by(@model.compare_events)
  if actual != expected {
    fail(
      where_ +
      ": events differ.\n  expected: " +
      show_events(expected) +
      "\n  actual:   " +
      show_events(actual),
    )
  }
}

///|
/// Check one case of a diff lesson. The model events are those of the old and
/// the new model together. The diff events are compared only when both models
/// can be compared; a case with an ERROR or a DANGER in a model claims none.
fn check_diff_case(
  session : @core.Session,
  where_ : String,
  case : @model.Case,
  all_files : Array[@model.LessonFile],
) -> Unit raise {
  let (old, new) = @model.sides(all_files)
  let (old_findings, new_findings, events) = match
    @core.handle(
      session,
      DiffModels(seq=1, old=files_of(old), new=files_of(new)),
    ) {
    Diffed(old~, new~, events~, ..) => (old, new, events)
    Blocked(reason~, ..) => fail(where_ + ": the diff was blocked: " + reason)
    _ => fail(where_ + ": unexpected answer")
  }
  let actual = compared(old_findings + new_findings)
  check_events(where_, case, actual)
  let keys = match events {
    Some(events) => events.map(e => @model.diff_key(e.id, e.severity, e.shape))
    None => []
  }
  keys.sort_by(@model.compare_code_units)
  let wanted = case.expect.diff.copy()
  wanted.sort_by(@model.compare_code_units)
  if keys != wanted {
    fail(
      where_ +
      ": diff events differ.\n  expected: " +
      show(wanted) +
      "\n  actual:   " +
      show(keys),
    )
  }
  if case.expect.output_contains.length() > 0 && events is None {
    fail(
      where_ + ": output_contains cannot run: a model has an ERROR or a DANGER",
    )
  }
  let text = match events {
    Some(events) => events.map(e => e.cli_line()).join("\n")
    None => ""
  }
  for needle in case.expect.output_contains {
    if !text.contains(needle) {
      fail(where_ + ": the output has no " + needle + "\n" + text)
    }
  }
}

///|
/// Compare the findings of a value or message check with the keys and the
/// output strings of the case. `file` is the name that the CLI prints for the
/// input.
fn check_findings(
  where_ : String,
  case : @model.Case,
  findings : Array[@core.DataFinding],
  file : String,
) -> Unit raise {
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
  let text = findings.map(f => f.cli_line(file~)).join("\n")
  for needle in case.expect.output_contains {
    if !text.contains(needle) {
      fail(where_ + ": the output has no " + needle + "\n" + text)
    }
  }
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
  if lesson.engine is Diff {
    return check_diff_case(session, where_, case, all_files)
  }
  let files = files_of(@model.model_files(lesson.engine, all_files))
  let selector = @model.query_of(all_files, fixed=lesson.selector)
  let actual = match
    @core.handle(
      session,
      @core.lesson_validate(seq=1, files~, output=lesson.output),
    ) {
    Diagnostics(items~, ..) => compared(items)
    Blocked(reason~, ..) => fail(where_ + ": validation was blocked: " + reason)
    _ => fail(where_ + ": unexpected answer")
  }
  check_events(where_, case, actual)
  let expected = case.expect.events.copy()
  expected.sort_by(@model.compare_events)
  let runs = match
    output_plan(
      lesson.output is Some(_) ||
      lesson.engine is (Value(_) | Message(_) | Transcript(_)),
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
        @core.handle(session, TransformFiles(seq=3, files~, output~, selector~)),
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
        check_findings(where_, case, findings, setup.file)
      }
    Message(setup) =>
      if runs {
        let message = match all_files.search_by(f => f.name == setup.file) {
          Some(i) => all_files[i].text
          None => fail(where_ + ": the case has no file " + setup.file)
        }
        let findings = match
          @core.handle(
            session,
            CheckMessage(
              seq=2,
              files~,
              service=setup.service,
              version=setup.version,
              message~,
              kind=setup.message_kind(all_files),
              options=setup.options,
            ),
          ) {
          DataChecked(findings~, ..) => findings
          Blocked(reason~, ..) =>
            fail(where_ + ": the message check was blocked: " + reason)
          _ => fail(where_ + ": unexpected answer")
        }
        check_findings(where_, case, findings, setup.file)
      }
    Model =>
      match lesson.output {
        Some(output) if runs => {
          let text = match
            @core.handle(
              session,
              TransformFiles(seq=2, files~, output~, selector~),
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
    Transcript(setup) =>
      if runs {
        let text = match all_files.search_by(f => f.name == setup.file) {
          Some(i) => all_files[i].text
          None => fail(where_ + ": the case has no file " + setup.file)
        }
        check_transcript(where_, files, setup, text, case.expect)
      }
    // `check_diff_case` checks a diff lesson.
    // A static lesson has no cases.
    Diff | Static => ()
  }
}

///|
/// The answer to a start or a step of a transcript: what is new, and the
/// summary when the check has ended. A block fails the case with its reason.
fn transcript_progress(
  where_ : String,
  response : @core.Response,
) -> (Array[@core.FindingView], @core.SummaryView?, Bool) raise {
  match response {
    TranscriptProgress(findings~, summary~, done~, ..) =>
      (findings, summary, done)
    Blocked(reason~, ..) =>
      fail(where_ + ": the transcript check was blocked: " + reason)
    _ => fail(where_ + ": unexpected answer")
  }
}

///|
/// The keys of the transcript findings, sorted.
fn transcript_keys(findings : Array[@core.FindingView]) -> Array[String] {
  let keys = findings.map(f => {
    @model.transcript_key(f.code, f.severity, f.entry, f.sender)
  })
  keys.sort_by(@model.compare_code_units)
  keys
}

///|
/// A fresh session that has loaded the transcript and checked `count` entries:
/// the findings so far and the last summary.
fn transcript_run(
  where_ : String,
  files : Array[(String, String)],
  setup : @model.TranscriptSetup,
  text : String,
  count : Int32,
) -> (Array[@core.FindingView], @core.SummaryView?) raise {
  let session = @core.Session::new()
  let (found, summary, done) = transcript_progress(
    where_,
    @core.handle(
      session,
      TranscriptStartFiles(
        seq=1,
        files~,
        protocol=setup.protocol,
        format=Json,
        complete=false,
        text~,
      ),
    ),
  )
  // A document that cannot be read ends at the start: it has nothing to step.
  if done {
    return (found, summary)
  }
  let (more, last, _) = transcript_progress(
    where_,
    @core.handle(session, TranscriptStep(seq=2, count~)),
  )
  (found + more, if last is Some(_) { last } else { summary })
}

///|
/// Check a transcript case: the findings of a run to the end, the verdict of
/// its summary, the findings after each step count, and the CLI lines.
fn check_transcript(
  where_ : String,
  files : Array[(String, String)],
  setup : @model.TranscriptSetup,
  text : String,
  expect : @model.Expectation,
) -> Unit raise {
  let (findings, summary) = transcript_run(where_, files, setup, text, 1000000)
  let keys = transcript_keys(findings)
  let wanted = expect.findings.copy()
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
  guard summary is Some(summary) else {
    fail(where_ + ": the check gave no summary at the end")
  }
  if expect.valid is Some(valid) && valid != summary.valid {
    fail(
      where_ +
      ": valid differs.\n  expected: \{valid}\n  actual:   \{summary.valid}",
    )
  }
  for step in expect.steps {
    let (so_far, _) = transcript_run(where_, files, setup, text, step.count)
    let keys = transcript_keys(so_far)
    let wanted = step.findings.copy()
    wanted.sort_by(@model.compare_code_units)
    if keys != wanted {
      fail(
        where_ +
        ": the findings after \{step.count} step differ.\n  expected: " +
        show(wanted) +
        "\n  actual:   " +
        show(keys),
      )
    }
  }
  let lines = findings.map(f => f.cli_line(file=setup.file))
  let expect_lines = match summary.expectations {
    Some(view) => view.cli_lines(file=setup.file)
    None => []
  }
  let output = (lines + expect_lines).join("\n")
  for needle in expect.output_contains {
    if !output.contains(needle) {
      fail(where_ + ": the output has no " + needle + "\n" + output)
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
  .filter(l => {
    l.needs_extension_note() && !l.text.contains(@model.extension_note)
  })
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

///|
/// The lesson of the tour in the folder `dir`.
fn lesson_in(dir : String) -> @model.Lesson raise {
  let tour = match @source.read_tour(lessons_root, repo="..") {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the tour: " + e)
  }
  match tour.lessons.search_by(l => l.dir == dir) {
    Some(i) => tour.lessons[i]
    None => fail("the tour has no lesson " + dir)
  }
}

///|
/// The text of the file `name` of a case of a lesson.
fn case_file(
  lesson : @model.Lesson,
  case : String,
  name : String,
) -> String raise {
  guard lesson.cases.search_by(c => c.name == case) is Some(i) else {
    fail(lesson.dir + " has no case " + case)
  }
  let files = lesson.case_files(lesson.cases[i])
  match files.search_by(f => f.name == name) {
    Some(j) => files[j].text
    None => fail(lesson.dir + "/" + case + " has no file " + name)
  }
}

///|
/// A lesson file as a README block holds it: LF line ends and no final
/// newline. A Windows checkout gives the lesson file CRLF line ends.
fn as_block(text : String) -> String {
  text.replace_all(old="\r\n", new="\n").trim_end(chars="\n").to_owned()
}

///|
/// Require the first include block of a lesson to show the lesson files. The
/// CLI tab writes each `(fixture, text)` of `cli` as that text, and the
/// MoonBit tab has each line of each text of `api` as a `#|` line.
fn check_included_files(
  lesson : @model.Lesson,
  cli~ : Array[(String, String)],
  api~ : Array[String],
) -> Unit raise {
  let doc = @markdown.parse(lesson.text, {
    source: "",
    resolve: _ => None,
    repo_url: "",
    git_ref: "",
  })
  let cli_snippets : Array[@markdown.Snippet] = []
  let api_code : Array[String] = []
  let mut seen = false
  @markdown.walk_blocks(doc.blocks, block => {
    if !seen && block is Tabs(_, tabs) {
      seen = true
      for tab in tabs {
        for s in tab.snippets {
          if tab.label == "CLI" {
            cli_snippets.push(s)
          } else if tab.label == "MoonBit" {
            api_code.push(s.code)
          }
        }
      }
    }
  })
  guard seen else { fail(lesson.dir + " has no include block") }
  for item in cli {
    let (fixture, text) = item
    match cli_snippets.search_by(s => s.file == Some(fixture)) {
      Some(i) => assert_eq(cli_snippets[i].code, as_block(text))
      None => fail(lesson.dir + ": the CLI tab has no file " + fixture)
    }
  }
  let lines : Array[String] = []
  for code in api_code {
    for line in code.split("\n") {
      lines.push(line.trim().to_owned())
    }
  }
  for text in api {
    for line in as_block(text).split("\n") {
      let hashed = ("#|" + line.to_owned()).trim_end().to_owned()
      if !lines.contains(hashed) {
        fail(lesson.dir + ": the MoonBit tab has no line " + hashed)
      }
    }
  }
}

///|
test "lesson 26 includes its own starting files" {
  let lesson = lesson_in("26-validating-values")
  let model = case_file(lesson, "start", "model.smithy")
  let order = case_file(lesson, "start", "order.json")
  check_included_files(
    lesson,
    cli=[
      ("order.smithy", model),
      ("order.json", order),
      ("order-too-many.json", case_file(lesson, "out-of-range", "order.json")),
    ],
    api=[model, order],
  )
}

///|
test "lesson 27 includes its own starting files" {
  let lesson = lesson_in("27-validating-messages")
  let model = case_file(lesson, "start", "model.smithy")
  let call = case_file(lesson, "start", "call.json")
  check_included_files(
    lesson,
    cli=[
      ("calculator.smithy", model),
      ("subtract.json", call),
      ("subtract-string.json", case_file(lesson, "wrong-type", "call.json")),
    ],
    api=[model, call],
  )
}

///|
test "lesson 28 includes its own starting files" {
  let lesson = lesson_in("28-transcripts")
  let model = case_file(lesson, "start", "model.smithy")
  let exchange = case_file(lesson, "start", "exchange.json")
  check_included_files(
    lesson,
    cli=[
      ("weather-peers.smithy", model),
      ("weather-exchange.json", exchange),
      ("weather-no-reply.json", case_file(lesson, "no-reply", "exchange.json")),
    ],
    api=[model, exchange],
  )
}

///|
test "a static extension lesson says that the feature is our extension" {
  let ok = match
    @source.read_tour("tour/source/testdata/static-ok", repo="..") {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the fixture: " + e)
  }
  assert_eq(lessons_without_note(ok), [])
  let bad = match
    @source.read_tour(
      "tour/source/testdata/static-extension-no-note",
      repo="..",
    ) {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the fixture: " + e)
  }
  assert_eq(lessons_without_note(bad), ["01-a"])
}

///|
fn diff_fixture() -> @model.Lesson raise {
  match @source.read_tour("tour/source/testdata/diff-level1", repo="..") {
    Ok(tour) => tour.lessons[0]
    Err(e) => fail("I cannot read the fixture: " + e)
  }
}

///|
fn diff_case(lesson : @model.Lesson, name : String) -> @model.Case raise {
  match lesson.cases.search_by(c => c.name == name) {
    Some(i) => lesson.cases[i]
    None => fail("the fixture has no " + name + " case")
  }
}

///|
test "a diff lesson case gives the events that its expect.json names" {
  let lesson = diff_fixture()
  assert_eq(lesson.engine, Diff)
  let session = @core.Session::new()
  for case in lesson.cases {
    check_case(session, lesson, case)
  }
  // A key that the core does not give is an error.
  let start = diff_case(lesson, "start")
  let wrong : @model.Case = {
    ..start,
    expect: { ..start.expect, diff: ["AddedShape|NOTE|example#C"], },
  }
  assert_true(
    raises_with("diff events differ", () => check_case(session, lesson, wrong)),
  )
  let wrong_severity : @model.Case = {
    ..start,
    expect: { ..start.expect, diff: ["AddedShape|ERROR|example#B"], },
  }
  assert_true(
    raises_with("diff events differ", () => {
      check_case(session, lesson, wrong_severity)
    }),
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
test "a diff case with a model error claims no diff events and the model events of both sides" {
  let lesson = diff_fixture()
  let session = @core.Session::new()
  let broken = diff_case(lesson, "broken-new")
  assert_true(broken.expect.events.any(e => e.severity.blocks_output()))
  let claims : @model.Case = {
    ..broken,
    expect: { ..broken.expect, diff: ["AddedShape|NOTE|example#B"], },
  }
  assert_true(
    raises_with("diff events differ", () => check_case(session, lesson, claims)),
  )
  let no_events : @model.Case = {
    ..broken,
    expect: { ..broken.expect, events: [], },
  }
  assert_true(
    raises_with("events differ", () => check_case(session, lesson, no_events)),
  )
}

///|
fn message_fixture() -> @model.Tour raise {
  match @source.read_tour("tour/source/testdata/message-level1", repo="..") {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the fixture: " + e)
  }
}

///|
test "a message lesson case gives the findings that its expect.json names" {
  let tour = message_fixture()
  assert_eq(tour.lessons.map(l => l.dir), ["01-call", "02-reply"])
  let session = @core.Session::new()
  for lesson in tour.lessons {
    assert_true(lesson.engine is Message(_))
    assert_eq(lesson.text.contains(@model.extension_note), true)
    for case in lesson.cases {
      check_case(session, lesson, case)
    }
  }
  // A claim that the check does not give is an error.
  let lesson = tour.lessons[0]
  let start = lesson.cases[0]
  let wrong : @model.Case = {
    ..start,
    expect: {
      ..start.expect,
      findings: ["TypeMismatch|error|/params/1|example#SubtractInput"],
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
test "a message case with an ERROR or a DANGER cannot claim findings" {
  let lesson = message_fixture().lessons[0]
  let i = lesson.cases.search_by(c => c.name == "model-error")
  guard i is Some(i) else { fail("the fixture has no model-error case") }
  let case = lesson.cases[i]
  assert_true(case.expect.events.any(e => e.severity.blocks_output()))
  check_case(@core.Session::new(), lesson, case)
  let claims : @model.Case = {
    ..case,
    expect: { ..case.expect, findings: ["Range|error|/id|example#Order"], },
  }
  assert_true(
    raises_with("output_contains cannot run", () => {
      check_case(@core.Session::new(), lesson, claims)
    }),
  )
}

///|
test "a message lesson that loses its note is found" {
  let tour = message_fixture()
  assert_eq(lessons_without_note(tour), [])
  let stripped : @model.Tour = {
    lessons: tour.lessons.map(l => {
      ..l,
      text: l.text.replace_all(old=@model.extension_note, new="> Note:"),
    }),
  }
  assert_eq(lessons_without_note(stripped), ["01-call", "02-reply"])
}

///|
test "a response case sends the text of the request file" {
  let lesson = message_fixture().lessons[1]
  let session = @core.Session::new()
  let by_name = (name : String) => {
    let i = lesson.cases.search_by(c => c.name == name)
    guard i is Some(i) else { fail("the fixture has no case " + name) }
    lesson.cases[i]
  }
  // The edited request has id 7 and the edited reply answers it.
  check_case(session, lesson, by_name("edited-request"))
  // The same reply, without the edit of the request, does not answer id 7.
  let reply_only : @model.Case = {
    ..by_name("edited-request"),
    files: [
      by_name("edited-request").files.filter(f => f.name == "reply.json")[0],
    ],
  }
  assert_true(
    raises_with("findings differ", () => check_case(session, lesson, reply_only)),
  )
}

///|
fn transcript_fixture() -> @model.Lesson raise {
  match @source.read_tour("tour/source/testdata/transcript-ok", repo="..") {
    Ok(tour) => tour.lessons[0]
    Err(e) => fail("I cannot read the fixture: " + e)
  }
}

///|
test "a transcript lesson case gives the findings, the summary and the steps that its expect.json names" {
  let lesson = transcript_fixture()
  assert_true(lesson.engine is Transcript(_))
  for case in lesson.cases {
    check_case(@core.Session::new(), lesson, case)
  }
}

///|
test "a claim that a transcript check does not give is an error" {
  let lesson = transcript_fixture()
  let session = @core.Session::new()
  let no_reply = lesson.cases[lesson.cases
    .search_by(c => c.name == "no-reply")
    .unwrap()]
  let claim = fn(expect : @model.Expectation) -> @model.Case {
    { ..no_reply, expect, }
  }
  let wrong_findings = claim({ ..no_reply.expect, findings: [], })
  assert_true(
    raises_with("findings differ", () => {
      check_case(session, lesson, wrong_findings)
    }),
  )
  let wrong_valid = claim({ ..no_reply.expect, valid: Some(true), })
  assert_true(
    raises_with("valid differs", () => check_case(session, lesson, wrong_valid)),
  )
  let wrong_steps = claim({
    ..no_reply.expect,
    steps: [{ count: 1, findings: ["MissingResponse|error|0|client"], }],
  })
  assert_true(
    raises_with("after 1 step", () => check_case(session, lesson, wrong_steps)),
  )
  let wrong_text = claim({
    ..no_reply.expect,
    output_contains: ["no such text"],
  })
  assert_true(
    raises_with("the output has no", () => {
      check_case(session, lesson, wrong_text)
    }),
  )
}

///|
test "a transcript lesson says that the check is our extension" {
  let lesson = transcript_fixture()
  assert_eq(lessons_without_note({ lessons: [lesson], }), [])
  let stripped = {
    ..lesson,
    text: lesson.text.replace_all(old=@model.extension_note, new="> Note:"),
  }
  assert_eq(lessons_without_note({ lessons: [stripped], }), ["01-weather"])
}
