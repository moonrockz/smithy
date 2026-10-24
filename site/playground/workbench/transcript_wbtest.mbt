///|
let chat_sample : @samples.TranscriptSample = {
  title: "Chat",
  path: "chat.md",
  protocol: "a#Chat",
  format: Markdown,
  version: None,
  preset: None,
  text: "---\nversion: 1.0\n---\n",
}

///|
let log_sample : @samples.TranscriptSample = {
  title: "Log",
  path: "editor.jsonl",
  protocol: "a#Editor",
  format: Jsonl,
  version: Some("2.0"),
  preset: Some(
    DirMessage([
      { value: "in", peer: "client", },
      { value: "out", peer: "server", },
    ]),
  ),
  text: "{}\n",
}

///|
let chat_protocol : Protocol = {
  id: "a#Chat",
  versions: ["1.0"],
  peers: ["client", "server"],
}

///|
let editor_protocol : Protocol = {
  id: "a#Editor",
  versions: ["1.0", "2.0"],
  peers: ["ide", "lsp"],
}

///|
fn tr_data() -> PlaygroundData {
  { ..data(), transcripts: [chat_sample, log_sample], transcript: 0, }
}

///|
/// A page whose first check has its answer, with two protocols.
fn ready() -> Model {
  ready_with([chat_protocol, editor_protocol])
}

///|
/// A page whose first check has its answer, with these protocols.
fn ready_with(protocols : Array[Protocol]) -> Model {
  let (m, _) = Model::start(tr_data())
  update(m, Answered(seq=1, answer=Validated(items=[], shapes=4, protocols~))).0
}

///|
/// The Editor protocol with the peers of the log sample.
let log_protocol : Protocol = {
  id: "a#Editor",
  versions: ["2.0"],
  peers: ["client", "server"],
}

///|
fn entry(index : Int32, line : Int32) -> Entry {
  {
    index,
    sender: "client",
    receiver: Some("server"),
    message: "{\"method\": \"echo\", \"id\": \{index}}",
    line: Some(line),
    column: Some(1),
  }
}

///|
fn finding(code : String, entry : Int32?) -> Finding {
  {
    code,
    severity: "error",
    message: "I expected something.",
    entry,
    line: None,
    column: None,
    sender: None,
    related: [],
    path: None,
    shape: None,
    operation: None,
  }
}

///|
fn progressed(
  entries~ : Array[Entry] = [],
  findings~ : Array[Finding] = [],
  checked~ : Int32,
  done~ : Bool = false,
  summary~ : Summary? = None,
) -> Answer {
  Progressed(entries~, findings~, checked~, done~, summary~)
}

