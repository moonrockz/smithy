///|
let start_text : String = "$version: \"2\"\n\nnamespace example\n\nstructure Greeting {}\n"

///|
let key : String = "smithy-tour:release:hello-smithy"

///|
fn page() -> @model.LessonPage {
  let files : Array[@model.LessonFile] = [
    { name: "model.smithy", text: start_text, },
  ]
  {
    slug: "hello-smithy",
    title: "Hello, Smithy",
    section: "Basics",
    number: 1,
    total: 12,
    output: Some(JsonAst),
    selector: None,
    spec: "https://smithy.io/2.0/spec/idl.html",
    files,
    digest: @model.digest(files),
    previous: None,
    next: Some({ slug: "simple-shapes", title: "Simple shapes", }),
    worker: "/smithy/playground/worker.js",
    storage_key: key,
    playground: Some("/smithy/playground/"),
  }
}

///|
/// A lesson about findings: it has no output.
fn findings_page() -> @model.LessonPage {
  { ..page(), output: None, }
}

///|
/// A lesson of two files. The playground holds one model, so it has no link.
fn two_file_page() -> @model.LessonPage {
  let files : Array[@model.LessonFile] = [
    { name: "a.smithy", text: "namespace a\n", },
    { name: "b.smithy", text: "namespace b\n", },
  ]
  { ..page(), files, digest: @model.digest(files), playground: None, }
}

///|
fn error_in(file : String, line : Int32) -> @core.Diagnostic {
  {
    severity: "ERROR",
    code: "Model",
    message: "I expected a namespace statement before the shape, but found `structure`.",
    file,
    start_line: line,
    start_column: 1,
    end_line: line,
    end_column: 10,
    shape: None,
  }
}

///|
fn warning_in(file : String) -> @core.Diagnostic {
  {
    ..error_in(file, 1),
    severity: "WARNING",
    code: "UnreferencedShape",
    message: "The shape is not used.",
  }
}

///|
fn note_in(file : String) -> @core.Diagnostic {
  { ..error_in(file, 1), severity: "NOTE", code: "ModelDeprecation", }
}

///|
/// The stored value for these files, as the lesson writes it.
fn stored(digest : String, files : Array[(String, String)]) -> String {
  let pairs : Array[Json] = files.map(f => {
    [Json::string(f.0), Json::string(f.1)]
  })
  ({ "digest": Json::string(digest), "files": Json::array(pairs) } : Json).stringify()
}

///|
/// Apply the messages in order and keep the effects of the last one.
fn run(m : Model, msgs : Array[Msg]) -> (Model, Array[Effect]) {
  let mut model = m
  let mut effects = []
  for msg in msgs {
    let (next, out) = update(model, msg)
    model = next
    effects = out
  }
  (model, effects)
}

///|
/// A started lesson whose starting files gave no findings and this output.
fn shown(text : String) -> Model {
  let (m, _) = Model::start(page(), None)
  run(m, [
    Answered(seq=1, answer=Checked([])),
    Answered(seq=2, answer=Converted(text)),
  ]).0
}

///|
/// Edit the model, wait for the debounce, and give a clean check: the
/// transform of the new text is sent.
fn edit_clean(m : Model, text : String) -> Model {
  let m = run(m, [Edited(text), Debounced(m.edits + 1)]).0
  update(m, Answered(seq=m.seq, answer=Checked([]))).0
}

///|
test "start sends a validate of the starting files" {
  let (m, effects) = Model::start(page(), None)
  assert_eq(m.seq, 1)
  assert_true(m.waiting)
  assert_eq(m.findings, Unchecked)
  assert_eq(m.output, NoOutput)
  assert_eq(effects, [
    LoadEditor(text=start_text),
    SendValidate(seq=1, files=[("model.smithy", start_text)]),
    Wait(ms=10000, msg=TimedOut(1)),
  ])
}

