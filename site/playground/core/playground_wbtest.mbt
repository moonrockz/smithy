///|
fn start(
  session : Session,
  text : String,
  format~ : TranscriptFormat = Markdown,
  complete~ : Bool = true,
  log_preset? : LogPreset,
  model~ : String = chat_model,
  protocol~ : String = "example.peers#EchoChat",
  version? : String,
) -> Response {
  handle(
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
fn codes(findings : Array[FindingView]) -> Array[String] {
  findings.map(finding => finding.code)
}

///|
fn blocked_reason(response : Response) -> String raise {
  match response {
    Blocked(reason~, ..) => reason
    other =>
      fail("I expected Blocked, but found \{@json.to_json(other).stringify()}")
  }
}

///|
fn blocked_kind(response : Response) -> BlockKind raise {
  match response {
    Blocked(kind~, ..) => kind
    other =>
      fail("I expected Blocked, but found \{@json.to_json(other).stringify()}")
  }
}

///|
fn warnings_of(response : Response) -> Array[String] raise {
  match response {
    Transformed(warnings~, ..) => warnings
    other =>
      fail(
        "I expected Transformed, but found \{@json.to_json(other).stringify()}",
      )
  }
}

///|
fn service_of(response : Response) -> String? raise {
  match response {
    Transformed(service~, ..) => service
    other =>
      fail(
        "I expected Transformed, but found \{@json.to_json(other).stringify()}",
      )
  }
}

///|
fn files_of(response : Response) -> Array[(String, String)] raise {
  match response {
    Transformed(files~, ..) => files
    other =>
      fail(
        "I expected Transformed, but found \{@json.to_json(other).stringify()}",
      )
  }
}

///|
fn progress_of(
  response : Response,
) -> (Array[EntryView], Array[FindingView], Bool, SummaryView?) raise {
  match response {
    TranscriptProgress(entries~, findings~, done~, summary~, ..) =>
      (entries, findings, done, summary)
    other =>
      fail("I expected progress, but found \{@json.to_json(other).stringify()}")
  }
}

///|
fn checked_of(response : Response) -> Int32 raise {
  match response {
    TranscriptProgress(checked~, ..) => checked
    other =>
      fail("I expected progress, but found \{@json.to_json(other).stringify()}")
  }
}

///|
/// Start, then step `count` entries at a time to the end. The findings are the
/// findings of every response in order, as the page appends them.
fn run_steps(
  session : Session,
  text : String,
  count~ : Int32 = 100000,
  format~ : TranscriptFormat = Markdown,
  complete~ : Bool = true,
  log_preset? : LogPreset,
  version? : String,
) -> (Array[EntryView], Array[FindingView], SummaryView?) raise {
  let (entries, findings, done, summary) = progress_of(
    start(session, text, format~, complete~, log_preset?, version?),
  )
  let all = findings.copy()
  let mut last = summary
  let mut done = done
  let mut seq = 2
  while !done {
    let (more, found, finished, summary) = progress_of(
      handle(session, TranscriptStep(seq~, count~)),
    )
    assert_eq(more, [])
    all.append(found)
    done = finished
    last = summary
    seq += 1
    if seq > 100000 {
      fail("the transcript did not finish")
    }
  }
  (entries, all, last)
}

///|
test "validate: a clean model has no diagnostics and counts its shapes" {
  let session = Session::new()
  assert_eq(
    handle(session, Validate(seq=7, model=chat_model)),
    Diagnostics(seq=7, items=[], shapes=13, protocols=[
      {
        id: "example.peers#EchoChat",
        versions: ["1.0"],
        peers: ["client", "server"],
      },
    ]),
  )
}

///|
test "validate: an unknown type is one error with the library's place" {
  let session = Session::new()
  match handle(session, Validate(seq=1, model=bad_model)) {
    Diagnostics(items=[item], shapes~, ..) => {
      assert_eq(item, {
        severity: "ERROR",
        code: "Target.UnresolvedShape",
        message: "I could not resolve shape example.peers#Intger, referenced by example.peers#PostMessageOutput$count.",
        file: "model.smithy",
        start_line: 46,
        start_column: 31,
        end_line: 46,
        end_column: 44,
        shape: Some("example.peers#PostMessageOutput$count"),
      })
      assert_eq(shapes, 0)
    }
    other => fail(@json.to_json(other).stringify())
  }
}

///|
test "validate: an empty model is valid and has no shapes" {
  let session = Session::new()
  assert_eq(
    handle(session, Validate(seq=1, model="")),
    Diagnostics(seq=1, items=[], shapes=0, protocols=[]),
  )
}

///|
test "validate: an unbalanced brace is an error at the end of the text" {
  let session = Session::new()
  match handle(session, Validate(seq=3, model="namespace a\nstructure S {")) {
    Diagnostics(seq=3, items=[item], shapes=0, protocols=[]) => {
      assert_eq(item.severity, "ERROR")
      assert_eq(item.file, "model.smithy")
      assert_eq(item.start_line, 2)
      assert_true(item.message.contains("I reached the end of the file"))
    }
    other => fail(@json.to_json(other).stringify())
  }
}

///|
test "transform: JSON AST equals the library's export" {
  let session = Session::new()
  let model = load([(MODEL_FILE, chat_model)]).model.unwrap()
  let expected = @syntax.encode_json_ast(model.to_json_ast()).stringify(
    indent=4,
  )
  let files = files_of(
    handle(
      session,
      Transform(seq=1, model=chat_model, output=JsonAst, selector=None),
    ),
  )
  assert_eq(files, [("model.json", expected + "\n")])
}

///|
test "transform: IDL has one file for each namespace" {
  let session = Session::new()
  let model = load([(MODEL_FILE, chat_model)]).model.unwrap()
  let expected = model.to_idl().get("example.peers").unwrap()
  let files = files_of(
    handle(
      session,
      Transform(seq=1, model=chat_model, output=Idl, selector=None),
    ),
  )
  assert_eq(files, [("example.peers.smithy", expected)])
}

///|
test "transform: a selector lists the shape IDs, and a bad one is blocked" {
  let session = Session::new()
  let run = selector => {
    handle(
      session,
      Transform(seq=1, model=chat_model, output=Selector, selector~),
    )
  }
  let files = files_of(run(Some("[id|namespace=example.peers] :is(structure)")))
  assert_eq(files.length(), 1)
  assert_eq(files[0].0, "selector.txt")
  assert_true(files[0].1.contains("example.peers#EchoChat\n"))
  assert_false(files[0].1.contains("smithy.api#"))
  assert_eq(
    blocked_reason(run(None)),
    "I expected a selector. Write one, for example: structure",
  )
  assert_eq(
    blocked_reason(run(Some("[["))),
    "I expected an identifier at selector offset 1.",
  )
}

///|
test "transform: JSON Schema equals the library's conversion" {
  let session = Session::new()
  let model = load([(MODEL_FILE, chat_model)]).model.unwrap()
  let expected = @jsonschema.convert(model).stringify(indent=4)
  let files = files_of(
    handle(
      session,
      Transform(seq=1, model=chat_model, output=Output::JsonSchema, selector=None),
    ),
  )
  assert_eq(files, [("schema.json", expected + "\n")])
}

///|
test "transform: OpenRPC uses the first service with jsonRpc 2.0" {
  let session = Session::new()
  let files = files_of(
    handle(
      session,
      Transform(seq=1, model=calculator_model, output=OpenRpc, selector=None),
    ),
  )
  assert_eq(files.length(), 1)
  assert_eq(files[0].0, "openrpc.json")
  assert_true(files[0].1.contains("\"openrpc\": \"1.3.2\""))
  assert_true(files[0].1.contains("\"subtract\""))
  // The chat model has only JSON-RPC 1.0 services.
  assert_eq(
    blocked_reason(
      handle(
        session,
        Transform(seq=1, model=chat_model, output=OpenRpc, selector=None),
      ),
    ),
    "I found no service with a jsonRpc trait for version 2.0 in the model.",
  )
}

///|
test "transform: OpenAPI 3.0.2 and 3.1.0 load the restJson1 definition" {
  let session = Session::new()
  for pair in [(Output::OpenApi30, "3.0.2"), (Output::OpenApi31, "3.1.0")] {
    let files = files_of(
      handle(
        session,
        Transform(seq=1, model=web_model, output=pair.0, selector=None),
      ),
    )
    assert_eq(files.length(), 1)
    assert_eq(files[0].0, "Weather.openapi.json")
    assert_true(files[0].1.contains("\"openapi\": \"\{pair.1}\""))
    assert_true(files[0].1.contains("\"/city\""))
  }
}

///|
test "transform: a model with errors is blocked" {
  let session = Session::new()
  for output in [Output::JsonAst, Idl, JsonSchema, OpenApi30, OpenRpc] {
    assert_eq(
      blocked_reason(
        handle(
          session,
          Transform(seq=1, model=bad_model, output~, selector=None),
        ),
      ),
      "The model has 1 error. Fix it in the Validate tab, then run again.",
    )
  }
  assert_eq(
    blocked_reason(
      handle(
        session,
        Transform(seq=1, model="structure {", output=JsonAst, selector=None),
      ),
    ),
    "The model has 2 errors. Fix them in the Validate tab, then run again.",
  )
}

///|
test "transform: an empty model gives an empty AST and no service" {
  let session = Session::new()
  let files = files_of(
    handle(session, Transform(seq=1, model="", output=JsonAst, selector=None)),
  )
  assert_eq(files, [
    ("model.json", "{\n    \"smithy\": \"2.0\",\n    \"shapes\": {}\n}\n"),
  ])
  assert_eq(
    blocked_reason(
      handle(
        session,
        Transform(seq=1, model="", output=OpenApi30, selector=None),
      ),
    ),
    "I found no service in the model.",
  )
}

///|
test "transcript: a wrong result gives the CLI findings" {
  let session = Session::new()
  let (entries, _, _, _) = progress_of(start(session, chat_markdown))
  let step = handle(session, TranscriptStep(seq=2, count=100))
  let (_, findings, done, summary) = progress_of(step)
  assert_true(done)
  assert_eq(entries.length(), 4)
  assert_eq(checked_of(step), 4)
  assert_eq(codes(findings), [
    "TypeMismatch", "RequiredMember", "MissingResponse",
  ])
  assert_eq(findings[0], {
    code: "TypeMismatch",
    severity: "error",
    message: "I expected a integer value, but found string.",
    entry: Some(2),
    line: Some(16),
    column: Some(1),
    sender: Some("server"),
    related: [0],
    path: Some("/result"),
    shape: Some("example.peers#PostMessageOutput$count"),
    operation: Some("example.peers#PostMessage"),
  })
  assert_eq(findings[1].path, Some("/params/0"))
  assert_eq(findings[1].shape, Some("example.peers#EchoInput$text"))
  assert_eq(
    findings[2].message,
    "I expected a reply from server to entry 3 from client with id 100; the complete transcript has none.",
  )
  assert_eq(findings[2].path, None)
  assert_eq(
    summary,
    Some({
      valid: false,
      complete: true,
      entries: 4,
      errors: 3,
      outstanding: 1,
      correlation: true,
      lines: 0,
      not_json: 0,
      skipped: 0,
      expectations: None,
    }),
  )
}

///|
test "transcript: an entry goes to the other peer, and a reply names no receiver" {
  for
    (text, format) in [
      (chat_markdown, TranscriptFormat::Markdown),
      (chat_json, Json),
    ] {
    let (entries, _, _, _) = progress_of(start(Session::new(), text, format~))
    assert_eq(entries.map(e => (e.index, e.sender, e.receiver)), [
      (0, "client", Some("server")),
      (1, "server", Some("client")),
      (2, "server", None),
      (3, "client", Some("server")),
    ])
  }
}

///|
test "transcript: the JSON form gives the same findings as the Markdown form" {
  let run = (text, format) => {
    let session = Session::new()
    ignore(start(session, text, format~))
    let (_, findings, _, _) = progress_of(
      handle(session, TranscriptStep(seq=2, count=100)),
    )
    findings.map(f => { ..f, line: None, column: None, })
  }
  assert_eq(run(chat_json, Json), run(chat_markdown, Markdown))
}

///|
test "transcript: stepping one entry at a time gives the findings of run all" {
  let all = Session::new()
  ignore(start(all, chat_markdown))
  let (_, expected, _, expected_summary) = progress_of(
    handle(all, TranscriptStep(seq=2, count=100)),
  )
  let session = Session::new()
  let (_, none, done, _) = progress_of(start(session, chat_markdown))
  assert_eq(none, [])
  assert_false(done)
  let counts = []
  let found = []
  let mut summary = None
  for i in 0..<4 {
    let step = handle(session, TranscriptStep(seq=10 + i, count=1))
    let (entries, findings, done, last) = progress_of(step)
    assert_eq(entries, [])
    found.append(findings)
    summary = last
    counts.push((checked_of(step), findings.length(), done))
  }
  assert_eq(counts, [(1, 0, false), (2, 0, false), (3, 1, false), (4, 2, true)])
  assert_eq(found, expected)
  assert_eq(summary, expected_summary)
  // A step after the end gives nothing new.
  let again = handle(session, TranscriptStep(seq=20, count=1))
  assert_eq(progress_of(again).1, [])
  assert_eq(checked_of(again), 4)
}

///|
test "transcript: a step gives only what is new since the previous response" {
  let session = Session::new()
  let first = start(session, chat_markdown)
  assert_eq(progress_of(first).0.length(), 4)
  assert_eq(checked_of(first), 0)
  let steps = [1, 2, 1].map(count => {
    let step = handle(session, TranscriptStep(seq=2, count~))
    let (entries, findings, _, _) = progress_of(step)
    (entries.length(), codes(findings), checked_of(step))
  })
  assert_eq(steps, [
    (0, [], 1),
    (0, ["TypeMismatch"], 3),
    (0, ["RequiredMember", "MissingResponse"], 4),
  ])
}

///|
test "transcript: a log of 20,000 lines costs the same for each step" {
  let lines = []
  for i in 0..<10000 {
    lines.push(
      "{\"dir\": \"request\", \"message\": {\"method\": \"postMessage\", \"params\": [\"Hello \{i}\"], \"id\": \{i}}}",
    )
    lines.push(
      "{\"dir\": \"response\", \"message\": {\"result\": \"x\", \"error\": null, \"id\": \{i}}}",
    )
  }
  let text = lines.join("\n") + "\n"
  let session = Session::new()
  let first = start(session, text, format=Jsonl, version="1.0")
  assert_eq(progress_of(first).0.length(), 20000)
  // Each step of 500 entries gives at most the findings of those entries: one
  // TypeMismatch for each wrong result.
  let mut steps = 0
  let mut found = 0
  let mut done = false
  while !done {
    let (entries, findings, finished, _) = progress_of(
      handle(session, TranscriptStep(seq=2, count=500)),
    )
    assert_eq(entries, [])
    assert_true(findings.length() <= 250)
    found += findings.length()
    done = finished
    steps += 1
  }
  assert_eq(steps, 40)
  assert_eq(found, 10000)
}

///|
test "transcript: a partial check reports the open call as outstanding" {
  let session = Session::new()
  let partial = chat_markdown.replace(old="complete: true\n", new="")
  ignore(start(session, partial, complete=false))
  let (_, findings, _, summary) = progress_of(
    handle(session, TranscriptStep(seq=2, count=100)),
  )
  assert_eq(codes(findings), [
    "TypeMismatch", "RequiredMember", "OutstandingCall",
  ])
  assert_eq(findings[2].severity, "advisory")
  assert_eq(summary.unwrap().errors, 2)
}

///|
test "transcript: an expect list is matched against the findings" {
  let session = Session::new()
  let text = chat_json.replace(
    old="\"complete\": true,",
    new="\"complete\": true,\n  \"expect\": [{\"code\": \"TypeMismatch\", \"entry\": 2}, {\"code\": \"RequiredMember\"}, {\"code\": \"MissingResponse\"}, {\"code\": \"WrongResponder\"}],",
  )
  ignore(start(session, text, format=Json))
  let (_, _, _, summary) = progress_of(
    handle(session, TranscriptStep(seq=2, count=100)),
  )
  match summary.unwrap().expectations {
    Some({ matched: false, missing: [missing], unexpected: [], }) =>
      assert_eq(missing, { code: "WrongResponder", entry: None, related: None, })
    other => fail(@json.to_json(other).stringify())
  }
}

///|
test "transcript: a JSONL log uses the preset and counts its lines" {
  let session = Session::new()
  let (entries, findings, done, _) = progress_of(
    start(session, chat_log, format=Jsonl, version="1.0"),
  )
  assert_eq(entries.map(e => (e.sender, e.receiver, e.line)), [
    ("client", Some("server"), Some(2)),
    ("server", None, Some(3)),
  ])
  assert_eq(entries.length(), 2)
  assert_eq(findings, [])
  assert_false(done)
  let (_, findings, done, summary) = progress_of(
    handle(session, TranscriptStep(seq=2, count=100)),
  )
  assert_true(done)
  assert_eq(findings, [])
  assert_eq(
    summary,
    Some({
      valid: true,
      complete: true,
      entries: 2,
      errors: 0,
      outstanding: 0,
      correlation: true,
      lines: 4,
      not_json: 1,
      skipped: 1,
      expectations: None,
    }),
  )
}

///|
test "transcript: a raw log has one sender and no correlation" {
  let session = Session::new()
  let raw = "{\"method\": \"postMessage\", \"params\": [\"a\"], \"id\": 1}\n"
  ignore(
    start(
      session,
      raw,
      format=Jsonl,
      version="1.0",
      log_preset=Raw(sender="client"),
    ),
  )
  let (_, findings, done, summary) = progress_of(
    handle(session, TranscriptStep(seq=2, count=100)),
  )
  assert_true(done)
  assert_eq(findings, [])
  assert_false(summary.unwrap().correlation)
}

///|
test "transcript: a request that cannot start is blocked with a reason" {
  let session = Session::new()
  assert_eq(
    blocked_reason(start(session, chat_markdown, model=bad_model)),
    "The model has 1 error. Fix it in the Validate tab, then run again.",
  )
  assert_eq(
    blocked_reason(start(session, chat_markdown, protocol="example.peers#Nope")),
    "I found no shape example.peers#Nope in the model.",
  )
  assert_eq(
    blocked_reason(start(session, chat_markdown, protocol="not a shape")),
    "I expected a shape ID for the protocol, but found 'not a shape'.",
  )
  assert_eq(
    blocked_reason(
      start(session, chat_markdown, protocol="example.peers#ChatServer"),
    ),
    "example.peers#ChatServer: I expected the shape to carry the jsonRpcProtocol trait.",
  )
  assert_eq(
    blocked_reason(
      start(
        session,
        chat_log,
        format=Jsonl,
        version="1.0",
        log_preset=Raw(sender="nobody"),
      ),
    ),
    "I expected a peer of the protocol (client, server), but found 'nobody'.",
  )
}

///|
test "transcript: the dir-message preset maps each dir value to its sender" {
  let log =
    #|{"dir": "in", "message": {"method": "postMessage", "params": ["a"], "id": 1}}
    #|{"dir": "out", "message": {"result": 1, "error": null, "id": 1}}
  let preset : LogPreset = DirMessage([
    { value: "in", peer: "client", },
    { value: "out", peer: "server", },
  ])
  let session = Session::new()
  let (entries, findings, summary) = run_steps(
    session,
    log,
    format=Jsonl,
    version="1.0",
    log_preset=preset,
  )
  assert_eq(entries.map(e => e.sender), ["client", "server"])
  assert_eq(findings, [])
  assert_true(summary.unwrap().valid)
  // No direction: request is the first peer and response the second, so
  // the value "in" is not known.
  let (entries, findings, _) = run_steps(
    session,
    log,
    format=Jsonl,
    version="1.0",
    log_preset=DirMessage([]),
  )
  assert_eq(entries, [])
  assert_eq(codes(findings), ["InvalidTranscript", "InvalidTranscript"])
}

///|
test "transcript: a log preset that the CLI refuses is blocked" {
  let session = Session::new()
  let blocked = (preset : LogPreset) => {
    blocked_reason(
      start(session, chat_log, format=Jsonl, version="1.0", log_preset=preset),
    )
  }
  assert_eq(
    blocked(DirMessage([{ value: "in", peer: "nobody", }])),
    "I expected a peer of the protocol (client, server), but found 'nobody'.",
  )
  assert_eq(
    blocked(
      DirMessage([
        { value: "in", peer: "client", },
        { value: "in", peer: "server", },
      ]),
    ),
    "The log preset gives the value 'in' twice.",
  )
  assert_eq(
    blocked(DirMessage([{ value: "", peer: "client", }])),
    "I expected a dir value for the peer client, but found none.",
  )
  // The CLI applies --log-preset to JSONL input only.
  assert_eq(
    blocked_reason(
      start(session, chat_markdown, log_preset=Raw(sender="client")),
    ),
    "A log preset applies only to a JSONL log.",
  )
}

///|
test "transcript: step with no transcript, and reset, are blocked or empty" {
  let session = Session::new()
  let none = "I have no transcript to check. Start one first."
  assert_eq(
    blocked_reason(handle(session, TranscriptStep(seq=1, count=1))),
    none,
  )
  ignore(start(session, chat_markdown))
  assert_eq(
    handle(session, TranscriptReset(seq=5)),
    TranscriptProgress(
      seq=5,
      entries=[],
      findings=[],
      checked=0,
      done=false,
      summary=None,
    ),
  )
  assert_eq(
    blocked_reason(handle(session, TranscriptStep(seq=6, count=1))),
    none,
  )
}

///|
test "transcript: a problem of the document comes before the entries" {
  let session = Session::new()
  // The value of complete is a problem of the document, not of an entry. The
  // version is good, so the entries are still checked after it.
  let text = "---\nversion: 1.0\ncomplete: maybe\n---\n```jsonrpc client -> server\n{}\n```\n"
  let (entries, first, done, _) = progress_of(start(session, text))
  assert_eq(entries.length(), 1)
  assert_false(done)
  assert_eq(codes(first), ["InvalidTranscript"])
  assert_eq(first[0].entry, None)
  assert_eq(first[0].line, Some(3))
  let (_, more, _, _) = progress_of(
    handle(session, TranscriptStep(seq=2, count=1)),
  )
  let findings = [..first, ..more]
  assert_eq(codes(findings), [
    "InvalidTranscript", "UnsolicitedResponse", "InvalidId", "InvalidEnvelope", "InvalidEnvelope",
  ])
  assert_eq(findings.map(finding => finding.entry), [
    None,
    Some(0),
    Some(0),
    Some(0),
    Some(0),
  ])
}

///|
test "transcript: a document with a bad version stops at the reader finding" {
  let session = Session::new()
  let text = "---\nversion: 9\n---\n```jsonrpc client -> server\n{}\n```\n"
  let first = start(session, text)
  let (entries, findings, done, summary) = progress_of(first)
  assert_eq(entries.length(), 1)
  assert_eq(checked_of(first), 0)
  assert_eq(codes(findings), ["InvalidTranscript"])
  assert_eq(findings[0].line, Some(2))
  assert_true(done)
  let summary = summary.unwrap()
  assert_false(summary.valid)
  assert_false(summary.complete)
  assert_eq(summary.errors, 1)
  assert_eq(summary.entries, 0)
}

///|
test "transcript: a document with no version is blocked" {
  let session = Session::new()
  let text = "```jsonrpc client -> server\n{}\n```\n"
  assert_eq(
    blocked_reason(start(session, text)),
    "The transcript gives no JSON-RPC version. Add version: 1.0 or version: 2.0 to it.",
  )
  assert_eq(
    blocked_reason(start(session, "{\"entries\": []}", format=Json)),
    "The transcript gives no JSON-RPC version. Add version: 1.0 or version: 2.0 to it.",
  )
}

///|
test "transcript: a version that differs from the document's is blocked, as in the CLI" {
  let session = Session::new()
  assert_eq(
    blocked_reason(start(session, chat_markdown, version="2.0")),
    "The version 2.0 conflicts with version 1.0 in the transcript.",
  )
  assert_eq(
    blocked_reason(start(session, chat_json, format=Json, version="2.0")),
    "The version 2.0 conflicts with version 1.0 in the transcript.",
  )
  // The same version as the document's runs as with no version.
  let (_, same, _) = run_steps(session, chat_markdown, version="1.0")
  let (_, none, _) = run_steps(session, chat_markdown)
  assert_eq(same, none)
  assert_eq(codes(same), ["TypeMismatch", "RequiredMember", "MissingResponse"])
}

///|
test "transcript: a document that I cannot read gives no expectations, as the CLI without --expect" {
  // The CLI matches only an --expect file against the read findings of such a
  // document; the expect list in the document is not read. The playground has
  // no --expect file.
  let text =
    #|---
    #|version: 9
    #|---
    #|```jsonrpc client -> server
    #|{"method": "echo", "params": ["x"], "id": 1}
    #|```
    #|
    #|```jsonrpc-expect
    #|[{"code": "MissingResponse"}]
    #|```
  let session = Session::new()
  let (_, findings, done, summary) = progress_of(start(session, text))
  assert_true(done)
  assert_eq(codes(findings), ["InvalidTranscript"])
  assert_eq(summary.unwrap().expectations, None)
}

///|
test "validate: the answer lists the JSON-RPC protocols with their versions and peers" {
  let session = Session::new()
  let protocols = match handle(session, Validate(seq=1, model=chat_model)) {
    Diagnostics(protocols~, ..) => protocols
    other => fail(@json.to_json(other).stringify())
  }
  assert_eq(protocols, [
    {
      id: "example.peers#EchoChat",
      versions: ["1.0"],
      peers: ["client", "server"],
    },
  ])
  // A model with errors does not assemble, so it lists no protocol.
  match handle(session, Validate(seq=2, model=bad_model)) {
    Diagnostics(protocols~, items~, ..) => {
      assert_eq(items.length(), 1)
      assert_eq(protocols, [])
    }
    other => fail(@json.to_json(other).stringify())
  }
  match handle(session, Validate(seq=3, model=calculator_model)) {
    Diagnostics(protocols~, ..) => assert_eq(protocols, [])
    other => fail(@json.to_json(other).stringify())
  }
}

///|
test "validate: the protocols are in the order of their shape IDs, as text" {
  let model =
    #|$version: "2"
    #|namespace a
    #|use smithy.rpc#jsonRpcProtocol
    #|@jsonRpcProtocol(versions: ["2.0", "1.0"], peers: [{ name: "x" }, { name: "y" }])
    #|structure Zz {}
    #|@jsonRpcProtocol(versions: ["2.0"], peers: [{ name: "x" }, { name: "y" }])
    #|structure Editor {}
  match handle(Session::new(), Validate(seq=1, model~)) {
    Diagnostics(protocols~, ..) =>
      assert_eq(protocols.map(p => (p.id, p.versions)), [
        ("a#Editor", ["2.0"]),
        ("a#Zz", ["2.0", "1.0"]),
      ])
    other => fail(@json.to_json(other).stringify())
  }
}

///|
test "transcript: a JSONL log needs a version, as the CLI needs --version" {
  let session = Session::new()
  let reason = "A JSONL log gives no JSON-RPC version. I need version 1.0 or 2.0."
  assert_eq(
    blocked_reason(
      handle(
        session,
        TranscriptStart(
          seq=1,
          model=chat_model,
          protocol="example.peers#EchoChat",
          format=Jsonl,
          complete=true,
          log_preset=None,
          version=None,
          text=chat_log,
        ),
      ),
    ),
    reason,
  )
  assert_eq(
    blocked_reason(start(session, chat_log, format=Jsonl, version="3.0")),
    "I expected 1.0 or 2.0 for the version.",
  )
  // A version that the protocol does not declare is a contract error.
  assert_eq(
    blocked_reason(start(session, chat_log, format=Jsonl, version="2.0")),
    "example.peers#EchoChat: I expected the selected version 2.0 to be declared by the protocol.",
  )
}

///|
test "transcript: an empty document finishes at once" {
  let session = Session::new()
  let (entries, findings, done, summary) = progress_of(
    start(session, "---\nversion: 1.0\n---\n"),
  )
  assert_eq(entries, [])
  assert_eq(findings, [])
  assert_true(done)
  assert_eq(summary.unwrap().entries, 0)
}

///|
test "wire: requests and responses survive a JSON round trip" {
  let requests : Array[Request] = [
    Validate(seq=1, model="m"),
    Transform(seq=2, model="m", output=OpenApi31, selector=Some("structure")),
    Transform(seq=3, model="m", output=Idl, selector=None),
    TranscriptStart(
      seq=4,
      model="m",
      protocol="a#B",
      format=Jsonl,
      complete=true,
      log_preset=Some(
        DirMessage([
          { value: "in", peer: "client", },
          { value: "out", peer: "server", },
        ]),
      ),
      version=Some("2.0"),
      text="t",
    ),
    TranscriptStart(
      seq=4,
      model="m",
      protocol="a#B",
      format=Jsonl,
      complete=false,
      log_preset=Some(Raw(sender="client")),
      version=None,
      text="t",
    ),
    TranscriptStep(seq=5, count=1),
    TranscriptReset(seq=6),
  ]
  for request in requests {
    assert_eq(@json.from_json(@json.to_json(request)), request)
  }
  let session = Session::new()
  let responses = [
    handle(session, Validate(seq=1, model=bad_model)),
    handle(
      session,
      Transform(seq=2, model=chat_model, output=JsonAst, selector=None),
    ),
    handle(session, Transform(seq=3, model="", output=OpenRpc, selector=None)),
    start(session, chat_markdown),
    handle(session, TranscriptStep(seq=5, count=100)),
  ]
  for response in responses {
    let text = @json.to_json(response).stringify()
    assert_eq(@json.from_json(@json.parse(text)), response)
  }
}

///|
fn sample_state() -> ShareState {
  {
    model: chat_model,
    transcript: chat_markdown,
    tab: TranscriptTab,
    selector: Some("structure"),
    log_preset: Some(DirMessage([{ value: "in", peer: "client", }])),
    version: Some("2.0"),
    output: OpenRpc,
    protocol: "example.peers#EchoChat",
    format: Markdown,
    complete: true,
  }
}

///|
test "share: a state survives the round trip" {
  let state = sample_state()
  let text = encode_share(state)
  assert_true(text.has_prefix("v1."))
  assert_eq(decode_share(text), Ok(state))
  assert_eq(share_length_problem(text), None)
  // The compressed text is shorter than the base64url text of the JSON.
  assert_true(text.length() < @json.to_json(state).stringify().length())
}

///|
test "share: non-ASCII text survives the round trip" {
  let state = {
    ..sample_state(),
    model: "// é 日本語 🙂\nnamespace a",
    tab: ValidateTab,
  }
  assert_eq(decode_share(encode_share(state)), Ok(state))
}

///|
test "share: base64url round trips every length" {
  for n in 0..<12 {
    let bytes = Bytes::from_array(
      Array::makei(n, i => (i * 37 + 250).land(255).to_byte()),
    )
    assert_eq(base64url_decode(base64url_encode(bytes)), Ok(bytes))
  }
  assert_eq(base64url_encode(b"\xfb\xff\xbf"), "-_-_")
}

///|
test "share: a corrupt fragment gives a message" {
  let good = encode_share(sample_state())
  let message = text => {
    match decode_share(text) {
      Err(message) => message
      Ok(_) => fail("I expected an error for '\{text}'")
    }
  }
  assert_eq(
    message("v2.abc"),
    "I cannot read this link: it has the format v2, and I know only v1. It may come from a newer version of the site.",
  )
  assert_eq(
    message("v10.abc"),
    "I cannot read this link: it has the format v10, and I know only v1. It may come from a newer version of the site.",
  )
  assert_eq(
    message("v.abc"),
    "I expected the link to start with v1. so I cannot read it.",
  )
  assert_eq(
    message(""),
    "I expected the link to start with v1. so I cannot read it.",
  )
  assert_eq(
    message("v1.ab+c"),
    "I found the character '+' in the link, which is not in base64url.",
  )
  assert_eq(
    message("v1.abcde"),
    "The link has a length that base64url cannot have.",
  )
  assert_true(message("v1.AAAA").has_prefix("I could not unpack the link"))
  assert_true(
    message(good[:good.length() - 8].to_owned()).has_prefix(
      "I could not unpack the link",
    ),
  )
  // Valid deflate of text that is not JSON, and of JSON that is not a state.
  let pack = text => {
    "v1." + base64url_encode(@flate.deflate_all(@utf8.encode(text)))
  }
  assert_eq(message(pack("not json")), "The link does not hold JSON.")
  assert_eq(
    message(pack("{\"model\": 1}")),
    "The link holds JSON that is not a playground state. It may come from another version of the site.",
  )
  assert_eq(
    message("v1." + base64url_encode(@flate.deflate_all(b"\xff\xfe"))),
    "The link does not hold UTF-8 text.",
  )
}

///|
test "share: a fragment over 8000 characters is rejected" {
  let long = "v1." + "A".repeat(MAX_SHARE_LENGTH)
  assert_true(long.length() > MAX_SHARE_LENGTH)
  assert_eq(
    decode_share(long),
    Err("The link has 8003 characters. A link can have 8000 at most."),
  )
  assert_eq(
    share_length_problem(long),
    Some(
      "The link has 8003 characters. A link can have 8000 at most. Use Download instead.",
    ),
  )
  // A model of text that does not compress makes a link that is too long.
  let noise = StringBuilder()
  let mut x = 12345
  for _ in 0..<12000 {
    x = (x * 1103515245 + 12345).land(0x7fffffff)
    noise.write_char(((x >> 16) % 26 + 97).unsafe_to_char())
  }
  let text = encode_share({ ..sample_state(), model: noise.to_string(), })
  assert_true(share_length_problem(text) is Some(_))
}

///|
test "share: a state that inflates above the limit is rejected" {
  // 3 MB of one letter packs to a few KB, so the link is short.
  let big = { ..sample_state(), model: "a".repeat(3000000), }
  let link = encode_share(big)
  assert_true(link.length() < 8000)
  assert_eq(share_length_problem(link), None)
  match decode_share(link) {
    Err(message) =>
      assert_true(
        message.has_prefix(
          "The link unpacks to more than \{MAX_STATE_BYTES} bytes.",
        ),
      )
    Ok(_) => fail("I expected the state above the limit to be rejected")
  }
  assert_true(share_state_problem(big) is Some(_))
}

///|
test "share: the decoder stops at the limit and does not unpack a bomb" {
  // 4 MB of one letter packs to a few KB and unpacks past the limit.
  let bomb = { ..sample_state(), model: "a".repeat(4000000), }
  let json = @utf8.encode(@json.to_json(bomb).stringify())
  let packed = @flate.deflate_all(json)
  assert_true(packed.length() < 8000)
  match bounded_inflate(packed) {
    Err(message) =>
      assert_true(message.has_prefix("The link unpacks to more than"))
    Ok(_) => fail("I expected the bomb to be rejected")
  }
  // A stream within the limit unpacks to the same bytes as `inflate_all`.
  let small = @utf8.encode("hello ".repeat(30000))
  assert_eq(bounded_inflate(@flate.deflate_all(small)), Ok(small))
  // Stored data, empty data and cut data.
  assert_eq(bounded_inflate(@flate.deflate_all(b"")), Ok(b""))
  let cut = @flate.deflate_all(small)
  assert_true(bounded_inflate(cut[:cut.length() / 2].to_owned()) is Err(_))
}

///|
test "share: a stream of exactly the limit unpacks, one byte more does not" {
  let exact = Bytes::from_array(Array::make(MAX_STATE_BYTES, b'a'))
  match bounded_inflate(@flate.deflate_all(exact)) {
    Ok(bytes) => assert_eq(bytes.length(), MAX_STATE_BYTES)
    Err(message) => fail(message)
  }
  let over = Bytes::from_array(Array::make(MAX_STATE_BYTES + 1, b'a'))
  assert_true(bounded_inflate(@flate.deflate_all(over)) is Err(_))
}

///|
test "share: a model of a few hundred KB still fits when its link is short" {
  let state = { ..sample_state(), model: "// line\n".repeat(50000), }
  assert_true(state.model.length() >= 400000)
  assert_eq(share_state_problem(state), None)
  let link = encode_share(state)
  assert_eq(share_length_problem(link), None)
  assert_eq(decode_share(link), Ok(state))
}

///|
test "transcript: a document that says complete is complete without the flag" {
  let session = Session::new()
  ignore(start(session, chat_markdown, complete=false))
  let (_, findings, _, _) = progress_of(
    handle(session, TranscriptStep(seq=2, count=100)),
  )
  assert_eq(codes(findings), [
    "TypeMismatch", "RequiredMember", "MissingResponse",
  ])
}

///|
test "share: a state without selector and log preset still decodes" {
  let old = "{\"model\":\"m\",\"transcript\":\"t\",\"tab\":\"ValidateTab\",\"output\":\"JsonAst\",\"protocol\":\"a#B\",\"format\":\"Markdown\",\"complete\":false}"
  let json = @json.parse(old)
  let state : ShareState = @json.from_json(json)
  assert_eq(state.selector, None)
  assert_eq(state.log_preset, None)
  assert_eq(state.version, None)
  let link = "v1." + base64url_encode(@flate.deflate_all(@utf8.encode(old)))
  assert_eq(decode_share(link), Ok(state))
}

///|
test "wire: handle_json answers a request with the response in JSON" {
  let session = Session::new()
  let request = @json.to_json(Validate(seq=4, model="")).stringify()
  let response : Response = @json.from_json(
    @json.parse(handle_json(session, request)),
  )
  assert_eq(response, Diagnostics(seq=4, items=[], shapes=0, protocols=[]))
}

///|
test "wire: handle_json blocks a request that it cannot read" {
  let session = Session::new()
  for text in ["", "not json", "{\"seq\": 1}", "[\"Validate\"]"] {
    let response : Response = @json.from_json(
      @json.parse(handle_json(session, text)),
    )
    match response {
      Blocked(seq=-1, reason~, ..) =>
        assert_true(reason.has_prefix("I could not read the request"))
      other => fail(@json.to_json(other).stringify())
    }
  }
}

///|
test "transform: OpenAPI picks the first service that has a protocol trait" {
  let session = Session::new()
  for output in [Output::OpenApi30, OpenApi31] {
    let response = handle(
      session,
      Transform(seq=1, model=mixed_model, output~, selector=None),
    )
    let files = files_of(response)
    // AlphaRpc sorts first, but it has no protocol trait for OpenAPI.
    assert_eq(service_of(response), Some("example.mixed#Weather"))
    assert_eq(files.map(file => file.0), ["Weather.openapi.json"])
  }
}

///|
test "transform: OpenRPC keeps the rule of the CLI: the first service with jsonRpc 2.0" {
  let response = handle(
    Session::new(),
    Transform(seq=1, model=versions_model, output=OpenRpc, selector=None),
  )
  assert_eq(service_of(response), Some("example.versions#NewRpc"))
  let files = files_of(response)
  // OldRpc sorts first but speaks 1.0 only.
  assert_true(files[0].1.contains("\"ping\""))
  assert_true(files[0].1.contains("\"title\": \"NewRpc\""))
}

///|
test "transform: OpenAPI of a model with no protocol trait is blocked with its reason" {
  let session = Session::new()
  // peers.smithy has services, but none has a protocol trait.
  let response = handle(
    session,
    Transform(seq=1, model=chat_model, output=OpenApi30, selector=None),
  )
  assert_eq(
    blocked_reason(response),
    "I found no service with a protocol trait in the model.",
  )
  assert_eq(blocked_kind(response), Other)
  let empty = handle(
    session,
    Transform(seq=1, model="", output=OpenApi31, selector=None),
  )
  assert_eq(blocked_reason(empty), "I found no service in the model.")
  assert_eq(blocked_kind(empty), Other)
}

///|
test "transform: a model with errors is blocked with the kind ModelErrors" {
  let session = Session::new()
  for output in [Output::JsonAst, OpenApi30, OpenRpc] {
    assert_eq(
      blocked_kind(
        handle(
          session,
          Transform(seq=1, model=bad_model, output~, selector=None),
        ),
      ),
      ModelErrors,
    )
  }
  // A bad selector is not a model error.
  assert_eq(
    blocked_kind(
      handle(
        session,
        Transform(seq=1, model=chat_model, output=Selector, selector=Some("")),
      ),
    ),
    Other,
  )
}

///|
test "transform: converter warnings come as the CLI prints them" {
  let session = Session::new()
  let response = handle(
    session,
    Transform(seq=1, model=warning_model, output=OpenApi30, selector=None),
  )
  assert_eq(warnings_of(response), [
    "WARNING: example.web#GetCity: OpenAPI omits unsupported HTTP method `CONNECT`",
  ])
  // A conversion with no warning has an empty list, and so has an output
  // that does not convert.
  assert_eq(
    warnings_of(
      handle(
        session,
        Transform(seq=1, model=web_model, output=OpenApi31, selector=None),
      ),
    ),
    [],
  )
  assert_eq(
    warnings_of(
      handle(
        session,
        Transform(seq=1, model=chat_model, output=JsonAst, selector=None),
      ),
    ),
    [],
  )
}

///|
test "transform: outputs that use no service report none" {
  let session = Session::new()
  for output in [Output::JsonAst, Idl, JsonSchema] {
    assert_eq(
      service_of(
        handle(
          session,
          Transform(seq=1, model=chat_model, output~, selector=None),
        ),
      ),
      None,
    )
  }
}

///|
let file_a : String = "$version: \"2\"\nnamespace a\nuse b#B\nstructure A { b: B }\n"

///|
let file_b_bad : String = "$version: \"2\"\nnamespace b\nstructure B {\n    x: Missing\n}\n"

///|
let file_b_ok : String = "$version: \"2\"\nnamespace b\nstructure B {\n    x: String\n}\n"

///|
test "ValidateFiles resolves a use across two files and places each finding in its file" {
  let session = Session::new()
  let response = handle(
    session,
    ValidateFiles(
      seq=1,
      files=[("a.smithy", file_a), ("b.smithy", file_b_bad)],
    ),
  )
  match response {
    Diagnostics(items=[item], ..) => {
      assert_eq(item.severity, "ERROR")
      assert_eq(item.code, "Target.UnresolvedShape")
      assert_eq(item.file, "b.smithy")
      assert_eq(item.start_line, 4)
      assert_eq(item.shape, Some("b#B$x"))
    }
    other => fail(@json.to_json(other).stringify())
  }
}

///|
test "ValidateFiles with one file gives the same answer as Validate" {
  let session = Session::new()
  for text in [chat_model, bad_model, file_b_ok, "structure {", ""] {
    assert_eq(
      handle(session, ValidateFiles(seq=1, files=[("model.smithy", text)])),
      handle(session, Validate(seq=1, model=text)),
    )
  }
}

///|
test "TransformFiles builds JSON Schema from two files" {
  let session = Session::new()
  let response = handle(
    session,
    TransformFiles(
      seq=1,
      files=[("a.smithy", file_a), ("b.smithy", file_b_ok)],
      output=Output::JsonSchema,
      selector=None,
    ),
  )
  match response {
    Transformed(files~, ..) => {
      assert_eq(files[0].0, "schema.json")
      assert_true(files[0].1.contains("\"B\""))
      assert_true(files[0].1.contains("\"A\""))
    }
    other => fail(@json.to_json(other).stringify())
  }
}

///|
test "TransformFiles is blocked when a file has an error" {
  let session = Session::new()
  let response = handle(
    session,
    TransformFiles(
      seq=1,
      files=[("a.smithy", file_a), ("b.smithy", file_b_bad)],
      output=Output::JsonSchema,
      selector=None,
    ),
  )
  assert_eq(blocked_kind(response), ModelErrors)
  assert_eq(
    blocked_reason(response),
    "The model has 1 error. Fix it in the Validate tab, then run again.",
  )
}
