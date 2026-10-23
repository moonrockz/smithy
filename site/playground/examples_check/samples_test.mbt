///|
/// The text of a repository file; the tests run in `site/`.
fn repository_file(path : String) -> String raise {
  @fs.read_file_to_string("../" + path)
}

///|
fn validate_sample(path : String) -> (Array[@core.Diagnostic], Int32) raise {
  let session = @core.Session::new()
  match @core.handle(session, Validate(seq=1, model=repository_file(path))) {
    Diagnostics(items~, shapes~, ..) => (items, shapes)
    other => fail(@json.to_json(other).stringify())
  }
}

///|
test "samples: the picker opens the model with a mistake" {
  let source = @samples.manifest[@samples.default_index]
  assert_eq(source.title, "JSON-RPC chat protocol (with a mistake)")
  assert_eq(source.path, "site/playground/samples/chat-error.smithy")
}

///|
test "samples: every model of the picker exists, and only the mistake has errors" {
  for source in @samples.manifest {
    let (items, shapes) = validate_sample(source.path)
    let errors = items.filter(d => {
      d.severity == "ERROR" || d.severity == "DANGER"
    })
    if source.path == "site/playground/samples/chat-error.smithy" {
      assert_eq(errors.length(), 1)
    } else {
      assert_eq(errors, [])
      assert_true(shapes > 0)
    }
  }
}

///|
test "samples: the mistake is peers.smithy with Intger for Integer" {
  let peers = repository_file("examples/json-rpc/peers.smithy")
  let mistake = repository_file("site/playground/samples/chat-error.smithy")
  assert_eq(
    mistake,
    peers.replace(
      old="structure PostMessageOutput { count: Integer }",
      new="structure PostMessageOutput { count: Intger }",
    ),
  )
  assert_true(mistake != peers)
  let (items, _) = validate_sample("site/playground/samples/chat-error.smithy")
  assert_eq(items.length(), 1)
  assert_eq(items[0].code, "Target.UnresolvedShape")
  assert_eq(
    items[0].message,
    "I could not resolve shape example.peers#Intger, referenced by example.peers#PostMessageOutput$count.",
  )
}

///|
/// The codes of the findings of a transcript of the picker, checked against
/// `examples/json-rpc/peers.smithy` with the settings of the picker.
fn transcript_codes(source : @samples.TranscriptSource) -> Array[String] raise {
  let (findings, summary) = run_all(
    repository_file("examples/json-rpc/peers.smithy"),
    source.protocol,
    source.format,
    repository_file(source.path),
    log_preset?=source.preset,
    version?=source.version,
  )
  assert_eq(
    summary.errors,
    findings.filter(f => f.severity == "error").length(),
  )
  findings.map(f => f.code)
}

///|
test "samples: the transcript picker opens the chat with the three findings of the mockup" {
  let source = @samples.transcript_manifest[@samples.default_transcript]
  assert_eq(source.path, "site/playground/samples/chat-findings.md")
  assert_eq(transcript_codes(source), [
    "TypeMismatch", "RequiredMember", "MissingResponse",
  ])
}

///|
test "samples: every other transcript of the picker is valid for peers.smithy" {
  let paths = []
  for i, source in @samples.transcript_manifest {
    if i != @samples.default_transcript {
      assert_eq(transcript_codes(source), [])
      paths.push(source.path)
    }
  }
  assert_eq(paths, [
    "examples/json-rpc/transcripts/chat.md", "examples/json-rpc/transcripts/echo.md",
    "examples/json-rpc/transcripts/editor.md", "examples/json-rpc/transcripts/editor.jsonl",
  ])
}

///|
test "samples: a document of the picker has no version or preset, and a log has both" {
  for source in @samples.transcript_manifest {
    match source.format {
      Jsonl =>
        assert_true(source.version is Some(_) && source.preset is Some(_))
      _ => assert_true(source.version is None && source.preset is None)
    }
  }
}