///|
test "start uses stored files whose digest matches" {
  let edited = "namespace example\nstructure Edited {}\n"
  let (m, effects) = Model::start(
    page(),
    Some(stored(page().digest, [("model.smithy", edited)])),
  )
  assert_eq(m.files, [{ name: "model.smithy", text: edited, }])
  assert_eq(effects, [
    LoadEditor(text=edited),
    SendValidate(seq=1, files=[("model.smithy", edited)]),
    Wait(ms=10000, msg=TimedOut(1)),
  ])
}

///|
test "start ignores and clears stored files with another digest" {
  // The starting files changed in a later build: the stored edits are of
  // the old files.
  let old = stored("0".repeat(64), [("model.smithy", "namespace old\n")])
  let (m, effects) = Model::start(page(), Some(old))
  assert_eq(m.files, page().files)
  assert_eq(effects, [
    Clear(key~),
    LoadEditor(text=start_text),
    SendValidate(seq=1, files=[("model.smithy", start_text)]),
    Wait(ms=10000, msg=TimedOut(1)),
  ])
}

///|
test "start ignores and clears a stored value that it cannot read" {
  for
    bad in [
      "not JSON",
      "{\"digest\": 3}",
      stored(page().digest, [("other.smithy", "namespace other\n")]),
      stored(page().digest, []),
    ] {
    let (m, effects) = Model::start(page(), Some(bad))
    assert_eq(m.files, page().files)
    assert_eq(effects[0], Clear(key~))
  }
}

///|
test "an edit waits 250 ms, then validates the current files" {
  let m = shown("{}")
  let text = "namespace example\nstructure B {}\n"
  let (m, effects) = update(m, Edited(text))
  assert_eq(m.edits, 1)
  assert_eq(effects, [
    Store(key~, value=stored(page().digest, [("model.smithy", text)])),
    Wait(ms=250, msg=Debounced(1)),
  ])
  let (m, effects) = update(m, Debounced(1))
  assert_eq(effects, [
    SendValidate(seq=3, files=[("model.smithy", text)]),
    Wait(ms=10000, msg=TimedOut(3)),
  ])
  assert_eq(m.seq, 3)
}

///|
test "only the wait of the last edit sends a request" {
  let m = shown("{}")
  let (m, _) = run(m, [Edited("namespace a\n"), Edited("namespace ab\n")])
  assert_eq(update(m, Debounced(1)).1, [])
  assert_eq(update(m, Debounced(2)).1, [
    SendValidate(seq=3, files=[("model.smithy", "namespace ab\n")]),
    Wait(ms=10000, msg=TimedOut(3)),
  ])
}

///|
test "an edit back to the starting files clears the stored files" {
  let m = shown("{}")
  let (m, _) = update(m, Edited("namespace changed\n"))
  let (_, effects) = update(m, Edited(start_text))
  assert_eq(effects, [Clear(key~), Wait(ms=250, msg=Debounced(2))])
}

///|
test "the editor echo of the text that the lesson loaded changes nothing" {
  let m = shown("{}")
  let (next, effects) = update(m, Edited(start_text))
  assert_eq(next, m)
  assert_eq(effects, [])
}

///|
test "an answer for an older seq is dropped" {
  // The reader types while the first check runs.
  let (m, _) = Model::start(page(), None)
  let (m, effects) = run(m, [Edited("namespace a\n"), Debounced(1)])
  assert_eq(effects, [])
  assert_true(m.pending)
  // The answer is for the text before the edit: it does not show, and the
  // newest text goes to the Worker.
  let (m, effects) = update(
    m,
    Answered(seq=1, answer=Checked([error_in("model.smithy", 1)])),
  )
  assert_eq(m.findings, Unchecked)
  assert_eq(effects, [
    SendValidate(seq=2, files=[("model.smithy", "namespace a\n")]),
    Wait(ms=10000, msg=TimedOut(2)),
  ])
  // A second answer to the old request changes nothing.
  let (next, effects) = update(m, Answered(seq=1, answer=Converted("old")))
  assert_eq(next, m)
  assert_eq(effects, [])
  // Only the answer to the newest request shows.
  let (m, _) = update(m, Answered(seq=2, answer=Checked([])))
  assert_eq(m.findings, Found([]))
}

