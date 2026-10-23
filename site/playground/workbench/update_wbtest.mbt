///|
fn data() -> PlaygroundData {
  {
    version: "0.0.1",
    worker: "/smithy/playground/worker.js",
    samples: [
      { title: "Good", path: "a.smithy", model: "namespace a\n", },
      { title: "Bad", path: "b.smithy", model: "namespace b\nstructure S {", },
    ],
    selected: 1,
  }
}

///|
fn error_at(line : Int32) -> Diagnostic {
  {
    severity: "ERROR",
    code: "Target.UnresolvedShape",
    message: "I could not resolve shape a#Intger, referenced by a#S$count.",
    file: "model.smithy",
    start_line: line,
    start_column: 5,
    end_line: line,
    end_column: 18,
    shape: Some("a#S$count"),
  }
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
/// A started page whose first check has its answer.
fn answered() -> Model {
  let (m, _) = Model::start(data())
  update(m, Answered(seq=1, answer=Validated(items=[], shapes=1))).0
}

///|
test "start: the playground checks the selected sample at once" {
  let (m, effects) = Model::start(data())
  assert_eq(m.sample, 1)
  assert_eq(m.seq, 1)
  assert_true(m.waiting)
  assert_eq(m.check, Unchecked)
  assert_eq(effects, [
    SendValidate(seq=1),
    Wait(ms=timeout_ms, then=TimedOut(seq=1)),
  ])
}

///|
test "start: a selection out of range opens the first sample" {
  let (m, _) = Model::start({ ..data(), selected: 7, })
  assert_eq(m.sample, 0)
}

///|
test "edit: a change waits 250 ms before the check" {
  let (m, _) = Model::start(data())
  let (m, effects) = update(m, Edited)
  assert_eq(m.edits, 1)
  assert_eq(effects, [Wait(ms=250, then=Debounced(edits=1))])
}

///|
test "edit: only the wait of the last change sends a request" {
  let m = answered()
  let (m, _) = run(m, [Edited, Edited, Edited])
  let (m, early) = update(m, Debounced(edits=2))
  assert_eq(early, [])
  assert_eq(m.seq, 1)
  let (m, effects) = update(m, Debounced(edits=3))
  assert_eq(m.seq, 2)
  assert_true(m.waiting)
  assert_eq(effects, [
    SendValidate(seq=2),
    Wait(ms=timeout_ms, then=TimedOut(seq=2)),
  ])
}

///|
test "answer: the answer to the newest request shows and marks the editor" {
  let (m, _) = Model::start(data())
  let (m, effects) = update(
    m,
    Answered(seq=1, answer=Validated(items=[error_at(2)], shapes=0)),
  )
  assert_false(m.waiting)
  assert_eq(m.check, Checked(items=[error_at(2)], shapes=0))
  assert_eq(m.errors(), 1)
  assert_eq(effects, [Mark([error_at(2)])])
}

///|
test "answer: an answer to an older request never replaces a newer result" {
  let m = answered()
  let (m, _) = run(m, [Edited, Debounced(edits=1)])
  assert_eq(m.seq, 2)
  // An answer to the old request after the new one was sent is dropped.
  let (m, stale) = update(
    m,
    Answered(seq=1, answer=Validated(items=[error_at(2)], shapes=0)),
  )
  assert_eq(stale, [])
  assert_true(m.waiting)
  assert_eq(m.check, Checked(items=[], shapes=1))
  let (m, _) = update(m, Answered(seq=2, answer=Validated(items=[], shapes=4)))
  assert_eq(m.check, Checked(items=[], shapes=4))
  // A late answer for the old text after the new one changes nothing.
  let (late, effects) = update(
    m,
    Answered(seq=1, answer=Validated(items=[error_at(2)], shapes=0)),
  )
  assert_eq(late, m)
  assert_eq(effects, [])
}

///|
test "answer: a refused request shows the reason and clears the marks" {
  let (m, _) = Model::start(data())
  let (m, effects) = update(m, Answered(seq=1, answer=NotRun("No.", Other)))
  assert_eq(m.check, Refused("No."))
  assert_eq(effects, [Mark([])])
}

///|
test "timeout: a Worker that does not answer in time is replaced" {
  let (m, _) = Model::start(data())
  let (m, effects) = update(m, TimedOut(seq=1))
  assert_false(m.waiting)
  assert_eq(m.check, Stopped)
  assert_eq(effects, [RestartWorker, Mark([])])
  // The answer of the stopped Worker can no longer arrive, but it is
  // dropped if it does.
  let (m2, late) = update(
    m,
    Answered(seq=1, answer=Validated(items=[], shapes=1)),
  )
  assert_eq(m2, m)
  assert_eq(late, [])
}

///|
test "timeout: the timer of an answered request does nothing" {
  let (m, _) = Model::start(data())
  let (m, _) = update(m, Answered(seq=1, answer=Validated(items=[], shapes=1)))
  let (m2, effects) = update(m, TimedOut(seq=1))
  assert_eq(m2, m)
  assert_eq(effects, [])
}

///|
test "timeout: the timer of an older request does nothing" {
  let m = answered()
  let (m, _) = run(m, [Edited, Debounced(edits=1)])
  let (m2, effects) = update(m, TimedOut(seq=1))
  assert_eq(m2, m)
  assert_eq(effects, [])
}

///|
test "timeout: the next change checks again with the new Worker" {
  let (m, _) = Model::start(data())
  let (m, _) = update(m, TimedOut(seq=1))
  let (m, effects) = run(m, [Edited, Debounced(edits=1)])
  assert_eq(m.seq, 2)
  assert_eq(effects, [
    SendValidate(seq=2),
    Wait(ms=timeout_ms, then=TimedOut(seq=2)),
  ])
}

///|
test "sample: a new sample replaces the editor text" {
  let (m, _) = Model::start(data())
  let (m, effects) = update(m, SampleChosen(0))
  assert_eq(m.sample, 0)
  assert_eq(effects, [LoadText("namespace a\n")])
  let (m2, none) = update(m, SampleChosen(9))
  assert_eq(m2, m)
  assert_eq(none, [])
}

///|
test "cursor and tabs: the status and the tab follow the messages" {
  let (m, _) = Model::start(data())
  let (m, _) = update(m, CursorMoved(line=4, column=7))
  assert_eq((m.line, m.column), (4, 7))
  let (m, _) = update(m, TabChosen(TransformTab))
  assert_eq(m.tab, TransformTab)
}

///|
test "diagnostic: a click moves the cursor to its place" {
  let m = answered()
  let (_, effects) = update(m, DiagnosticChosen(line=46, column=31))
  assert_eq(effects, [MoveCursor(line=46, column=31)])
}

///|
test "errors: warnings do not count as errors" {
  let (m, _) = Model::start(data())
  let warning = { ..error_at(1), severity: "WARNING", }
  let danger = { ..error_at(3), severity: "DANGER", }
  let (m, _) = update(
    m,
    Answered(
      seq=1,
      answer=Validated(items=[warning, error_at(2), danger], shapes=1),
    ),
  )
  assert_eq(m.errors(), 2)
  assert_eq(m.warnings(), 1)
}

///|
test "answer: an answer for text that changed after the request is dropped" {
  let (m, _) = Model::start(data())
  // The text changes while the first request runs; its wait has not ended.
  let (m, _) = update(m, Edited)
  let (m, effects) = update(
    m,
    Answered(seq=1, answer=Validated(items=[error_at(2)], shapes=0)),
  )
  assert_eq(effects, [])
  assert_eq(m.check, Unchecked)
  assert_false(m.waiting)
  // The wait ends and the new text is checked.
  let (m, _) = update(m, Debounced(edits=1))
  let (m, _) = update(m, Answered(seq=2, answer=Validated(items=[], shapes=1)))
  assert_eq(m.check, Checked(items=[], shapes=1))
  assert_false(m.waiting)
}

///|
test "queue: a change while a request runs does not post" {
  let (m, _) = Model::start(data())
  let (m, effects) = run(m, [Edited, Debounced(edits=1)])
  assert_eq(effects, [])
  assert_eq(m.seq, 1)
  assert_true(m.pending)
}

///|
test "queue: the answer then posts the newest text once" {
  let (m, _) = Model::start(data())
  let (m, _) = run(m, [Edited, Debounced(edits=1), Edited, Debounced(edits=2)])
  assert_eq(m.seq, 1)
  // The answer is for older text: it does not show, and the newest text goes.
  let (m, effects) = update(
    m,
    Answered(seq=1, answer=Validated(items=[error_at(2)], shapes=0)),
  )
  assert_eq(m.check, Unchecked)
  assert_eq(m.seq, 2)
  assert_false(m.pending)
  assert_eq(effects, [
    SendValidate(seq=2),
    Wait(ms=timeout_ms, then=TimedOut(seq=2)),
  ])
  let (m, effects) = update(
    m,
    Answered(seq=2, answer=Validated(items=[], shapes=1)),
  )
  assert_eq(m.check, Checked(items=[], shapes=1))
  assert_eq(effects, [Mark([])])
}

///|
test "queue: an answer before the wait of a change ends lets the wait send" {
  let (m, _) = Model::start(data())
  let (m, _) = update(m, Edited)
  let (m, effects) = update(
    m,
    Answered(seq=1, answer=Validated(items=[], shapes=1)),
  )
  assert_eq(effects, [])
  assert_false(m.waiting)
  let (m, effects) = update(m, Debounced(edits=1))
  assert_eq(m.seq, 2)
  assert_eq(effects, [
    SendValidate(seq=2),
    Wait(ms=timeout_ms, then=TimedOut(seq=2)),
  ])
}

///|
test "queue: a timeout with a pending change posts the newest text to the new Worker" {
  let (m, _) = Model::start(data())
  let (m, _) = run(m, [Edited, Debounced(edits=1)])
  let (m, effects) = update(m, TimedOut(seq=1))
  assert_eq(m.check, Stopped)
  assert_eq(m.seq, 2)
  assert_true(m.waiting)
  assert_false(m.pending)
  assert_eq(effects, [
    RestartWorker,
    Mark([]),
    SendValidate(seq=2),
    Wait(ms=timeout_ms, then=TimedOut(seq=2)),
  ])
}

///|
test "failure: a Worker error restarts the Worker at once and says that the check failed" {
  let (m, _) = Model::start(data())
  let (m, effects) = update(m, WorkerFailed("RuntimeError: unreachable"))
  assert_false(m.waiting)
  assert_eq(m.check, Failed("RuntimeError: unreachable"))
  assert_eq(effects, [RestartWorker, Mark([])])
  // A second error, with no request, does not restart again.
  let (m2, again) = update(m, WorkerFailed("x"))
  assert_eq(m2, m)
  assert_eq(again, [])
}

///|
test "failure: a Worker error with a pending change posts the newest text" {
  let (m, _) = Model::start(data())
  let (m, _) = run(m, [Edited, Debounced(edits=1)])
  let (m, effects) = update(m, WorkerFailed(""))
  assert_eq(m.check, Failed(""))
  assert_eq(effects, [
    RestartWorker,
    Mark([]),
    SendValidate(seq=2),
    Wait(ms=timeout_ms, then=TimedOut(seq=2)),
  ])
}

///|
test "stale: a result for older text does not move the cursor" {
  let (m, _) = Model::start(data())
  let (m, _) = update(
    m,
    Answered(seq=1, answer=Validated(items=[error_at(2)], shapes=0)),
  )
  assert_true(m.is_current())
  let (stale, _) = update(m, Edited)
  assert_false(stale.is_current())
  let (_, effects) = update(stale, DiagnosticChosen(line=2, column=5))
  assert_eq(effects, [])
  // While the newest text is checked, the old rows stay stale.
  let (checking, _) = update(stale, Debounced(edits=1))
  assert_false(checking.is_current())
}

///|
fn done_files(names : Array[String]) -> Answer {
  Transformed(files=names, warnings=["WARNING: a#S: OpenAPI omits something"])
}

///|
test "transform: Run sends the output and, for a selector, the selector" {
  let m = answered()
  let (m, effects) = update(m, RunClicked)
  assert_eq(m.tx, TxRunning)
  assert_eq(effects, [
    SendTransform(seq=2, output=JsonAst, selector=None),
    Wait(ms=timeout_ms, then=TimedOut(seq=2)),
  ])
  let m = answered()
  let (m, _) = run(m, [OutputChosen(Selector), SelectorEdited("string")])
  let (_, effects) = update(m, RunClicked)
  assert_eq(
    effects[0],
    SendTransform(seq=2, output=Selector, selector=Some("string")),
  )
}

///|
test "transform: the answer shows the first file and keeps the warnings" {
  let (m, _) = update(answered(), RunClicked)
  let (m, effects) = update(
    m,
    Answered(seq=2, answer=done_files(["a.smithy", "b.smithy"])),
  )
  assert_false(m.waiting)
  assert_eq(effects, [ShowFile(0)])
  assert_eq(
    m.tx,
    TxDone(
      output=JsonAst,
      files=["a.smithy", "b.smithy"],
      warnings=["WARNING: a#S: OpenAPI omits something"],
      file=0,
      edits=0,
    ),
  )
  // A second file shows on request, and Copy and Download name it.
  let (m, effects) = update(m, FileChosen(1))
  assert_eq(effects, [ShowFile(1)])
  assert_eq(update(m, CopyClicked).1, [CopyFile(1)])
  assert_eq(update(m, DownloadClicked).1, [DownloadFile(1)])
  assert_eq(update(m, FileChosen(5)).1, [])
  // The clipboard answer shows once, and a new run clears it.
  let (m, _) = update(m, CopyDone(true))
  assert_eq(m.copy, Copied)
  let (m, _) = update(m, RunClicked)
  assert_eq(m.copy, NotCopied)
}

///|
test "transform: Copy and Download do nothing before an output exists" {
  let m = answered()
  assert_eq(update(m, CopyClicked).1, [])
  assert_eq(update(m, DownloadClicked).1, [])
}

///|
test "transform: a blocked run keeps its kind, so the page chooses its copy" {
  let (m, _) = update(answered(), RunClicked)
  let (errors, _) = update(
    m,
    Answered(seq=2, answer=NotRun("The model has 1 error.", ModelErrors)),
  )
  assert_eq(
    errors.tx,
    TxBlocked(reason="The model has 1 error.", by=ModelErrors),
  )
  let (other, _) = update(
    m,
    Answered(seq=2, answer=NotRun("I found no service in the model.", Other)),
  )
  assert_eq(
    other.tx,
    TxBlocked(reason="I found no service in the model.", by=Other),
  )
  // The check of the Validate tab does not change.
  assert_eq(other.check, answered().check)
}

///|
test "queue: Run while a check runs waits, and goes before the pending check" {
  // Start: the first check runs.
  let (m, _) = Model::start(data())
  let (m, effects) = update(m, RunClicked)
  assert_eq(effects, [])
  assert_true(m.run_pending)
  assert_eq(m.tx, TxRunning)
  // A change while the check runs also waits.
  let (m, _) = update(m, Edited)
  let (m, effects) = update(m, Debounced(edits=1))
  assert_eq(effects, [])
  assert_true(m.pending)
  // The check ends: only the transform goes to the Worker.
  let (m, effects) = update(
    m,
    Answered(seq=1, answer=Validated(items=[], shapes=1)),
  )
  // The answer is for older text, so it does not show.
  assert_eq(effects.length(), 2)
  assert_eq(effects[0], SendTransform(seq=2, output=JsonAst, selector=None))
  assert_false(m.run_pending)
  assert_true(m.pending)
  assert_eq(m.inflight, Transforming)
  // The transform ends: the newest text goes next, once.
  let (m, effects) = update(
    m,
    Answered(seq=2, answer=done_files(["model.json"])),
  )
  assert_eq(effects, [
    ShowFile(0),
    SendValidate(seq=3),
    Wait(ms=timeout_ms, then=TimedOut(seq=3)),
  ])
  assert_eq(m.inflight, Validating)
  assert_false(m.pending)
}

///|
test "queue: a change while a transform runs posts nothing until it ends" {
  let (m, _) = update(answered(), RunClicked)
  let (m, _) = update(m, Edited)
  let (m, effects) = update(m, Debounced(edits=1))
  assert_eq(effects, [])
  // A second Run does not queue a second transform.
  let (m, effects) = update(m, RunClicked)
  assert_eq(effects, [])
  assert_false(m.run_pending)
  // The output shows for the old text, and the tab can see that.
  let (m, _) = update(m, Answered(seq=2, answer=done_files(["model.json"])))
  match m.tx {
    TxDone(edits~, ..) => assert_eq(edits, 0)
    _ => fail("I expected TxDone.")
  }
  assert_eq(m.edits, 1)
  assert_eq(m.seq, 3)
}

///|
test "queue: a transform that is stale at its answer still shows" {
  let (m, _) = update(answered(), RunClicked)
  let (m, _) = update(m, Edited)
  let (m, _) = update(m, Answered(seq=2, answer=done_files(["model.json"])))
  assert_true(m.tx is TxDone(..))
}

///|
test "queue: a transform that times out restarts the Worker and keeps the check" {
  let (m, _) = update(answered(), RunClicked)
  let check = m.check
  let (m, effects) = update(m, TimedOut(seq=2))
  assert_eq(m.tx, TxStopped)
  assert_eq(effects, [RestartWorker])
  assert_eq(m.check, check)
  assert_false(m.waiting)
  // Run again works at once.
  assert_eq(update(m, RunClicked).1.length(), 2)
}

///|
test "queue: a Worker error during a transform shows in the tab only" {
  let (m, _) = update(answered(), RunClicked)
  let check = m.check
  let (m, effects) = update(m, WorkerFailed("boom"))
  assert_eq(m.tx, TxFailed("boom"))
  assert_eq(effects, [RestartWorker])
  assert_eq(m.check, check)
}

///|
test "queue: a check that times out with a Run waiting sends the transform" {
  let (m, _) = Model::start(data())
  let (m, _) = update(m, RunClicked)
  let (m, effects) = update(m, TimedOut(seq=1))
  assert_eq(m.check, Stopped)
  assert_eq(effects[0], RestartWorker)
  assert_eq(effects[2], SendTransform(seq=2, output=JsonAst, selector=None))
}

///|
test "stale: the diagnostics stay current while a transform runs" {
  let (m, _) = update(answered(), RunClicked)
  assert_true(m.is_current())
  assert_false(m.checking())
}
