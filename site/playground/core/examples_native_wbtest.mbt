///|
/// The playground samples are files of `examples/json-rpc/`. These tests read
/// them from the checkout (the tests run in `site/`), so they run on the native target only.
fn example(name : String) -> String raise {
  @fs.read_file_to_string("../examples/json-rpc/" + name)
}

///|
fn run_all(
  model : String,
  protocol : String,
  format : TranscriptFormat,
  text : String,
  log_preset? : String,
  complete~ : Bool = false,
) -> (Array[FindingView], SummaryView) raise {
  let session = Session::new()
  ignore(
    handle(
      session,
      TranscriptStart(
        seq=1,
        model~,
        protocol~,
        format~,
        complete~,
        log_preset~,
        text~,
      ),
    ),
  )
  let (_, findings, done, summary) = progress_of(
    handle(session, TranscriptStep(seq=2, count=100000)),
  )
  assert_true(done)
  (findings, summary.unwrap())
}

///|
test "examples: peers.smithy validates and every protocol has a transcript" {
  let session = Session::new()
  match handle(session, Validate(seq=1, model=example("peers.smithy"))) {
    Diagnostics(items=[], shapes~, ..) => assert_true(shapes > 20)
    other => fail(@json.to_json(other).stringify())
  }
  let peers = example("peers.smithy")
  let chat = run_all(
    peers,
    "example.peers#EchoChat",
    Markdown,
    example("transcripts/chat.md"),
    complete=true,
  )
  assert_eq(chat.0, [])
  assert_true(chat.1.valid)
  assert_eq(chat.1.entries, 4)
  let editor = run_all(
    peers,
    "example.peers#Editor",
    Json,
    example("transcripts/editor.json"),
  )
  assert_eq(editor.0, [])
  let echo = run_all(
    peers,
    "example.peers#EchoChat",
    Markdown,
    example("transcripts/echo.md"),
  )
  assert_eq(echo.0, [])
}

///|
test "examples: the lifecycle violations match the README and the expect list" {
  let (findings, summary) = run_all(
    example("lifecycle.smithy"),
    "example.lifecycle#Lifecycle",
    Json,
    example("transcripts/lifecycle-violation.json"),
  )
  assert_eq(findings.map(f => (f.code, f.severity, f.entry)), [
    ("StateViolation", "error", Some(0)),
    ("CapabilityNotAdvertised", "error", Some(3)),
    ("CancelInactiveCall", "advisory", Some(5)),
    ("StateViolation", "error", Some(9)),
  ])
  assert_eq(findings[0].line, Some(11))
  assert_eq(findings[0].column, Some(34))
  assert_eq(summary.expectations.map(e => e.matched), Some(true))
}

///|
test "examples: the negative editor transcript reports the listed findings" {
  let (findings, summary) = run_all(
    example("peers.smithy"),
    "example.peers#Editor",
    Json,
    example("transcripts/editor-negative.json"),
  )
  assert_eq(findings.map(f => (f.code, f.entry)), [
    ("UnsolicitedResponse", Some(1)),
    ("MissingResponse", Some(0)),
    ("MissingResponse", Some(2)),
  ])
  assert_eq(summary.expectations.map(e => e.matched), Some(true))
}

///|
test "examples: the editor log gives the summary of the README" {
  let (findings, summary) = run_all(
    example("peers.smithy"),
    "example.peers#Editor",
    Jsonl,
    example("transcripts/editor.jsonl"),
    log_preset="dir-message:in=client,out=server",
  )
  assert_eq(findings, [])
  assert_eq(summary, {
    valid: true,
    complete: true,
    entries: 9,
    errors: 0,
    outstanding: 0,
    correlation: true,
    lines: 19,
    not_json: 8,
    skipped: 2,
    expectations: None,
  })
}