///|
test "a transform answer for text that changed since does not show" {
  let (m, _) = Model::start(page(), None)
  let (m, _) = update(m, Answered(seq=1, answer=Checked([])))
  // The transform (seq 2) runs; the reader types and the wait ends.
  let (m, _) = run(m, [Edited("namespace a\n"), Debounced(1)])
  let (m, effects) = update(m, Answered(seq=2, answer=Converted("old")))
  assert_eq(m.output, NoOutput)
  assert_eq(effects, [
    SendValidate(seq=3, files=[("model.smithy", "namespace a\n")]),
    Wait(ms=10000, msg=TimedOut(3)),
  ])
}

///|
test "a file tab change while a request runs keeps the newest answer" {
  let page = two_file_page()
  let (m, _) = Model::start(page, None)
  let (m, effects) = update(m, SelectFile(1))
  assert_eq(effects, [LoadEditor(text="namespace b\n"), Mark(items=[])])
  // The editor echo of the loaded text changes nothing.
  assert_eq(update(m, Edited("namespace b\n")).1, [])
  let items = [error_in("a.smithy", 1), warning_in("b.smithy")]
  let (m, effects) = update(m, Answered(seq=1, answer=Checked(items)))
  // The editor marks the findings of the file that it shows.
  assert_eq(effects[0], Mark(items=[warning_in("b.smithy")]))
  assert_eq(m.findings, Found(items))
  let (_, effects) = update(m, SelectFile(0))
  assert_eq(effects, [
    LoadEditor(text="namespace a\n"),
    Mark(items=[error_in("a.smithy", 1)]),
  ])
}

///|
test "an edit changes the file that the editor shows" {
  let (m, _) = Model::start(two_file_page(), None)
  let (m, _) = update(m, SelectFile(1))
  let (m, effects) = update(m, Edited("namespace bb\n"))
  assert_eq(m.files, [
    { name: "a.smithy", text: "namespace a\n", },
    { name: "b.smithy", text: "namespace bb\n", },
  ])
  assert_eq(
    effects[0],
    Store(
      key~,
      value=stored(two_file_page().digest, [
        ("a.smithy", "namespace a\n"),
        ("b.smithy", "namespace bb\n"),
      ]),
    ),
  )
}

///|
test "a clean validate starts a transform; its output is highlighted against the previous output" {
  let (m, _) = Model::start(page(), None)
  let (m, effects) = update(m, Answered(seq=1, answer=Checked([])))
  assert_eq(effects, [
    Mark(items=[]),
    SendTransform(
      seq=2,
      files=[("model.smithy", start_text)],
      output=JsonAst,
      selector=None,
    ),
    Wait(ms=10000, msg=TimedOut(2)),
  ])
  // The first output has nothing before it: nothing is highlighted.
  let (m, effects) = update(m, Answered(seq=2, answer=Converted("a\nb\nc")))
  assert_eq(effects, [ShowOutput(text="a\nb\nc", highlight=[])])
  assert_eq(m.output, Shown(text="a\nb\nc", highlight=[]))
  assert_false(m.waiting)
  let m = edit_clean(m, "namespace example\n")
  let (m, effects) = update(m, Answered(seq=4, answer=Converted("a\nB\nc")))
  assert_eq(effects, [ShowOutput(text="a\nB\nc", highlight=[2])])
  assert_eq(m.output, Shown(text="a\nB\nc", highlight=[2]))
}

///|
test "a transform sends the selector of the lesson" {
  let page = { ..page(), output: Some(Selector), selector: Some("string"), }
  let (m, _) = Model::start(page, None)
  let (_, effects) = update(m, Answered(seq=1, answer=Checked([])))
  assert_eq(
    effects[1],
    SendTransform(
      seq=2,
      files=[("model.smithy", start_text)],
      output=Selector,
      selector=Some("string"),
    ),
  )
}