///|
fn summary(entries : Int32, errors : Int32) -> Summary {
  {
    valid: errors == 0,
    complete: true,
    entries,
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
fn log_of(m : Model) -> Log raise {
  match m.tr {
    TrChecked(log) => log
    other => fail("I expected a check, but found \{other.to_repr()}")
  }
}

///|
test "transcript: the tab opens the selected transcript with its settings" {
  let (m, _) = Model::start(tr_data())
  assert_eq(m.first_transcript(), ("---\nversion: 1.0\n---\n", Markdown))
  assert_eq(m.settings, {
    protocol: "a#Chat",
    format: Markdown,
    complete: false,
    version: "",
    preset: DirMessage([]),
  })
  assert_eq(m.tr, TrIdle)
  // A page with no transcript has empty settings.
  let (empty, _) = Model::start({ ..data(), transcripts: [], transcript: 0, })
  assert_eq(empty.first_transcript(), ("", Markdown))
  assert_eq(empty.settings.protocol, "")
}

///|
test "transcript: a check lists the protocols, and a check with errors keeps them" {
  let m = ready()
  assert_eq(m.protocols, [chat_protocol, editor_protocol])
  let (m, _) = run(m, [Edited, Debounced(edits=1)])
  let (m, _) = update(
    m,
    Answered(
      seq=2,
      answer=Validated(items=[error_at(3)], shapes=0, protocols=[]),
    ),
  )
  assert_eq(m.protocols, [chat_protocol, editor_protocol])
  // A model with no error and no protocol has none.
  let (m, _) = run(m, [Edited, Debounced(edits=2)])
  let (m, _) = update(
    m,
    Answered(seq=3, answer=Validated(items=[], shapes=1, protocols=[])),
  )
  assert_eq(m.protocols, [])
  assert_eq(m.settings.protocol, "a#Chat")
}

///|
test "transcript: the choice moves to the first protocol when the model loses it" {
  let m = ready()
  let (m, _) = run(m, [Edited, Debounced(edits=1)])
  let (m, _) = update(
    m,
    Answered(
      seq=2,
      answer=Validated(items=[], shapes=1, protocols=[editor_protocol]),
    ),
  )
  assert_eq(m.settings.protocol, "a#Editor")
}

///|
test "transcript: Step starts the check, then checks one entry" {
  let m = { ..ready(), tab: TranscriptTab, }
  let (m, effects) = update(m, StepClicked)
  assert_eq(effects, [
    SendTranscriptStart(seq=2, settings=m.settings),
    Wait(ms=timeout_ms, then=TimedOut(seq=2)),
    Wait(ms=TICK_MS, then=Ticked(seq=2)),
  ])
  assert_true(m.tr_running())
  let (m, effects) = update(
    m,
    Answered(
      seq=2,
      answer=progressed(entries=[entry(0, 11), entry(1, 15)], checked=0),
    ),
  )
  assert_eq(effects, [
    SendTranscriptStep(seq=3, count=1),
    Wait(ms=timeout_ms, then=TimedOut(seq=3)),
    Wait(ms=TICK_MS, then=Ticked(seq=3)),
  ])
  assert_eq(log_of(m).entries.length(), 2)
  let (m, effects) = update(m, Answered(seq=3, answer=progressed(checked=1)))
  // The editor cursor follows the last checked entry.
  assert_eq(effects, [FollowTranscript(line=11)])
  assert_false(m.tr_running())
  assert_eq(log_of(m).checked, 1)
  // The next Step checks the next entry, with no new start.
  let (m, effects) = update(m, StepClicked)
  assert_eq(effects[0], SendTranscriptStep(seq=4, count=1))
  let (m, effects) = update(
    m,
    Answered(
      seq=4,
      answer=progressed(
        findings=[finding("TypeMismatch", Some(1))],
        checked=2,
        done=true,
        summary=Some(summary(2, 1)),
      ),
    ),
  )
  assert_eq(effects, [FollowTranscript(line=15)])
  let log = log_of(m)
  assert_true(log.done)
  assert_eq(log.findings.map(f => f.code), ["TypeMismatch"])
  // A step after the end does nothing.
  assert_eq(update(m, StepClicked).1, [])
}

///|
test "transcript: Run all checks in groups and appends the findings of each" {
  let (m, _) = update(ready(), RunAllClicked)
  let (m, effects) = update(
    m,
    Answered(
      seq=2,
      answer=progressed(
        entries=Array::makei(600, i => entry(i, i + 1)),
        checked=0,
      ),
    ),
  )
  assert_eq(effects[0], SendTranscriptStep(seq=3, count=RUN_GROUP))
  let (m, effects) = update(
    m,
    Answered(
      seq=3,
      answer=progressed(findings=[finding("A", Some(3))], checked=RUN_GROUP),
    ),
  )
  assert_eq(effects, [
    FollowTranscript(line=RUN_GROUP),
    SendTranscriptStep(seq=4, count=RUN_GROUP),
    Wait(ms=timeout_ms, then=TimedOut(seq=4)),
    Wait(ms=TICK_MS, then=Ticked(seq=4)),
  ])
  let (m, _) = update(
    m,
    Answered(
      seq=4,
      answer=progressed(
        findings=[finding("B", Some(300))],
        checked=2 * RUN_GROUP,
      ),
    ),
  )
  let (m, effects) = update(
    m,
    Answered(
      seq=5,
      answer=progressed(
        findings=[finding("C", None)],
        checked=600,
        done=true,
        summary=Some(summary(600, 3)),
      ),
    ),
  )
  assert_eq(effects, [FollowTranscript(line=600)])
  assert_eq(log_of(m).findings.map(f => f.code), ["A", "B", "C"])
  assert_false(m.tr_running())
  assert_false(m.waiting)
}

///|
test "queue: Step while a check runs waits, then the check of the newest text, then the start" {
  let (m, _) = Model::start(tr_data())
  let (m, effects) = update(m, StepClicked)
  assert_eq(effects, [])
  assert_true(m.tr_running())
  let (m, _) = run(m, [Edited, Debounced(edits=1)])
  assert_true(m.pending)
  let (m, effects) = update(
    m,
    Answered(
      seq=1,
      answer=Validated(items=[], shapes=1, protocols=[chat_protocol]),
    ),
  )
  // The answer is for older text, so it does not show. The start needs the
  // protocols of the newest text, so the check of that text goes first.
  assert_eq(effects, [
    SendValidate(seq=2),
    Wait(ms=timeout_ms, then=TimedOut(seq=2)),
    Wait(ms=TICK_MS, then=Ticked(seq=2)),
  ])
  assert_true(m.tr_running())
  let (m, effects) = update(
    m,
    Answered(
      seq=2,
      answer=Validated(items=[], shapes=1, protocols=[chat_protocol]),
    ),
  )
  assert_eq(effects, [
    Mark([]),
    SendTranscriptStart(seq=3, settings=m.settings),
    Wait(ms=timeout_ms, then=TimedOut(seq=3)),
    Wait(ms=TICK_MS, then=Ticked(seq=3)),
  ])
  // A change while the start runs: its check goes before the step that the
  // start still needs.
  let (m, _) = run(m, [Edited, Debounced(edits=2)])
  let (m, effects) = update(
    m,
    Answered(seq=3, answer=progressed(entries=[entry(0, 5)], checked=0)),
  )
  assert_eq(effects, [
    SendValidate(seq=4),
    Wait(ms=timeout_ms, then=TimedOut(seq=4)),
    Wait(ms=TICK_MS, then=Ticked(seq=4)),
  ])
  let (_, effects) = update(
    m,
    Answered(
      seq=4,
      answer=Validated(items=[], shapes=1, protocols=[chat_protocol]),
    ),
  )
  assert_eq(effects, [
    Mark([]),
    SendTranscriptStep(seq=5, count=1),
    Wait(ms=timeout_ms, then=TimedOut(seq=5)),
    Wait(ms=TICK_MS, then=Ticked(seq=5)),
  ])
}

///|
test "queue: a change during Run all is checked between two groups" {
  let (m, _) = update(ready(), RunAllClicked)
  let (m, _) = update(
    m,
    Answered(
      seq=2,
      answer=progressed(entries=Array::makei(900, i => entry(i, i)), checked=0),
    ),
  )
  // The first group runs; the model changes.
  let (m, _) = run(m, [Edited, Debounced(edits=1)])
  assert_true(m.pending)
  let (m, effects) = update(
    m,
    Answered(seq=3, answer=progressed(checked=RUN_GROUP)),
  )
  assert_eq(effects, [
    FollowTranscript(line=RUN_GROUP - 1),
    SendValidate(seq=4),
    Wait(ms=timeout_ms, then=TimedOut(seq=4)),
    Wait(ms=TICK_MS, then=Ticked(seq=4)),
  ])
  // The run goes on after the check.
  let (_, effects) = update(
    m,
    Answered(seq=4, answer=Validated(items=[], shapes=1, protocols=[])),
  )
  assert_eq(effects[1], SendTranscriptStep(seq=5, count=RUN_GROUP))
}

///|
test "queue: Run all while a transform runs waits for it" {
  let (m, _) = update(ready(), RunClicked)
  let (m, effects) = update(m, RunAllClicked)
  assert_eq(effects, [])
  let (_, effects) = update(
    m,
    Answered(
      seq=2,
      answer=Transformed(files=["a.json"], warnings=[], service=None),
    ),
  )
  assert_eq(effects[1], SendTranscriptStart(seq=3, settings=m.settings))
}

///|
test "stale: a change of the transcript or a setting starts the check again" {
  let (m, _) = update(ready(), StepClicked)
  let (m, _) = update(
    m,
    Answered(
      seq=2,
      answer=progressed(entries=[entry(0, 1), entry(1, 2)], checked=0),
    ),
  )
  let (m, _) = update(m, Answered(seq=3, answer=progressed(checked=1)))
  assert_true(m.tr_current())
  let (edited, _) = update(m, TranscriptEdited)
  assert_false(edited.tr_current())
  assert_eq(
    update(edited, StepClicked).1[0],
    SendTranscriptStart(seq=4, settings=edited.settings),
  )
  let (toggled, _) = update(m, CompleteChosen(true))
  assert_false(toggled.tr_current())
  assert_eq(
    update(toggled, RunAllClicked).1[0],
    SendTranscriptStart(seq=4, settings=toggled.settings),
  )
  // A change of the model makes the check old too.
  let (changed, _) = update(m, Edited)
  assert_false(changed.tr_current())
}

///|
test "reset: Reset clears the list and ends the session of the Worker" {
  let (m, _) = update(ready(), StepClicked)
  let (m, _) = update(
    m,
    Answered(seq=2, answer=progressed(entries=[entry(0, 1)], checked=0)),
  )
  let (m, _) = update(m, Answered(seq=3, answer=progressed(checked=1)))
  let (m, effects) = update(m, ResetClicked)
  assert_eq(m.tr, TrIdle)
  assert_eq(effects, [
    SendTranscriptReset(seq=4),
    Wait(ms=timeout_ms, then=TimedOut(seq=4)),
    Wait(ms=TICK_MS, then=Ticked(seq=4)),
  ])
  let (m, effects) = update(m, Answered(seq=4, answer=progressed(checked=0)))
  assert_eq(effects, [])
  assert_eq(m.tr, TrIdle)
  assert_eq(m.session, None)
  // With no session, Reset sends nothing.
  assert_eq(update(m, ResetClicked).1, [])
}

///|
test "reset: Reset during Run all drops the running answer and stops the run" {
  let (m, _) = update(ready(), RunAllClicked)
  let (m, effects) = update(m, ResetClicked)
  assert_eq(effects, [])
  assert_eq(m.tr, TrIdle)
  let (m, effects) = update(
    m,
    Answered(seq=2, answer=progressed(entries=[entry(0, 1)], checked=0)),
  )
  assert_eq(effects, [
    SendTranscriptReset(seq=3),
    Wait(ms=timeout_ms, then=TimedOut(seq=3)),
    Wait(ms=TICK_MS, then=Ticked(seq=3)),
  ])
  assert_eq(m.tr, TrIdle)
  let (m, effects) = update(m, Answered(seq=3, answer=progressed(checked=0)))
  assert_eq(effects, [])
  assert_false(m.tr_running())
}

///|
test "transcript: a blocked start shows the reason and its kind" {
  let (m, _) = update(ready(), RunAllClicked)
  let (m, effects) = update(
    m,
    Answered(seq=2, answer=NotRun("The model has 1 error.", ModelErrors)),
  )
  assert_eq(effects, [])
  assert_eq(m.tr, TrBlocked(reason="The model has 1 error.", by=ModelErrors))
  assert_eq(m.session, None)
  assert_false(m.tr_running())
  // The Validate tab does not change.
  assert_eq(m.check, ready().check)
}

///|
test "timeout: a transcript request that does not answer stops the check" {
  let (m, _) = update(ready(), RunAllClicked)
  let (m, effects) = update(m, TimedOut(seq=2))
  assert_eq(effects, [RestartWorker])
  assert_eq(m.tr, TrStopped)
  assert_false(m.tr_running())
  let (m, _) = update(m, RunAllClicked)
  let (m, effects) = update(m, WorkerFailed("trap"))
  assert_eq(effects, [RestartWorker])
  assert_eq(m.tr, TrFailed("trap"))
}

///|
test "timeout: a new Worker has no session, so the next Step starts again" {
  let (m, _) = update(ready(), StepClicked)
  let (m, _) = update(
    m,
    Answered(seq=2, answer=progressed(entries=[entry(0, 1)], checked=0)),
  )
  let (m, _) = update(m, Answered(seq=3, answer=progressed(checked=1)))
  let (m, _) = run(m, [Edited, Debounced(edits=1)])
  let (m, effects) = update(m, TimedOut(seq=4))
  assert_eq(effects, [RestartWorker, Mark([])])
  assert_eq(m.session, None)
  // The list stays, and the next Step starts the check again.
  assert_eq(log_of(m).checked, 1)
  assert_eq(
    update(m, StepClicked).1[0],
    SendTranscriptStart(seq=5, settings=m.settings),
  )
}

///|
test "log: a JSONL log fits its version and preset to the protocol" {
  let m = ready()
  let (m, effects) = update(m, FormatChosen(Jsonl))
  assert_eq(effects, [SetTranscriptLanguage(Jsonl)])
  // The version is the first of the protocol, and request and response go to
  // its first and second peer, as the CLI defaults.
  assert_eq(m.settings.version, "1.0")
  assert_eq(
    m.settings.preset,
    DirMessage([
      { value: "request", peer: "client", },
      { value: "response", peer: "server", },
    ]),
  )
  let (m, _) = update(m, ProtocolChosen("a#Editor"))
  assert_eq(m.settings.version, "1.0")
  assert_eq(
    m.settings.preset,
    DirMessage([
      { value: "request", peer: "ide", },
      { value: "response", peer: "lsp", },
    ]),
  )
  let (m, _) = run(m, [
    VersionChosen("2.0"),
    DirectionEdited(peer="ide", value="in"),
  ])
  assert_eq(m.settings.version, "2.0")
  assert_eq(
    m.settings.preset,
    DirMessage([
      { value: "in", peer: "ide", },
      { value: "response", peer: "lsp", },
    ]),
  )
  // An empty value leaves the peer out.
  let (m, _) = update(m, DirectionEdited(peer="lsp", value=""))
  assert_eq(m.settings.preset, DirMessage([{ value: "in", peer: "ide", }]))
  let (m, _) = update(m, PresetChosen(RawLog))
  assert_eq(m.settings.preset, Raw(sender="ide"))
  let (m, _) = update(m, SenderChosen("lsp"))
  assert_eq(m.settings.preset, Raw(sender="lsp"))
  // A version that the protocol does not declare is not taken.
  let (m, _) = update(m, VersionChosen("3.0"))
  assert_eq(m.settings.version, "2.0")
  // Back to the first protocol: the version and the peers fit it again.
  let (m, _) = update(m, ProtocolChosen("a#Chat"))
  assert_eq(m.settings.version, "1.0")
  assert_eq(m.settings.preset, Raw(sender="client"))
}

///|
test "transcript: a sample of the picker loads its text and its settings" {
  let m = ready_with([chat_protocol, log_protocol])
  let (m, effects) = update(m, TranscriptSampleChosen(1))
  assert_eq(effects, [LoadTranscript(text="{}\n", format=Jsonl)])
  assert_eq(m.transcript, 1)
  assert_eq(m.settings, {
    protocol: "a#Editor",
    format: Jsonl,
    complete: false,
    version: "2.0",
    preset: DirMessage([
      { value: "in", peer: "client", },
      { value: "out", peer: "server", },
    ]),
  })
  assert_eq(update(m, TranscriptSampleChosen(7)).1, [])
}

///|
test "transcript: a document sends no version and no preset; a log sends both" {
  let m = ready_with([chat_protocol, log_protocol])
  assert_eq(m.settings.request_version(), None)
  assert_eq(m.settings.request_preset(), None)
  let (m, _) = update(m, TranscriptSampleChosen(1))
  assert_eq(m.settings.request_version(), Some("2.0"))
  assert_eq(
    m.settings.request_preset(),
    Some(
      DirMessage([
        { value: "in", peer: "client", },
        { value: "out", peer: "server", },
      ]),
    ),
  )
}

///|
test "transcript: an entry moves the cursor of the transcript only while the check is current" {
  let (m, _) = update(ready(), StepClicked)
  let (m, _) = update(
    m,
    Answered(seq=2, answer=progressed(entries=[entry(0, 7)], checked=0)),
  )
  assert_eq(update(m, EntryChosen(line=7, column=1)).1, [
    GoToTranscript(line=7, column=1),
  ])
  let (m, _) = update(m, TranscriptEdited)
  assert_eq(update(m, EntryChosen(line=7, column=1)).1, [])
}

///|
test "log: equality compares the revision, not the entries" {
  let a = Log::start(1, Array::makei(3, i => entry(i, i)), [], 0, false, None)
  let b = Log::start(1, [], [], 0, false, None)
  assert_true(a == b)
  let c = a.add(2, [finding("A", Some(0))], 1, false, None)
  assert_false(a == c)
  assert_eq(c.entries.length(), 3)
  assert_eq(c.findings.length(), 1)
  assert_eq(a.findings.length(), 0)
}

///|
test "rows: a short transcript shows every entry" {
  assert_eq(visible_rows(3, 1, []), [Shown(0), Shown(1), Shown(2)])
}

///|
test "rows: a long transcript shows the entries near the last checked one and those with findings" {
  let rows = visible_rows(20000, 10000, [5, 6, 19999])
  let shown = rows.filter_map(row => {
    if row is Shown(i) {
      Some(i)
    } else {
      None
    }
  })
  assert_true(shown.length() <= MAX_ENTRY_ROWS)
  assert_eq(shown[:3].to_owned(), [5, 6, 9900])
  assert_true(shown.contains(9999))
  assert_true(shown.contains(19999))
  // A gap between two shown entries is one row with its size.
  assert_eq(rows[0], Hidden(5))
  assert_eq(rows[3], Hidden(9900 - 7))
  let hidden = rows.fold(init=0, (n, row) => {
    match row {
      Hidden(count) => n + count
      Shown(_) => n + 1
    }
  })
  assert_eq(hidden, 20000)
  // At the start, the window is the first entries.
  let first = visible_rows(20000, 0, [])
  assert_eq(first[0], Shown(0))
  assert_eq(first[first.length() - 1], Hidden(20000 - WINDOW_ROWS))
}

///|
test "hint: the transcript names the CLI command that gives the same findings" {
  let settings : Settings = {
    protocol: "a#Chat",
    format: Markdown,
    complete: false,
    version: "",
    preset: DirMessage([]),
  }
  assert_eq(
    transcript_hint(settings),
    "smithy validate rpc transcript --protocol a#Chat model.smithy transcript.md",
  )
  assert_eq(
    transcript_hint({ ..settings, format: Json, complete: true, }),
    "smithy validate rpc transcript --protocol a#Chat --complete model.smithy transcript.json",
  )
  assert_eq(
    transcript_hint({
      ..settings,
      format: Jsonl,
      version: "2.0",
      preset: DirMessage([{ value: "in", peer: "client", }]),
    }),
    "smithy validate rpc transcript --protocol a#Chat --version 2.0 --log-preset dir-message --direction in=client model.smithy transcript.jsonl",
  )
  assert_eq(
    transcript_hint({
      ..settings,
      format: Jsonl,
      version: "1.0",
      preset: Raw(sender="client"),
    }),
    "smithy validate rpc transcript --protocol a#Chat --version 1.0 --log-preset raw --sender client model.smithy transcript.jsonl",
  )
}

///|
test "stale: a version or preset does not make the check of a document old" {
  // The first model has errors, so the settings do not fit a protocol yet.
  let (m, _) = Model::start(tr_data())
  let (m, _) = update(
    m,
    Answered(
      seq=1,
      answer=Validated(items=[error_at(1)], shapes=0, protocols=[]),
    ),
  )
  let (m, _) = update(m, StepClicked)
  let (m, _) = run(m, [Edited, Debounced(edits=1)])
  let (m, _) = update(
    m,
    Answered(seq=2, answer=progressed(entries=[entry(0, 1)], checked=0)),
  )
  // The check of the new model fits the version and the preset.
  let (m, _) = update(
    m,
    Answered(
      seq=3,
      answer=Validated(items=[], shapes=1, protocols=[chat_protocol]),
    ),
  )
  assert_true(m.settings.preset != m.session.unwrap().settings.preset)
  // The model changed after the start, so this check is old for that reason.
  assert_false(m.tr_current())
  let m = { ..m, session: m.session.map(s => { ..s, model_edits: m.edits, }), }
  assert_true(m.tr_current())
  // For a log, the version and the preset count.
  let (log, _) = update(m, FormatChosen(Jsonl))
  assert_false(log.tr_current())
}

///|
test "transcript: a sample fits its settings to the protocols of the model" {
  // The model has no a#Editor: the first protocol and its version. Its peers
  // are those of the preset, so the preset stays.
  let (m, _) = update(ready_with([chat_protocol]), TranscriptSampleChosen(1))
  assert_eq(m.settings, {
    protocol: "a#Chat",
    format: Jsonl,
    complete: false,
    version: "1.0",
    preset: DirMessage([
      { value: "in", peer: "client", },
      { value: "out", peer: "server", },
    ]),
  })
  assert_eq(
    transcript_hint(m.settings),
    "smithy validate rpc transcript --protocol a#Chat --version 1.0 --log-preset dir-message --direction in=client --direction out=server model.smithy transcript.jsonl",
  )
  // Peers that the protocol does not have give its default preset.
  let (m, _) = update(ready(), TranscriptSampleChosen(1))
  assert_eq(m.settings.protocol, "a#Editor")
  assert_eq(m.settings.version, "2.0")
  assert_eq(
    m.settings.preset,
    DirMessage([
      { value: "request", peer: "ide", },
      { value: "response", peer: "lsp", },
    ]),
  )
}

///|
test "queue: Step before the check of a new model waits for that check, then starts with fitted settings" {
  // The page opens with a model with errors: no protocols, so the settings do not fit yet.
  let (m, _) = Model::start(tr_data())
  let (m, _) = update(
    m,
    Answered(
      seq=1,
      answer=Validated(items=[error_at(1)], shapes=0, protocols=[]),
    ),
  )
  let (m, _) = update(m, TranscriptSampleChosen(1))
  // A new model: its check waits for the end of the change.
  let (m, _) = update(m, Edited)
  let (m, effects) = update(m, StepClicked)
  assert_eq(effects, [])
  assert_true(m.tr_running())
  let (m, effects) = update(m, Debounced(edits=1))
  assert_eq(effects, [
    SendValidate(seq=2),
    Wait(ms=timeout_ms, then=TimedOut(seq=2)),
    Wait(ms=TICK_MS, then=Ticked(seq=2)),
  ])
  let (m, effects) = update(
    m,
    Answered(
      seq=2,
      answer=Validated(items=[], shapes=1, protocols=[editor_protocol]),
    ),
  )
  let fitted : Settings = {
    protocol: "a#Editor",
    format: Jsonl,
    complete: false,
    version: "2.0",
    preset: DirMessage([
      { value: "request", peer: "ide", },
      { value: "response", peer: "lsp", },
    ]),
  }
  assert_eq(m.settings, fitted)
  assert_eq(effects, [
    Mark([]),
    SendTranscriptStart(seq=3, settings=fitted),
    Wait(ms=timeout_ms, then=TimedOut(seq=3)),
    Wait(ms=TICK_MS, then=Ticked(seq=3)),
  ])
}

///|
test "queue: a stopped check does not hold a Step back" {
  let (m, _) = Model::start(tr_data())
  let (m, _) = update(m, TimedOut(seq=1))
  let (_, effects) = update(m, StepClicked)
  assert_eq(effects[0], SendTranscriptStart(seq=2, settings=m.settings))
}

///|
test "hint: a value that the shell splits is quoted" {
  let settings : Settings = {
    protocol: "a#Chat",
    format: Jsonl,
    complete: false,
    version: "2.0",
    preset: DirMessage([
      { value: "in out", peer: "client", },
      { value: "it's", peer: "server", },
    ]),
  }
  assert_eq(
    transcript_hint(settings),
    "smithy validate rpc transcript --protocol a#Chat --version 2.0 --log-preset dir-message --direction 'in out=client' --direction 'it'\\''s=server' model.smithy transcript.jsonl",
  )
}
