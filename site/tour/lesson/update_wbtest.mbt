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
    engine: Model,
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
    LoadEditor(
      text=start_text,
      file="model.smithy",
      fresh=true,
      language="smithy",
    ),
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
    LoadEditor(text=edited, file="model.smithy", fresh=true, language="smithy"),
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
    LoadEditor(
      text=start_text,
      file="model.smithy",
      fresh=true,
      language="smithy",
    ),
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
  assert_eq(effects, [
    LoadEditor(
      text="namespace b\n",
      file="b.smithy",
      fresh=false,
      language="smithy",
    ),
    Mark(items=[]),
  ])
  // The editor echo of the loaded text changes nothing.
  assert_eq(update(m, Edited("namespace b\n")).1, [])
  let items = [error_in("a.smithy", 1), warning_in("b.smithy")]
  let (m, effects) = update(m, Answered(seq=1, answer=Checked(items)))
  // The editor marks the findings of the file that it shows.
  assert_eq(effects[0], Mark(items=[warning_in("b.smithy")]))
  assert_eq(m.findings, Found(items))
  let (_, effects) = update(m, SelectFile(0))
  assert_eq(effects, [
    LoadEditor(
      text="namespace a\n",
      file="a.smithy",
      fresh=false,
      language="smithy",
    ),
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
    LoadEditor(
      text=start_text,
      file="model.smithy",
      fresh=true,
      language="smithy",
    ),
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
  assert_eq(effects, [
    Clear(key~),
    LoadEditor(
      text=start_text,
      file="model.smithy",
      fresh=true,
      language="smithy",
    ),
  ])
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

///|
test "ToggleExpand expands a pane and the same button gives the split view back" {
  let (m, _) = Model::start(page(), None)
  assert_eq(m.layout, Split)
  let (m, effects) = update(m, ToggleExpand(EditorSide))
  assert_eq(m.layout, EditorOnly)
  assert_eq(effects, [Remeasure])
  let (m, effects) = update(m, ToggleExpand(EditorSide))
  assert_eq(m.layout, Split)
  assert_eq(effects, [Remeasure])
  let (m, effects) = update(m, ToggleExpand(OutputSide))
  assert_eq(m.layout, OutputOnly)
  assert_eq(effects, [Remeasure])
  let (m, effects) = update(m, ToggleExpand(OutputSide))
  assert_eq(m.layout, Split)
  assert_eq(effects, [Remeasure])
}

///|
test "the button of the other pane switches the expanded pane" {
  let (m, _) = Model::start(page(), None)
  let (m, _) = update(m, ToggleExpand(EditorSide))
  let (m, effects) = update(m, ToggleExpand(OutputSide))
  assert_eq(m.layout, OutputOnly)
  assert_eq(effects, [Remeasure])
  let (m, effects) = update(m, ToggleExpand(EditorSide))
  assert_eq(m.layout, EditorOnly)
  assert_eq(effects, [Remeasure])
}

///|
test "a toggle changes nothing else, and Reset keeps the layout" {
  let (m, _) = Model::start(page(), None)
  let (expanded, _) = update(m, ToggleExpand(OutputSide))
  assert_eq(expanded, { ..m, layout: OutputOnly, })
  let (reset, effects) = update(expanded, Reset)
  assert_eq(reset.layout, OutputOnly)
  assert_false(effects.contains(Remeasure))
}

///|
test "reset loads the selected file with a fresh state" {
  let (m, _) = Model::start(two_file_page(), None)
  let (m, _) = update(m, SelectFile(1))
  let (m, _) = update(m, Edited("namespace c\n"))
  let (_, effects) = update(m, Reset)
  assert_true(
    effects.contains(
      LoadEditor(
        text="namespace b\n",
        file="b.smithy",
        fresh=true,
        language="smithy",
      ),
    ),
  )
}

///|
/// A Selector lesson: the model file and the query file.
fn query_page() -> @model.LessonPage {
  let files : Array[@model.LessonFile] = [
    { name: "model.smithy", text: start_text, },
    { name: "query.selector", text: "operation\n", },
  ]
  {
    ..page(),
    output: Some(Selector),
    files,
    digest: @model.digest(files),
    playground: Some("/smithy/playground/"),
  }
}

///|
test "a Selector lesson validates the model files and sends the query as the selector" {
  let (m, effects) = Model::start(query_page(), None)
  assert_eq(effects, [
    LoadEditor(
      text=start_text,
      file="model.smithy",
      fresh=true,
      language="smithy",
    ),
    SendValidate(seq=1, files=[("model.smithy", start_text)]),
    Wait(ms=10000, msg=TimedOut(1)),
  ])
  let (_, effects) = update(m, Answered(seq=1, answer=Checked([])))
  assert_eq(
    effects[1],
    SendTransform(
      seq=2,
      files=[("model.smithy", start_text)],
      output=Selector,
      selector=Some("operation\n"),
    ),
  )
}

///|
test "an edit of the query file transforms with the new selector" {
  let (m, _) = Model::start(query_page(), None)
  let m = run(m, [Answered(seq=1, answer=Checked([])), SelectFile(1)]).0
  let (m, effects) = run(m, [
    Answered(seq=2, answer=Converted("x")),
    Edited("string\n"),
    Debounced(1),
  ])
  assert_eq(effects, [
    SendValidate(seq=3, files=[("model.smithy", start_text)]),
    Wait(ms=10000, msg=TimedOut(3)),
  ])
  let (_, effects) = update(m, Answered(seq=3, answer=Checked([])))
  assert_eq(
    effects[1],
    SendTransform(
      seq=4,
      files=[("model.smithy", start_text)],
      output=Selector,
      selector=Some("string\n"),
    ),
  )
}

///|
test "an empty query shows the reason of the core" {
  let (m, _) = Model::start(query_page(), None)
  let m = run(m, [
      Answered(seq=1, answer=Checked([])),
      Answered(seq=2, answer=Converted("x")),
      SelectFile(1),
      Edited(""),
      Debounced(1),
      Answered(seq=3, answer=Checked([])),
    ]).0
  let reason = "I expected a selector. Write one, for example: structure"
  let (m, _) = update(m, Answered(seq=4, answer=NotConverted(reason)))
  assert_eq(m.output, NotShown(reason))
  assert_eq(m.findings, Found([]))
}

///|
test "the query file opens as plain text" {
  let (m, _) = Model::start(query_page(), None)
  let (_, effects) = update(m, SelectFile(1))
  assert_eq(effects, [
    LoadEditor(
      text="operation\n",
      file="query.selector",
      fresh=false,
      language="text",
    ),
    Mark(items=[]),
  ])
}

///|
test "Open in playground carries the query" {
  let (m, _) = Model::start(query_page(), None)
  let (m, _) = run(m, [SelectFile(1), Edited("string\n")])
  let (_, effects) = update(m, OpenPlayground)
  guard effects is [Navigate(url~)] else { fail("no navigation") }
  let fragment = url["/smithy/playground/#".length():].to_owned()
  guard @core.decode_share(fragment) is Ok(state) else { fail("bad link") }
  assert_eq(state.selector, Some("string\n"))
  assert_eq(state.model, start_text)
}

///|
let order_text : String = "{\"quantity\": 3}\n"

///|
let order_options : @samples.ValueOptions = @samples.ValueOptions::default()

///|
/// A value lesson: the model and the value file `order.json`.
fn value_page() -> @model.LessonPage {
  let files : Array[@model.LessonFile] = [
    { name: "model.smithy", text: start_text, },
    { name: "order.json", text: order_text, },
  ]
  {
    ..page(),
    engine: Value({
      file: "order.json",
      shape: "example#Order",
      options: order_options,
    }),
    output: None,
    files,
    digest: @model.digest(files),
    playground: None,
  }
}

///|
fn range_finding() -> @core.DataFinding {
  Found(
    code="Range",
    severity="error",
    path="/quantity",
    shape="example#Order",
    message="The value 0 is below the minimum 1.",
    offset=None,
  )
}

///|
fn check_value_effect(seq : Int32, value : String) -> Effect {
  SendCheckValue(
    seq~,
    files=[("model.smithy", start_text)],
    shape="example#Order",
    value~,
    options=order_options,
  )
}

///|
/// A started value lesson whose model is clean: the value check is sent
/// (request 2).
fn value_checking() -> Model {
  let (m, _) = Model::start(value_page(), None)
  update(m, Answered(seq=1, answer=Checked([]))).0
}

///|
test "a value lesson validates the model files only, then checks the value" {
  let (m, effects) = Model::start(value_page(), None)
  assert_eq(
    effects[1],
    SendValidate(seq=1, files=[("model.smithy", start_text)]),
  )
  let (m, effects) = update(m, Answered(seq=1, answer=Checked([])))
  assert_eq(m.inflight, CheckingValue)
  assert_eq(effects, [
    Mark(items=[]),
    check_value_effect(2, order_text),
    Wait(ms=10000, msg=TimedOut(2)),
  ])
}

///|
test "a value lesson with model errors does not check the value and says why" {
  let (m, _) = Model::start(value_page(), None)
  let (m, effects) = update(
    m,
    Answered(seq=1, answer=Checked([error_in("model.smithy", 3)])),
  )
  assert_false(effects.any(e => e is SendCheckValue(..)))
  assert_true(effects.contains(ShowOutput(text=not_run_text, highlight=[])))
  assert_eq(m.output, NotShown(not_run_text))
  assert_false(m.busy())
}

///|
test "the value check uses the current text of the value file" {
  let (m, _) = Model::start(value_page(), None)
  let (m, effects) = run(m, [
    SelectFile(1),
    Edited("{\"quantity\": 0}"),
    Debounced(1),
    Answered(seq=1, answer=Checked([])),
    Answered(seq=2, answer=Checked([])),
  ])
  assert_true(effects.contains(check_value_effect(3, "{\"quantity\": 0}")))
  assert_eq(m.seq, 3)
}

///|
test "the value answer shows the CLI lines and highlights the changed lines" {
  let m = value_checking()
  let first = [range_finding()]
  let (m, effects) = update(
    m,
    Answered(seq=2, answer=DataChecked(valid=false, findings=first)),
  )
  assert_eq(effects, [
    ShowOutput(text=data_text(first, "order.json"), highlight=[]),
  ])
  assert_eq(
    data_text(first, "order.json"),
    "order.json/quantity: error[Range] example#Order: The value 0 is below the minimum 1.",
  )
  // A second answer: the lines that differ from the first are highlighted.
  let second = [range_finding(), range_finding()]
  let m = run(m, [Edited("{\"quantity\": 9}"), Debounced(1)]).0
  let m = update(m, Answered(seq=3, answer=Checked([]))).0
  let (_, effects) = update(
    m,
    Answered(seq=4, answer=DataChecked(valid=false, findings=second)),
  )
  let text = data_text(second, "order.json")
  assert_eq(effects, [
    ShowOutput(
      text~,
      highlight=changed_lines(data_text(first, "order.json"), text),
    ),
  ])
}

///|
test "a value that is not JSON shows its InvalidJson line, not the old lines" {
  let m = value_checking()
  let m = update(
      m,
      Answered(
        seq=2,
        answer=DataChecked(valid=false, findings=[range_finding()]),
      ),
    ).0
  let m = run(m, [Edited("{\"quantity\": "), Debounced(1)]).0
  let m = update(m, Answered(seq=3, answer=Checked([]))).0
  let bad : Array[@core.DataFinding] = [
    Stopped(
      code="InvalidJson",
      message="I expected a value, but found the end of the text.",
      source=None,
      offset=None,
    ),
  ]
  let (_, effects) = update(
    m,
    Answered(seq=4, answer=DataChecked(valid=false, findings=bad)),
  )
  match effects[0] {
    ShowOutput(text~, ..) => {
      assert_eq(
        text, "order.json: error[InvalidJson]: I expected a value, but found the end of the text.",
      )
      assert_false(text.contains("Range"))
    }
    _ => fail("expected ShowOutput")
  }
}

///|
test "a valid value shows valid_text" {
  let (_, effects) = update(
    value_checking(),
    Answered(seq=2, answer=DataChecked(valid=true, findings=[])),
  )
  assert_eq(effects, [ShowOutput(text=valid_text, highlight=[])])
  assert_eq(valid_text, "No findings. The value is valid.")
}

///|
test "the value file opens in JSON mode" {
  let (m, _) = Model::start(value_page(), None)
  let (_, effects) = update(m, SelectFile(1))
  assert_eq(
    effects[0],
    LoadEditor(text=order_text, file="order.json", fresh=false, language="json"),
  )
}

///|
test "a value lesson opens on the Value findings tab and keeps the expand control" {
  let (m, _) = Model::start(value_page(), None)
  assert_eq(m.pane, OutputPane)
  let (m, effects) = update(m, ToggleExpand(OutputSide))
  assert_eq(m.layout, OutputOnly)
  assert_eq(effects, [Remeasure])
}

///|
test "the second timeout of a value check shows the timeout text" {
  let m = value_checking()
  let (m, _) = update(m, TimedOut(2))
  assert_true(m.retried)
  let (m, effects) = update(m, TimedOut(3))
  assert_eq(m.output, NotShown(timeout_text))
  assert_true(effects.contains(RestartWorker))
}

///|
let call_text : String = "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[42,23],\"id\":1}\n"

///|
let reply_text : String = "{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":1}\n"

///|
/// A request lesson: the model and the message file `call.json`.
fn message_page() -> @model.LessonPage {
  let files : Array[@model.LessonFile] = [
    { name: "model.smithy", text: start_text, },
    { name: "call.json", text: call_text, },
  ]
  {
    ..page(),
    engine: Message({
      file: "call.json",
      service: "example#Calculator",
      version: V2_0,
      role: Request,
      options: order_options,
    }),
    output: None,
    files,
    digest: @model.digest(files),
    playground: None,
  }
}

///|
/// A response lesson: the reply and the request that it answers.
fn response_page() -> @model.LessonPage {
  let files : Array[@model.LessonFile] = [
    { name: "model.smithy", text: start_text, },
    { name: "reply.json", text: reply_text, },
    { name: "call.json", text: call_text, },
  ]
  {
    ..message_page(),
    engine: Message({
      file: "reply.json",
      service: "example#Calculator",
      version: V2_0,
      role: Response(
        context=Some(RequestFile("call.json")),
        legacy_errors=Opaque,
      ),
      options: order_options,
    }),
    files,
    digest: @model.digest(files),
  }
}

///|
fn check_message_effect(
  seq : Int32,
  message : String,
  kind~ : @samples.MessageKind,
) -> Effect {
  SendCheckMessage(
    seq~,
    files=[("model.smithy", start_text)],
    service="example#Calculator",
    version=V2_0,
    message~,
    kind~,
    options=order_options,
  )
}

///|
fn mismatch_finding() -> @core.DataFinding {
  Found(
    code="TypeMismatch",
    severity="error",
    path="/params/1",
    shape="example#SubtractInput$subtrahend",
    message="I expected an integer, but found a string.",
    offset=None,
  )
}

///|
test "a message lesson validates the model files, then checks the message" {
  let (m, effects) = Model::start(message_page(), None)
  assert_eq(
    effects[1],
    SendValidate(seq=1, files=[("model.smithy", start_text)]),
  )
  let (m, effects) = update(m, Answered(seq=1, answer=Checked([])))
  assert_eq(m.inflight, CheckingMessage)
  assert_eq(effects, [
    Mark(items=[]),
    check_message_effect(2, call_text, kind=RequestMessage),
    Wait(ms=10000, msg=TimedOut(2)),
  ])
}

///|
test "a message lesson with model errors does not check the message and says why" {
  let (m, _) = Model::start(message_page(), None)
  let (m, effects) = update(
    m,
    Answered(seq=1, answer=Checked([error_in("model.smithy", 3)])),
  )
  assert_false(effects.any(e => e is SendCheckMessage(..)))
  assert_true(effects.contains(ShowOutput(text=not_run_text, highlight=[])))
  assert_eq(m.output, NotShown(not_run_text))
}

///|
test "a response lesson sends the text of the request file as the original request" {
  let (m, _) = Model::start(response_page(), None)
  let (m, effects) = update(m, Answered(seq=1, answer=Checked([])))
  assert_true(
    effects.contains(
      check_message_effect(
        2,
        reply_text,
        kind=ResponseMessage(
          context=Some(OriginalRequest(call_text)),
          legacy_errors=None,
        ),
      ),
    ),
  )
  // Edit call.json (the third file): the next check has the edited text.
  let edited = "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[1,2],\"id\":7}"
  let (_, effects) = run(m, [
    Answered(seq=2, answer=DataChecked(valid=true, findings=[])),
    SelectFile(2),
    Edited(edited),
    Debounced(1),
    Answered(seq=3, answer=Checked([])),
  ])
  assert_true(
    effects.contains(
      check_message_effect(
        4,
        reply_text,
        kind=ResponseMessage(
          context=Some(OriginalRequest(edited)),
          legacy_errors=None,
        ),
      ),
    ),
  )
}

///|
test "the message answer shows the CLI lines for the message file" {
  let (m, _) = Model::start(message_page(), None)
  let m = update(m, Answered(seq=1, answer=Checked([]))).0
  let findings = [mismatch_finding()]
  let (_, effects) = update(
    m,
    Answered(seq=2, answer=DataChecked(valid=false, findings~)),
  )
  let text = data_text(findings, "call.json", empty=message_valid_text)
  assert_eq(effects, [ShowOutput(text~, highlight=[])])
  assert_eq(
    text, "call.json/params/1: error[TypeMismatch] example#SubtractInput$subtrahend: I expected an integer, but found a string.",
  )
}

///|
test "a valid message shows the message text, a valid value the value text" {
  let (m, _) = Model::start(message_page(), None)
  let m = update(m, Answered(seq=1, answer=Checked([]))).0
  let (_, effects) = update(
    m,
    Answered(seq=2, answer=DataChecked(valid=true, findings=[])),
  )
  assert_eq(effects, [
    ShowOutput(text="No findings. The message is valid.", highlight=[]),
  ])
  assert_eq(message_valid_text, "No findings. The message is valid.")
  assert_eq(valid_text, "No findings. The value is valid.")
}

///|
test "a message file opens in JSON mode and a message lesson keeps the expand control" {
  let (m, _) = Model::start(message_page(), None)
  assert_eq(m.pane, OutputPane)
  let (_, effects) = update(m, SelectFile(1))
  assert_eq(
    effects[0],
    LoadEditor(text=call_text, file="call.json", fresh=false, language="json"),
  )
  let (m, effects) = update(m, ToggleExpand(OutputSide))
  assert_eq(m.layout, OutputOnly)
  assert_eq(effects, [Remeasure])
}

///|
test "the second timeout of a message check shows the timeout text" {
  let (m, _) = Model::start(message_page(), None)
  let m = update(m, Answered(seq=1, answer=Checked([]))).0
  let (m, _) = update(m, TimedOut(2))
  assert_true(m.retried)
  let (m, effects) = update(m, TimedOut(3))
  assert_eq(m.output, NotShown(timeout_text))
  assert_true(effects.contains(RestartWorker))
}

///|
let new_text : String = "$version: \"2\"\n\nnamespace example\n\nstructure Greeting {}\n\nstructure Coupon {}\n"

///|
/// A diff lesson: the old and the new model in their folders.
fn diff_page() -> @model.LessonPage {
  let files : Array[@model.LessonFile] = [
    { name: "old/model.smithy", text: start_text, },
    { name: "new/model.smithy", text: new_text, },
  ]
  {
    ..page(),
    engine: Diff,
    output: None,
    files,
    digest: @model.digest(files),
    playground: None,
  }
}

///|
fn added_coupon() -> @core.DiffEvent {
  {
    id: "AddedShape",
    severity: "NOTE",
    shape: Some("example#Coupon"),
    message: "Added structure `example#Coupon`",
  }
}

///|
fn removed_greeting() -> @core.DiffEvent {
  {
    id: "RemovedShape",
    severity: "ERROR",
    shape: Some("example#Greeting"),
    message: "Removed structure `example#Greeting`",
  }
}

///|
/// A diff lesson after its first answer: the models are clean.
fn diff_shown() -> Model {
  let (m, _) = Model::start(diff_page(), None)
  update(
    m,
    Answered(
      seq=1,
      answer=Diffed(old=[], new=[], events=Some([added_coupon()])),
    ),
  ).0
}

///|
test "a diff lesson sends one diff request and no validate" {
  let (m, effects) = Model::start(diff_page(), None)
  assert_eq(m.inflight, Diffing)
  assert_eq(
    effects[1],
    SendDiff(seq=1, old=[("old/model.smithy", start_text)], new=[
      ("new/model.smithy", new_text),
    ]),
  )
  assert_false(effects.any(e => e is SendValidate(..)))
  let (m, effects) = update(
    m,
    Answered(
      seq=1,
      answer=Diffed(old=[], new=[], events=Some([added_coupon()])),
    ),
  )
  assert_false(effects.any(e => e is (SendValidate(..) | SendTransform(..))))
  assert_false(m.waiting)
  // An edit in the new model sends the diff again.
  let (m, _) = update(m, SelectFile(1))
  let (m, _) = update(m, Edited(start_text))
  let (_, effects) = update(m, Debounced(1))
  assert_true(
    effects.contains(
      SendDiff(seq=2, old=[("old/model.smithy", start_text)], new=[
        ("new/model.smithy", start_text),
      ]),
    ),
  )
  assert_false(effects.any(e => e is SendValidate(..)))
}

///|
test "the Findings tab of a diff lesson lists the findings of both models by file" {
  let (m, _) = Model::start(diff_page(), None)
  let old = [error_in("old/model.smithy", 3)]
  let new = [error_in("new/model.smithy", 5)]
  let (m, effects) = update(
    m,
    Answered(seq=1, answer=Diffed(old~, new~, events=None)),
  )
  assert_eq(m.findings, Found([..old, ..new]))
  // The editor shows the old model first: its mark is the old finding.
  assert_eq(effects[0], Mark(items=old))
  let (_, effects) = update(m, SelectFile(1))
  assert_eq(effects[1], Mark(items=new))
  // The first model of the page has findings: the lesson opens on them.
  assert_eq(m.pane, FindingsPane)
}

///|
test "a diff answer shows the diff lines and highlights the changed lines" {
  let m = diff_shown()
  assert_eq(m.output, Shown(text=added_coupon().cli_line(), highlight=[]))
  assert_eq(m.pane, OutputPane)
  let (m, _) = update(m, SelectFile(1))
  let (m, _) = update(m, Edited(start_text + "\n"))
  let (m, _) = update(m, Debounced(1))
  let (m, effects) = update(
    m,
    Answered(
      seq=2,
      answer=Diffed(
        old=[],
        new=[],
        events=Some([added_coupon(), removed_greeting()]),
      ),
    ),
  )
  let text = added_coupon().cli_line() + "\n" + removed_greeting().cli_line()
  assert_eq(effects, [Mark(items=[]), ShowOutput(text~, highlight=[2])])
  assert_eq(m.output, Shown(text~, highlight=[2]))
}

///|
test "a diff without events shows the text for no difference" {
  let (m, _) = Model::start(diff_page(), None)
  let (_, effects) = update(
    m,
    Answered(seq=1, answer=Diffed(old=[], new=[], events=Some([]))),
  )
  assert_true(
    effects.contains(ShowOutput(text=no_difference_text, highlight=[])),
  )
  assert_eq(no_difference_text, "No differences.")
}

///|
test "a diff with a model error shows diff_not_run_text and no highlight" {
  let m = diff_shown()
  let (m, _) = update(m, SelectFile(1))
  let (m, _) = update(m, Edited("namespace\n"))
  let (m, _) = update(m, Debounced(1))
  let (m, effects) = update(
    m,
    Answered(
      seq=2,
      answer=Diffed(old=[], new=[error_in("new/model.smithy", 1)], events=None),
    ),
  )
  let text = diff_not_run_text(false, true)
  assert_eq(m.output, NotShown(text))
  assert_true(effects.contains(ShowOutput(text~, highlight=[])))
  assert_eq(
    text, "The models were not compared, because the new model has errors. See the Findings tab.",
  )
  assert_eq(
    diff_not_run_text(true, false),
    "The models were not compared, because the old model has errors. See the Findings tab.",
  )
  assert_eq(
    diff_not_run_text(true, true),
    "The models were not compared, because the old model and the new model have errors. See the Findings tab.",
  )
}

///|
test "a diff timeout twice shows the timeout text" {
  let (m, _) = Model::start(diff_page(), None)
  let (m, _) = update(m, TimedOut(1))
  assert_true(m.retried)
  let (m, effects) = update(m, TimedOut(2))
  assert_eq(m.output, NotShown(timeout_text))
  assert_eq(m.findings, NotChecked(timeout_text))
  assert_true(effects.contains(RestartWorker))
}

///|
test "a diff lesson opens on the Diff tab and keeps the expand control" {
  let (m, _) = Model::start(diff_page(), None)
  assert_eq(m.pane, OutputPane)
  let (m, effects) = update(m, ToggleExpand(OutputSide))
  assert_eq(m.layout, OutputOnly)
  assert_eq(effects, [Remeasure])
}

///|
test "each file of a diff lesson has its own editor state" {
  let (m, _) = Model::start(diff_page(), None)
  let (_, effects) = update(m, SelectFile(1))
  assert_eq(
    effects[0],
    LoadEditor(
      text=new_text,
      file="new/model.smithy",
      fresh=false,
      language="smithy",
    ),
  )
}

///|
test "Reset of a diff lesson sends the diff of the starting files" {
  let (m, _) = Model::start(diff_page(), None)
  let (m, _) = update(
    m,
    Answered(seq=1, answer=Diffed(old=[], new=[], events=Some([]))),
  )
  let (m, _) = update(m, SelectFile(1))
  let (m, _) = update(m, Edited("namespace x\n"))
  let (m, _) = update(m, Debounced(1))
  let (m, _) = update(
    m,
    Answered(seq=2, answer=Diffed(old=[], new=[], events=Some([]))),
  )
  let (m, effects) = update(m, Reset)
  assert_eq(m.inflight, Diffing)
  assert_true(
    effects.contains(
      SendDiff(seq=3, old=[("old/model.smithy", start_text)], new=[
        ("new/model.smithy", new_text),
      ]),
    ),
  )
  assert_false(effects.any(e => e is SendValidate(..)))
}

///|
let exchange_text : String = "{\"entries\": [1, 2, 3]}\n"

///|
/// A transcript lesson: the model file and the file of the transcript.
fn transcript_page() -> @model.LessonPage {
  let files : Array[@model.LessonFile] = [
    { name: "model.smithy", text: start_text, },
    { name: "exchange.json", text: exchange_text, },
  ]
  {
    ..page(),
    engine: Transcript({
      file: "exchange.json",
      protocol: "example#WeatherProtocol",
    }),
    output: None,
    files,
    digest: @model.digest(files),
    playground: None,
  }
}

///|
fn entry_of(index : Int32, sender : String) -> @core.EntryView {
  {
    index,
    sender,
    receiver: Some(if sender == "client" { "server" } else { "client" }),
    message: "{\"id\": \{index}}",
    line: None,
    column: None,
  }
}

///|
fn three_entries() -> Array[@core.EntryView] {
  [entry_of(0, "client"), entry_of(1, "server"), entry_of(2, "server")]
}

///|
fn finding_at(entry : Int32?, code : String) -> @core.FindingView {
  {
    code,
    severity: "error",
    message: "I expected a reply.",
    entry,
    line: Some(5),
    column: Some(35),
    sender: Some("client"),
    related: [],
    path: None,
    shape: None,
    operation: None,
  }
}

///|
fn summary_of(valid : Bool, errors : Int32) -> @core.SummaryView {
  {
    valid,
    complete: true,
    entries: 3,
    errors,
    outstanding: 0,
    correlation: true,
    lines: 0,
    not_json: 0,
    skipped: 0,
    expectations: None,
  }
}

///|
fn progress(
  entries~ : Array[@core.EntryView] = [],
  findings~ : Array[@core.FindingView] = [],
  checked~ : Int32 = 0,
  done~ : Bool = false,
  summary~ : @core.SummaryView? = None,
) -> Answer {
  Progress(entries~, findings~, checked~, done~, summary~)
}

///|
/// A transcript lesson after the model check and the start of the transcript:
/// three entries, none checked.
fn started() -> Model {
  let (m, _) = Model::start(transcript_page(), None)
  run(m, [
    Answered(seq=1, answer=Checked([])),
    Answered(seq=2, answer=progress(entries=three_entries())),
  ]).0
}

///|
/// Edit the transcript file, wait for the debounce, and give a clean check.
fn edit_transcript(m : Model, text : String) -> (Model, Array[Effect]) {
  let m = run(m, [SelectFile(1), Edited(text), Debounced(m.edits + 1)]).0
  update(m, Answered(seq=m.seq, answer=Checked([])))
}

///|
test "a transcript lesson validates the model files, then starts the transcript" {
  let (m, effects) = Model::start(transcript_page(), None)
  // The transcript file is not part of the model.
  assert_eq(effects, [
    LoadEditor(
      text=start_text,
      file="model.smithy",
      fresh=true,
      language="smithy",
    ),
    SendValidate(seq=1, files=[("model.smithy", start_text)]),
    Wait(ms=10000, msg=TimedOut(1)),
  ])
  assert_eq(m.pane, TranscriptPane)
  let (m, effects) = update(m, Answered(seq=1, answer=Checked([])))
  assert_eq(effects, [
    Mark(items=[]),
    SendTranscriptStart(
      seq=2,
      files=[("model.smithy", start_text)],
      protocol="example#WeatherProtocol",
      text=exchange_text,
    ),
    Wait(ms=10000, msg=TimedOut(2)),
  ])
  assert_eq(m.inflight, Transcribing)
  assert_eq(m.transcript, None)
}

///|
test "exchange.json opens in JSON mode" {
  let (m, _) = Model::start(transcript_page(), None)
  let (_, effects) = update(m, SelectFile(1))
  assert_eq(
    effects[0],
    LoadEditor(
      text=exchange_text,
      file="exchange.json",
      fresh=false,
      language="json",
    ),
  )
}

///|
test "the start answer shows the entries and checks none" {
  let m = started()
  assert_false(m.waiting)
  let t = m.transcript.unwrap()
  assert_eq(t.entries.length(), 3)
  assert_eq(t.checked, 0)
  assert_eq(t.wanted, 0)
  assert_eq(t.before, None)
}

///|
test "Step checks one entry and Run all checks the rest" {
  let m = started()
  let (m, effects) = update(m, StepClicked)
  assert_eq(effects, [
    SendTranscriptStep(seq=3, count=1),
    Wait(ms=10000, msg=TimedOut(3)),
  ])
  let (m, _) = update(m, Answered(seq=3, answer=progress(checked=1)))
  let t = m.transcript.unwrap()
  assert_eq(t.checked, 1)
  assert_eq(t.wanted, 1)
  let (m, effects) = update(m, RunAllClicked)
  assert_eq(effects, [
    SendTranscriptStep(seq=4, count=2),
    Wait(ms=10000, msg=TimedOut(4)),
  ])
  let missing = finding_at(Some(0), "MissingResponse")
  let (m, _) = update(
    m,
    Answered(
      seq=4,
      answer=progress(
        findings=[missing],
        checked=3,
        done=true,
        summary=Some(summary_of(false, 1)),
      ),
    ),
  )
  let t = m.transcript.unwrap()
  // The entries of the start stay; the step adds its findings.
  assert_eq(t.entries.length(), 3)
  assert_eq(t.findings, [missing])
  assert_true(t.done)
  assert_eq(t.wanted, 3)
  // Step and Run all do nothing at the end.
  assert_eq(update(m, StepClicked).1, [])
  assert_eq(update(m, RunAllClicked).1, [])
}

///|
test "an edit restarts the check and steps to the same position" {
  let m = started()
  let m = run(m, [StepClicked, Answered(seq=3, answer=progress(checked=1))]).0
  let m = run(m, [StepClicked, Answered(seq=4, answer=progress(checked=2))]).0
  let (m, effects) = edit_transcript(m, "{\"entries\": [1, 2, 3, 4]}\n")
  assert_eq(effects.length(), 3)
  assert_true(effects[1] is SendTranscriptStart(..))
  // The new start answer has the new entries and no check yet: it steps to
  // the position of the reader.
  let four = [..three_entries(), entry_of(3, "client")]
  let (m, effects) = update(
    m,
    Answered(seq=m.seq, answer=progress(entries=four)),
  )
  assert_eq(effects, [
    SendTranscriptStep(seq=m.seq, count=2),
    Wait(ms=10000, msg=TimedOut(m.seq)),
  ])
  let t = m.transcript.unwrap()
  assert_eq(t.entries.length(), 4)
  assert_eq(t.wanted, 2)
}

///|
test "an old position past the end runs to the end and disables Step" {
  let m = started()
  let m = run(m, [RunAllClicked, Answered(seq=3, answer=progress(checked=3))]).0
  // The reader deletes entries: two are left.
  let (m, _) = edit_transcript(m, "{\"entries\": [1, 2]}\n")
  let two = [entry_of(0, "client"), entry_of(1, "server")]
  let (m, effects) = update(
    m,
    Answered(seq=m.seq, answer=progress(entries=two)),
  )
  assert_eq(effects, [
    SendTranscriptStep(seq=m.seq, count=3),
    Wait(ms=10000, msg=TimedOut(m.seq)),
  ])
  let (m, _) = update(
    m,
    Answered(
      seq=m.seq,
      answer=progress(checked=2, done=true, summary=Some(summary_of(true, 0))),
    ),
  )
  let t = m.transcript.unwrap()
  assert_true(t.done)
  assert_eq(t.checked, 2)
  assert_eq(update(m, StepClicked).1, [])
}

///|
test "a request at a time: Step while a request runs does nothing; a stale answer is dropped" {
  let m = started()
  let (m, _) = update(m, StepClicked)
  assert_true(m.waiting)
  // Step and Run all while the request runs change nothing.
  assert_eq(update(m, StepClicked), (m, []))
  assert_eq(update(m, RunAllClicked), (m, []))
  // The answer of an older request is dropped.
  assert_eq(update(m, Answered(seq=2, answer=progress(checked=1))), (m, []))
  // An edit while the request runs: its answer does not show.
  let m = run(started(), [SelectFile(1), StepClicked]).0
  let m = update(m, Edited("{\"entries\": []}\n")).0
  let (m, effects) = update(m, Answered(seq=3, answer=progress(checked=1)))
  assert_eq(effects, [])
  let t = m.transcript.unwrap()
  assert_eq(t.checked, 0)
}

///|
test "a model with errors does not start the transcript and says why" {
  let (m, _) = Model::start(transcript_page(), None)
  let (m, effects) = update(
    m,
    Answered(seq=1, answer=Checked([error_in("model.smithy", 2)])),
  )
  assert_eq(effects, [Mark(items=[error_in("model.smithy", 2)])])
  assert_eq(m.transcript, None)
  assert_eq(m.not_run, Some(not_run_text))
  assert_eq(m.pane, FindingsPane)
  assert_eq(update(m, StepClicked).1, [])
}

///|
test "a model with errors clears the rows of the check before" {
  let m = run(started(), [
      StepClicked,
      Answered(seq=3, answer=progress(checked=1)),
    ]).0
  let m = run(m, [Edited(start_text + "x"), Debounced(m.edits + 1)]).0
  let (m, _) = update(
    m,
    Answered(seq=m.seq, answer=Checked([error_in("model.smithy", 2)])),
  )
  assert_eq(m.transcript, None)
  assert_true(m.not_run is Some(_))
}

///|
test "a missing protocol shows the reason and no rows" {
  let m = run(started(), [
      StepClicked,
      Answered(seq=3, answer=progress(checked=1)),
    ]).0
  let m = run(m, [Edited(start_text + "x"), Debounced(m.edits + 1)]).0
  let (m, _) = update(m, Answered(seq=m.seq, answer=Checked([])))
  let reason = "I found no shape example#WeatherProtocol in the model."
  let (m, _) = update(m, Answered(seq=m.seq, answer=NotConverted(reason)))
  assert_eq(m.transcript, None)
  assert_eq(m.not_run, Some(reason))
  assert_false(m.waiting)
  assert_eq(update(m, StepClicked).1, [])
}

///|
test "text that is not JSON shows its InvalidTranscript line and no old entries" {
  let m = run(started(), [
      StepClicked,
      Answered(seq=3, answer=progress(checked=1)),
    ]).0
  let (m, _) = edit_transcript(m, "{\"entries\": [")
  let invalid = { ..finding_at(None, "InvalidTranscript"), entry: None, }
  let (m, effects) = update(
    m,
    Answered(
      seq=m.seq,
      answer=progress(
        findings=[invalid],
        done=true,
        summary=Some({ ..summary_of(false, 1), entries: 0, }),
      ),
    ),
  )
  // The document has no entries, so nothing steps further.
  assert_eq(effects, [])
  let t = m.transcript.unwrap()
  assert_eq(t.entries, [])
  assert_eq(t.findings, [invalid])
  assert_true(t.done)
}

///|
test "the lines that are new since the last edit are highlighted; the first check highlights nothing" {
  let missing = finding_at(Some(0), "MissingResponse")
  let m = started()
  let m = run(m, [
      RunAllClicked,
      Answered(
        seq=3,
        answer=progress(checked=3, done=true, summary=Some(summary_of(true, 0))),
      ),
    ]).0
  let t = m.transcript.unwrap()
  assert_eq(t.before, None)
  assert_eq(t.changed_lines("exchange.json"), [])
  // An edit stores the lines on the tab.
  let (m, _) = edit_transcript(m, "{\"entries\": [1, 2]}\n")
  let t = m.transcript.unwrap()
  assert_eq(t.before, Some([]))
  let two = [entry_of(0, "client"), entry_of(1, "server")]
  let m = run(m, [
      Answered(seq=m.seq, answer=progress(entries=two)),
      Answered(
        seq=m.seq + 1,
        answer=progress(
          findings=[missing],
          checked=2,
          done=true,
          summary=Some(summary_of(false, 1)),
        ),
      ),
    ]).0
  let t = m.transcript.unwrap()
  assert_eq(t.changed_lines("exchange.json"), [
    "exchange.json:5:35: entry 0 client: error MissingResponse: I expected a reply.",
  ])
}

///|
test "the lines are not highlighted before the check reached its position" {
  let m = started()
  let m = run(m, [
      RunAllClicked,
      Answered(
        seq=3,
        answer=progress(checked=3, done=true, summary=Some(summary_of(true, 0))),
      ),
    ]).0
  let (m, _) = edit_transcript(m, "{\"entries\": [1, 2, 3]}\n")
  let m = update(
      m,
      Answered(seq=m.seq, answer=progress(entries=three_entries())),
    ).0
  // The start gave checked 0 of wanted 3, and the step is on its way.
  let t = m.transcript.unwrap()
  assert_eq(t.changed_lines("exchange.json"), [])
}

///|
test "after a timeout the new start steps back to the position of the reader" {
  let m = started()
  let (m, _) = update(m, StepClicked)
  let (m, effects) = update(m, TimedOut(3))
  assert_eq(effects[0], RestartWorker)
  assert_true(effects[1] is SendTranscriptStart(..))
  // The new Worker answers the start with no entry checked: the page sends
  // the step that timed out again.
  let (m, effects) = update(
    m,
    Answered(seq=m.seq, answer=progress(entries=three_entries())),
  )
  assert_eq(effects, [
    SendTranscriptStep(seq=m.seq, count=1),
    Wait(ms=10000, msg=TimedOut(m.seq)),
  ])
  let (m, _) = update(m, Answered(seq=m.seq, answer=progress(checked=1)))
  let t = m.transcript.unwrap()
  assert_eq(t.checked, 1)
  assert_eq(t.wanted, 1)
  assert_eq(t.entries.length(), 3)
  assert_false(m.busy())
}

///|
test "a transcript request that takes too long starts the transcript again, then gives up" {
  let m = started()
  let (m, _) = update(m, StepClicked)
  let (m, effects) = update(m, TimedOut(3))
  assert_eq(effects[0], RestartWorker)
  assert_true(effects[1] is SendTranscriptStart(..))
  assert_true(m.retried)
  let (m, effects) = update(m, TimedOut(m.seq))
  assert_eq(effects, [RestartWorker])
  assert_eq(m.transcript, None)
  assert_eq(m.not_run, Some(timeout_text))
}

///|
test "a validate that is not converted clears the rows and the steps" {
  let m = run(started(), [
      StepClicked,
      Answered(seq=3, answer=progress(checked=1)),
    ]).0
  let m = run(m, [Edited(start_text + "x"), Debounced(m.edits + 1)]).0
  assert_eq(m.inflight, Validating)
  assert_true(m.transcript is Some(_))
  let reason = "I cannot convert this model."
  let (m, _) = update(m, Answered(seq=m.seq, answer=NotConverted(reason)))
  assert_eq(m.transcript, None)
  assert_eq(m.not_run, Some(reason))
  assert_eq(update(m, StepClicked).1, [])
}

///|
test "a second validate timeout clears the rows and the steps" {
  let m = run(started(), [
      StepClicked,
      Answered(seq=3, answer=progress(checked=1)),
    ]).0
  let m = run(m, [Edited(start_text + "x"), Debounced(m.edits + 1)]).0
  assert_eq(m.inflight, Validating)
  let (m, _) = update(m, TimedOut(m.seq))
  let (m, _) = update(m, TimedOut(m.seq))
  assert_eq(m.transcript, None)
  assert_eq(m.not_run, Some(timeout_text))
  assert_eq(update(m, StepClicked).1, [])
}