///|
test "a warning does not stop the transform" {
  let (m, _) = Model::start(page(), None)
  let (m, effects) = update(
    m,
    Answered(seq=1, answer=Checked([warning_in("model.smithy")])),
  )
  assert_eq(m.inflight, Transforming)
  assert_true(effects.contains(Wait(ms=10000, msg=TimedOut(2))))
}

///|
test "an edit that does not parse shows the findings, the blocked reason and no highlight" {
  let m = shown("a\nb")
  let broken = "$version: \"2\"\nstructure Greeting {}\n"
  let (m, _) = run(m, [Edited(broken), Debounced(1)])
  let error = error_in("model.smithy", 2)
  let (m, effects) = update(m, Answered(seq=3, answer=Checked([error])))
  // No transform runs, and the old output goes away.
  assert_eq(effects, [Mark(items=[error]), ShowOutput(text="", highlight=[])])
  assert_eq(m.findings, Found([error]))
  assert_eq(
    m.output,
    NotShown(
      "The model has 1 error, so I did not make the JSON AST. The Findings tab shows the error.",
    ),
  )
  assert_false(m.waiting)
  let (_, effects) = update(
    m,
    Answered(seq=3, answer=Checked([error, { ..error, severity: "DANGER", }])),
  )
  assert_eq(effects, [])
}

///|
test "the blocked reason counts every error and danger" {
  let error = error_in("model.smithy", 2)
  let (m, _) = Model::start(page(), None)
  let (m, _) = update(
    m,
    Answered(
      seq=1,
      answer=Checked([
        error,
        { ..error, severity: "DANGER", },
        note_in("model.smithy"),
      ]),
    ),
  )
  assert_eq(
    m.output,
    NotShown(
      "The model has 2 errors, so I did not make the JSON AST. The Findings tab shows the errors.",
    ),
  )
}

///|
test "a transform that the Worker does not run shows its reason" {
  let (m, _) = Model::start(page(), None)
  let (m, _) = update(m, Answered(seq=1, answer=Checked([])))
  let (m, effects) = update(
    m,
    Answered(seq=2, answer=NotConverted("The selector is not valid.")),
  )
  assert_eq(m.output, NotShown("The selector is not valid."))
  assert_eq(effects, [ShowOutput(text="", highlight=[])])
}

///|
test "the first output after a blocked output has no highlight" {
  let m = shown("a\nb\nc")
  let (m, _) = run(m, [Edited("broken"), Debounced(1)])
  let (m, _) = update(
    m,
    Answered(seq=3, answer=Checked([error_in("model.smithy", 1)])),
  )
  let m = edit_clean(m, "namespace example\n")
  let (m, effects) = update(m, Answered(seq=5, answer=Converted("a\nX\nc")))
  assert_eq(effects, [ShowOutput(text="a\nX\nc", highlight=[])])
  assert_eq(m.output, Shown(text="a\nX\nc", highlight=[]))
}

///|
test "Reset loads the starting files and clears the stored files" {
  let m = shown("{}")
  let (m, _) = update(m, Edited("namespace changed\n"))
  let (m, effects) = update(m, Reset)
  assert_eq(m.files, page().files)
  assert_eq(effects, [
    Clear(key~),
    LoadEditor(text=start_text),
    SendValidate(seq=3, files=[("model.smithy", start_text)]),
    Wait(ms=10000, msg=TimedOut(3)),
  ])
  // The wait of the edit before the reset sends nothing.
  assert_eq(update(m, Debounced(1)).1, [])
  // The editor echo of the starting text changes nothing.
  assert_eq(update(m, Edited(start_text)).1, [])
}

///|
test "Reset while a request runs checks the starting files after it" {
  let (m, _) = Model::start(page(), None)
  let (m, _) = update(m, Edited("namespace changed\n"))
  let (m, effects) = update(m, Reset)
  assert_eq(effects, [Clear(key~), LoadEditor(text=start_text)])
  let (_, effects) = update(m, Answered(seq=1, answer=Checked([])))
  assert_eq(effects, [
    SendValidate(seq=2, files=[("model.smithy", start_text)]),
    Wait(ms=10000, msg=TimedOut(2)),
  ])
}

