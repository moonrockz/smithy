///|
fn start(
  session : Session,
  text : String,
  format~ : TranscriptFormat = Markdown,
  complete~ : Bool = true,
  log_preset? : String,
  model~ : String = chat_model,
  protocol~ : String = "example.peers#EchoChat",
  version? : String,
) -> Response {
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
test "validate: a clean model has no diagnostics and counts its shapes" {
  let session = Session::new()
  assert_eq(
    handle(session, Validate(seq=7, model=chat_model)),
    Diagnostics(seq=7, items=[], shapes=13),
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
    Diagnostics(seq=1, items=[], shapes=0),
  )
}

///|
test "validate: an unbalanced brace is an error at the end of the text" {
  let session = Session::new()
  match handle(session, Validate(seq=3, model="namespace a\nstructure S {")) {
    Diagnostics(seq=3, items=[item], shapes=0) => {
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
  let model = load(chat_model).model.unwrap()
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
  let model = load(chat_model).model.unwrap()
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
  let model = load(chat_model).model.unwrap()
  let expected = @jsonschema.convert(model).stringify(indent=4)
  let files = files_of(
    handle(
      session,
      Transform(seq=1, model=chat_model, output=JsonSchema, selector=None),
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
  for pair in [(OpenApi30, "3.0.2"), (OpenApi31, "3.1.0")] {
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
  for output in [JsonAst, Idl, JsonSchema, OpenApi30, OpenRpc] {
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
  ignore(start(session, chat_markdown))
  let (entries, findings, done, summary) = progress_of(
    handle(session, TranscriptStep(seq=2, count=100)),
  )
  assert_true(done)
  assert_eq(entries.length(), 4)
  assert_true(entries.all(entry => entry.checked))
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
  let mut last = (
    ([] : Array[EntryView]),
    ([] : Array[FindingView]),
    false,
    (None : SummaryView?),
  )
  for i in 0..<4 {
    last = progress_of(handle(session, TranscriptStep(seq=10 + i, count=1)))
    counts.push(
      (last.0.filter(e => e.checked).length(), last.1.length(), last.2),
    )
  }
  assert_eq(counts, [(1, 0, false), (2, 0, false), (3, 1, false), (4, 3, true)])
  assert_eq(last.1, expected)
  assert_eq(last.3, expected_summary)
  // A step after the end changes nothing.
  let again = progress_of(handle(session, TranscriptStep(seq=20, count=1)))
  assert_eq(again.1, expected)
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
    start(session, raw, format=Jsonl, version="1.0", log_preset="raw:client"),
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
      start(session, chat_log, format=Jsonl, version="1.0", log_preset="raw"),
    ),
    "I expected a sender for the raw preset, as raw:<peer>.",
  )
  assert_eq(
    blocked_reason(
      start(
        session,
        chat_log,
        format=Jsonl,
        version="1.0",
        log_preset="raw:nobody",
      ),
    ),
    "I expected a peer of the protocol (client, server), but found 'nobody'.",
  )
  assert_eq(
    blocked_reason(
      start(session, chat_log, format=Jsonl, version="1.0", log_preset="csv"),
    ),
    "I expected the log preset dir-message or raw:<peer>, but found 'csv'.",
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
    TranscriptProgress(seq=5, entries=[], findings=[], done=false, summary=None),
  )
  assert_eq(
    blocked_reason(handle(session, TranscriptStep(seq=6, count=1))),
    none,
  )
}

///|
test "transcript: a problem of the document comes before the entries" {
  let session = Session::new()
  let text = "---\nversion: 1.0\nbad: 1\n---\n```jsonrpc client -> server\n{}\n```\n"
  let (entries, findings, done, _) = progress_of(start(session, text))
  assert_eq(entries.length(), 1)
  assert_false(done)
  assert_true(findings.length() <= 1)
}

///|
test "transcript: a document with a bad version stops at the reader finding" {
  let session = Session::new()
  let text = "---\nversion: 9\n---\n```jsonrpc client -> server\n{}\n```\n"
  let (entries, findings, done, summary) = progress_of(start(session, text))
  assert_eq(entries.length(), 1)
  assert_false(entries[0].checked)
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
      log_preset=Some("raw:client"),
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
    log_preset: None,
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
    "The link holds JSON that is not a playground state.",
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
    Err(
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
  let link = "v1." + base64url_encode(@flate.deflate_all(@utf8.encode(old)))
  assert_eq(decode_share(link), Ok(state))
}
