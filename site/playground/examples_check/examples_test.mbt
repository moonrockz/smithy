///|
/// The files of `examples/json-rpc/`; the tests run in `site/`.
fn example(name : String) -> String raise {
  @fs.read_file_to_string("../examples/json-rpc/" + name)
}

///|
/// The chat transcript of the mockup: a wrong result and a call without a reply.
let chat_markdown : String =
  #|---
  #|version: 1.0
  #|complete: true
  #|---
  #|```jsonrpc client -> server
  #|{"method": "postMessage", "params": ["Hello all!"], "id": 99}
  #|```
  #|
  #|```jsonrpc server -> client
  #|{"method": "handleMessage", "params": ["user1", "I'm in!"], "id": null}
  #|```
  #|
  #|```jsonrpc server
  #|{"result": "one", "error": null, "id": 99}
  #|```
  #|
  #|```jsonrpc client -> server
  #|{"method": "echo", "params": [], "id": 100}
  #|```

///|
priv struct Progress {
  entries : Array[@core.EntryView]
  findings : Array[@core.FindingView]
  done : Bool
  summary : @core.SummaryView?
}

///|
fn progress_of(response : @core.Response) -> Progress raise {
  match response {
    TranscriptProgress(entries~, findings~, done~, summary~, ..) =>
      { entries, findings, done, summary, }
    other =>
      fail("I expected progress, but found \{@json.to_json(other).stringify()}")
  }
}

///|
fn start(
  session : @core.Session,
  model : String,
  protocol : String,
  format : @core.TranscriptFormat,
  text : String,
  complete~ : Bool = false,
  log_preset? : String,
  version? : String,
) -> @core.Response {
  session.start_transcript(
    seq=1,
    model~,
    protocol~,
    format~,
    complete~,
    log_preset~,
    text~,
    version?,
  )
}

///|
fn run_all(
  model : String,
  protocol : String,
  format : @core.TranscriptFormat,
  text : String,
  complete~ : Bool = false,
  log_preset? : String,
  version? : String,
) -> (Array[@core.FindingView], @core.SummaryView) raise {
  let session = @core.Session::new()
  ignore(
    start(
      session,
      model,
      protocol,
      format,
      text,
      complete~,
      log_preset?,
      version?,
    ),
  )
  let { findings, done, summary, .. } = progress_of(
    @core.handle(session, TranscriptStep(seq=2, count=100000)),
  )
  assert_true(done)
  (findings, summary.unwrap())
}

///|
test "examples: peers.smithy validates and every protocol has a transcript" {
  let session = @core.Session::new()
  let peers = example("peers.smithy")
  match @core.handle(session, Validate(seq=1, model=peers)) {
    Diagnostics(items=[], shapes~, ..) => assert_true(shapes > 20)
    other => fail(@json.to_json(other).stringify())
  }
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
    version="2.0",
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

///|
/// The core against the library: the findings and the summary that
/// `@rpc.run_transcript` gives for the same document, for Run all and for
/// stepping one entry at a time.
fn differential(
  model : String,
  protocol : String,
  format : @core.TranscriptFormat,
  text : String,
  complete : Bool,
) -> Unit raise {
  let (document, read_findings) = match format {
    Markdown => @rpc.read_markdown_transcript(text)
    _ => @rpc.read_json_transcript(text)
  }
  let assembled = @rpc.loader().add_idl("model.smithy", model).assemble().model.unwrap()
  let description = @rpc.ProtocolDescription::from_smithy(
    assembled,
    @smithy.ShapeId::parse(protocol).unwrap(),
    document.version.unwrap(),
  )
  let run = @rpc.run_transcript(
    description,
    document,
    read_findings,
    completeness?=if complete { Some(@rpc.Complete) } else { None },
  )
  let findings = run.findings.map(@core.FindingView::from_finding)
  let errors = run.findings
    .filter(f => f.severity == @validation.Error)
    .length()
  let summary : @core.SummaryView = {
    valid: run.summary.complete && errors == 0,
    complete: run.summary.complete,
    entries: run.summary.entries,
    errors,
    outstanding: run.summary.outstanding,
    correlation: run.summary.correlation,
    lines: 0,
    not_json: 0,
    skipped: 0,
    expectations: run.expectations.map(result => {
      matched: result.is_match(),
      missing: result.missing.map(e => {
        code: e.code(),
        entry: e.entry(),
        related: e.related(),
      }),
      unexpected: result.unexpected
      .filter(f => f.severity == @validation.Error)
      .map(@core.FindingView::from_finding),
    }),
  }
  // Run all
  let all = run_all(model, protocol, format, text, complete~)
  assert_eq(all.0, findings)
  assert_eq(all.1, summary)
  // One entry at a time
  let session = @core.Session::new()
  let mut last = progress_of(
    start(session, model, protocol, format, text, complete~),
  )
  let mut steps = 0
  while !last.done && steps < 1000 {
    last = progress_of(@core.handle(session, TranscriptStep(seq=2, count=1)))
    steps += 1
  }
  assert_true(last.done)
  assert_eq(last.findings, findings)
  assert_eq(last.summary, Some(summary))
}

///|
test "differential: the core equals run_transcript for the examples" {
  let peers = example("peers.smithy")
  differential(peers, "example.peers#EchoChat", Markdown, chat_markdown, true)
  differential(peers, "example.peers#EchoChat", Markdown, chat_markdown, false)
  differential(
    peers,
    "example.peers#EchoChat",
    Markdown,
    example("transcripts/chat.md"),
    false,
  )
  differential(
    peers,
    "example.peers#Editor",
    Json,
    example("transcripts/editor.json"),
    false,
  )
  differential(
    peers,
    "example.peers#Editor",
    Json,
    example("transcripts/editor-negative.json"),
    false,
  )
  differential(
    example("lifecycle.smithy"),
    "example.lifecycle#Lifecycle",
    Json,
    example("transcripts/lifecycle-violation.json"),
    false,
  )
}

///|
test "differential: a document with no version gives its read findings" {
  let text = "---\nversion: 9\n---\n```jsonrpc client -> server\n{}\n```\n"
  let (document, read_findings) = @rpc.read_markdown_transcript(text)
  assert_true(document.version is None)
  assert_true(read_findings.any(f => f.severity == @validation.Error))
  let session = @core.Session::new()
  let { entries, findings, done, summary, } = progress_of(
    start(
      session,
      example("peers.smithy"),
      "example.peers#EchoChat",
      Markdown,
      text,
    ),
  )
  assert_eq(findings, read_findings.map(@core.FindingView::from_finding))
  assert_eq(entries.length(), document.entries.length())
  assert_true(done)
  let summary = summary.unwrap()
  assert_false(summary.valid)
  assert_false(summary.complete)
  assert_eq(summary.errors, read_findings.length())
}