///|
test "a lesson without an output never sends a transform" {
  let (m, _) = Model::start(findings_page(), None)
  assert_eq(m.pane, FindingsPane)
  let (m, effects) = update(m, Answered(seq=1, answer=Checked([])))
  assert_eq(effects, [Mark(items=[])])
  assert_false(m.waiting)
  let (m, effects) = update(
    m,
    Answered(seq=1, answer=Checked([error_in("model.smithy", 1)])),
  )
  assert_eq(effects, [])
  let m = run(m, [Edited("namespace a\n"), Debounced(1)]).0
  let (m, effects) = update(
    m,
    Answered(seq=2, answer=Checked([error_in("model.smithy", 1)])),
  )
  assert_eq(effects, [Mark(items=[error_in("model.smithy", 1)])])
  assert_eq(m.output, NoOutput)
  // The lesson has no output tab to select.
  assert_eq(update(m, SelectPane(OutputPane)).0.pane, FindingsPane)
}

///|
test "the output tab opens first, unless the starting model has findings" {
  let (m, _) = Model::start(page(), None)
  assert_eq(m.pane, OutputPane)
  // A NOTE is not a finding that the lesson compares.
  let (clean, _) = update(
    m,
    Answered(seq=1, answer=Checked([note_in("model.smithy")])),
  )
  assert_eq(clean.pane, OutputPane)
  let (m, _) = update(
    m,
    Answered(seq=1, answer=Checked([warning_in("model.smithy")])),
  )
  assert_eq(m.pane, FindingsPane)
  // Later answers do not move the reader's tab.
  let (m, _) = run(m, [
    SelectPane(OutputPane),
    Answered(seq=2, answer=Converted("{}")),
  ])
  let m = run(m, [Edited("namespace a\n"), Debounced(1)]).0
  let (m, _) = update(
    m,
    Answered(seq=3, answer=Checked([warning_in("model.smithy")])),
  )
  assert_eq(m.pane, OutputPane)
}

///|
test "a timeout restarts the worker and sends the request again" {
  let (m, _) = Model::start(page(), None)
  let (m, effects) = update(m, TimedOut(1))
  assert_eq(effects, [
    RestartWorker,
    SendValidate(seq=2, files=[("model.smithy", start_text)]),
    Wait(ms=10000, msg=TimedOut(2)),
  ])
  // The time of an older request ends: nothing happens.
  assert_eq(update(m, TimedOut(1)).1, [])
  // The answer of the stopped Worker can no longer come, and is dropped.
  assert_eq(update(m, Answered(seq=1, answer=Checked([]))).1, [])
  // A second timeout of the same request stops: a model that is too slow
  // would restart the Worker again and again.
  let (m, effects) = update(m, TimedOut(2))
  assert_eq(effects, [
    RestartWorker,
    Mark(items=[]),
    ShowOutput(text="", highlight=[]),
  ])
  assert_eq(m.findings, NotChecked(timeout_text))
  assert_eq(m.output, NotShown(timeout_text))
  assert_false(m.waiting)
  // The next edit tries again.
  let (_, effects) = run(m, [Edited("namespace a\n"), Debounced(1)])
  assert_eq(effects, [
    SendValidate(seq=3, files=[("model.smithy", "namespace a\n")]),
    Wait(ms=10000, msg=TimedOut(3)),
  ])
}

///|
test "the timeout text names the time limit" {
  assert_true(timeout_text.has_prefix("The check took more than 10 s,"))
}

