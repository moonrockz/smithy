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
/// One response of the core: the entries and findings are the change since
/// the previous response.
priv struct Progress {
  entries : Array[@core.EntryView]
  findings : Array[@core.FindingView]
  checked : Int32
  done : Bool
  summary : @core.SummaryView?
}

///|
fn progress_of(response : @core.Response) -> Progress raise {
  match response {
    TranscriptProgress(entries~, findings~, checked~, done~, summary~, ..) =>
      { entries, findings, checked, done, summary, }
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
  log_preset? : @core.LogPreset,
  version? : String,
) -> @core.Response {
  @core.handle(
    session,
    TranscriptStart(
      seq=1,
      model~,
      protocol~,
      format~,
      complete~,
      log_preset~,
      version~,
      text~,
    ),
  )
}

///|
fn run_all(
  model : String,
  protocol : String,
  format : @core.TranscriptFormat,
  text : String,
  complete~ : Bool = false,
  log_preset? : @core.LogPreset,
  version? : String,
  count~ : Int32 = 100000,
) -> (Array[@core.FindingView], @core.SummaryView) raise {
  let session = @core.Session::new()
  let first = progress_of(
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
  // The page appends the findings of each response.
  let findings = first.findings.copy()
  let mut last = first
  let mut steps = 0
  while !last.done {
    last = progress_of(@core.handle(session, TranscriptStep(seq=2, count~)))
    assert_eq(last.entries, [])
    findings.append(last.findings)
    steps += 1
    if steps > 100000 {
      fail("the transcript did not finish")
    }
  }
  // The checker read every entry.
  assert_eq(last.checked, last.summary.unwrap().entries)
  (findings, last.summary.unwrap())
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
    log_preset=DirMessage([
      { value: "in", peer: "client", },
      { value: "out", peer: "server", },
    ]),
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
  version? : String,
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
  // Run all, then one entry at a time.
  for count in [100000, 1] {
    let all = run_all(
      model,
      protocol,
      format,
      text,
      complete~,
      version?,
      count~,
    )
    assert_eq(all.0, findings)
    assert_eq(all.1, summary)
  }
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
  // A version that equals the document's version gives the same result.
  differential(
    peers,
    "example.peers#EchoChat",
    Markdown,
    chat_markdown,
    true,
    version="1.0",
  )
  differential(
    peers,
    "example.peers#Editor",
    Json,
    example("transcripts/editor.json"),
    false,
    version="2.0",
  )
}

///|
test "differential: a version that conflicts with the document's is refused, as the CLI refuses it" {
  // The CLI stops with "--version 2.0 conflicts with version 1.0 in <file>"
  // (apps/smithy/transcript_cli.mbt, transcript_version) before it checks.
  let session = @core.Session::new()
  match
    start(
      session,
      example("peers.smithy"),
      "example.peers#EchoChat",
      Markdown,
      example("transcripts/chat.md"),
      version="2.0",
    ) {
    Blocked(reason~, ..) =>
      assert_eq(
        reason, "The version 2.0 conflicts with version 1.0 in the transcript.",
      )
    other => fail(@json.to_json(other).stringify())
  }
}

///|
/// The checker as the CLI runs it on a log (apps/smithy/transcript_log_cli.mbt,
/// `stream_log` and `check_lines`): the reader findings and the checker
/// findings in line order, then the findings of the end.
fn log_differential(
  model : String,
  protocol : String,
  text : String,
  preset : @core.LogPreset,
  directions : Map[String, String],
  version : String,
  complete~ : Bool = false,
) -> Unit raise {
  let assembled = @rpc.loader().add_idl("model.smithy", model).assemble().model.unwrap()
  let description = @rpc.ProtocolDescription::from_smithy(
    assembled,
    @smithy.ShapeId::parse(protocol).unwrap(),
    @rpc.ProtocolVersion::parse(version).unwrap(),
  )
  let map : Map[String, @rpc.PeerName] = Map([])
  for value, peer in directions {
    map[value] = @rpc.PeerName::parse(peer).unwrap()
  }
  let reader = @rpc.LogReader::new(@rpc.LogMapping::dir_message(map))
  let checker = @rpc.TranscriptChecker::new(
    description,
    completeness=if complete { @rpc.Complete } else { @rpc.Partial },
    correlation=!reader.single_sender(),
  )
  fn line(location : @rpc.SourceLocation?) -> Int32 {
    location.map(at => at.line).unwrap_or(0)
  }

  fn check_lines(
    read : (Array[@rpc.TranscriptEntry], Array[@rpc.TranscriptFinding]),
  ) -> Array[@rpc.TranscriptFinding] {
    let (entries, problems) = read
    let out = []
    let mut problem = 0
    for entry in entries {
      while problem < problems.length() &&
            line(problems[problem].location) < line(entry.location) {
        out.push(problems[problem])
        problem += 1
      }
      out.append(checker.feed(entry))
    }
    out.append(problems[problem:].to_owned())
    out
  }

  let expected = check_lines(reader.push_text(text))
  expected.append(check_lines(reader.end()))
  let result = checker.finish()
  expected.append(result.findings)
  let errors = expected.filter(f => f.severity == @validation.Error).length()
  let counts = reader.counts()
  let summary : @core.SummaryView = {
    valid: result.complete && errors == 0,
    complete: result.complete,
    entries: result.entries,
    errors,
    outstanding: result.outstanding,
    correlation: result.correlation,
    lines: counts.lines,
    not_json: counts.not_json,
    skipped: counts.skipped,
    expectations: None,
  }
  for count in [100000, 250, 1] {
    let (findings, got) = run_all(
      model,
      protocol,
      Jsonl,
      text,
      complete~,
      log_preset=preset,
      version~,
      count~,
    )
    assert_eq(findings, expected.map(@core.FindingView::from_finding))
    assert_eq(got, summary)
  }
}

///|
test "differential: a log gives the findings of the CLI's log check" {
  let peers = example("peers.smithy")
  log_differential(
    peers,
    "example.peers#Editor",
    example("transcripts/editor.jsonl"),
    DirMessage([
      { value: "in", peer: "client", },
      { value: "out", peer: "server", },
    ]),
    { "in": "client", "out": "server" },
    "2.0",
  )
  // A log with findings in the middle and lines that are not messages.
  let lines = []
  for i in 0..<600 {
    lines.push(
      "{\"dir\": \"in\", \"message\": {\"jsonrpc\": \"2.0\", \"id\": \{i}, \"method\": \"textDocument/hover\", \"params\": {\"uri\": \"file:///a.txt\", \"line\": 1, \"character\": 2}}}",
    )
    if i % 7 == 0 {
      lines.push("not json \{i}")
    }
    let result = if i % 5 == 0 { "3" } else { "\"docs\"" }
    if i % 11 != 0 {
      lines.push(
        "{\"dir\": \"out\", \"message\": {\"jsonrpc\": \"2.0\", \"id\": \{i}, \"result\": \{result}}}",
      )
    }
  }
  log_differential(
    peers,
    "example.peers#Editor",
    lines.join("\n"),
    DirMessage([
      { value: "in", peer: "client", },
      { value: "out", peer: "server", },
    ]),
    { "in": "client", "out": "server" },
    "2.0",
    complete=true,
  )
}

///|
test "differential: a document with no version gives its read findings" {
  // The expect list of the document does not count, as in the CLI: it
  // matches only an --expect file against these findings.
  let text = "---\nversion: 9\n---\n```jsonrpc client -> server\n{}\n```\n\n```jsonrpc-expect\n[{\"code\": \"MissingResponse\"}]\n```\n"
  let (document, read_findings) = @rpc.read_markdown_transcript(text)
  assert_true(document.version is None)
  assert_true(read_findings.any(f => f.severity == @validation.Error))
  let session = @core.Session::new()
  let { entries, findings, done, summary, .. } = progress_of(
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
  assert_true(document.expect is Some(_))
  assert_eq(summary.expectations, None)
}