///|
test "a timeout of a transform sends the transform again" {
  let (m, _) = Model::start(page(), None)
  let (m, _) = update(m, Answered(seq=1, answer=Checked([])))
  let (m, effects) = update(m, TimedOut(2))
  assert_eq(effects, [
    RestartWorker,
    SendTransform(
      seq=3,
      files=[("model.smithy", start_text)],
      output=JsonAst,
      selector=None,
    ),
    Wait(ms=10000, msg=TimedOut(3)),
  ])
  // A second timeout stops the output and keeps the findings.
  let (m, effects) = update(m, TimedOut(3))
  assert_eq(effects, [RestartWorker, ShowOutput(text="", highlight=[])])
  assert_eq(m.findings, Found([]))
  assert_eq(m.output, NotShown(timeout_text))
}

///|
test "a timeout of a lesson without an output stops the findings only" {
  let (m, _) = Model::start(findings_page(), None)
  let (m, effects) = run(m, [TimedOut(1), TimedOut(2)])
  assert_eq(effects, [RestartWorker, Mark(items=[])])
  assert_eq(m.findings, NotChecked(timeout_text))
  assert_eq(m.output, NoOutput)
}

///|
test "a timeout after an edit checks the newest files" {
  let (m, _) = Model::start(page(), None)
  let (m, _) = run(m, [TimedOut(1), Edited("namespace a\n"), Debounced(1)])
  let (m, effects) = update(m, TimedOut(2))
  assert_eq(effects, [
    RestartWorker,
    SendValidate(seq=3, files=[("model.smithy", "namespace a\n")]),
    Wait(ms=10000, msg=TimedOut(3)),
  ])
  assert_false(m.retried)
}

///|
test "a timeout of a transform after an edit checks the edited files" {
  let (m, _) = Model::start(page(), None)
  // The transform of the starting files runs, and the wait of the edit has
  // not ended.
  let (m, _) = run(m, [
    Answered(seq=1, answer=Checked([])),
    Edited("namespace a\n"),
  ])
  let (m, effects) = update(m, TimedOut(2))
  assert_eq(effects, [
    RestartWorker,
    SendValidate(seq=3, files=[("model.smithy", "namespace a\n")]),
    Wait(ms=10000, msg=TimedOut(3)),
  ])
  assert_false(m.retried)
}

///|
test "OpenPlayground navigates to the playground with the current model" {
  let text = "namespace example\nstructure Mine {}\n"
  let m = shown("{}")
  let (m, _) = update(m, Edited(text))
  let (_, effects) = update(m, OpenPlayground)
  let state : @samples.ShareState = {
    model: text,
    transcript: "",
    tab: TransformTab,
    output: JsonAst,
    protocol: "",
    format: Markdown,
    complete: false,
    selector: None,
    log_preset: None,
    version: None,
  }
  assert_eq(effects, [
    Navigate(url="/smithy/playground/#" + @core.encode_share(state)),
  ])
  // The link opens in the playground as this state.
  assert_eq(@core.decode_share(@core.encode_share(state)), Ok(state))
}

///|
test "OpenPlayground opens a lesson without an output in the Validate tab" {
  let (m, _) = Model::start(findings_page(), None)
  let (_, effects) = update(m, OpenPlayground)
  guard effects is [Navigate(url~)] else { fail("no navigation") }
  let fragment = url["/smithy/playground/#".length():].to_owned()
  guard @core.decode_share(fragment) is Ok(state) else { fail("bad link") }
  assert_eq(state.tab, ValidateTab)
  assert_eq(state.model, start_text)
}

///|
test "OpenPlayground does nothing for a lesson of two files" {
  let (m, _) = Model::start(two_file_page(), None)
  assert_eq(update(m, OpenPlayground).1, [])
}

///|
test "OpenPlayground does not open a model that is too large for a link" {
  let m = shown("{}")
  // Text that deflate cannot pack: each line differs.
  let big = Array::makei(3000, i => "// \{i * 7919 % 10007} \{i}").join("\n")
  let (m, _) = update(m, Edited(big))
  let (m, effects) = update(m, OpenPlayground)
  assert_eq(effects, [])
  assert_true(m.link_problem is Some(_))
  // An edit removes the notice.
  let (m, _) = update(m, Edited("namespace a\n"))
  assert_eq(m.link_problem, None)
}
