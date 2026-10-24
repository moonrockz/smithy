///|
test "hint: each output names the CLI command that gives it" {
  assert_eq(
    cli_hint(JsonAst, "", 1, None),
    "smithy convert --to json model.smithy",
  )
  assert_eq(cli_hint(Idl, "", 1, None), "smithy convert --to idl model.smithy")
  assert_eq(
    cli_hint(Idl, "", 2, None),
    "smithy convert --to idl --output-dir DIR model.smithy",
  )
  assert_eq(
    cli_hint(Selector, "structure > member", 1, None),
    "smithy select --selector 'structure > member' model.smithy",
  )
  assert_eq(
    cli_hint(JsonSchema, "", 1, None),
    "smithy build --config smithy-build.json, with the plugin \"jsonSchema\"",
  )
}

///|
test "hint: OpenAPI and OpenRPC name the service that the run picked" {
  let service = Some("example.web#Weather")
  assert_eq(
    cli_hint(OpenApi30, "", 1, service),
    "smithy build --config smithy-build.json, with the plugin \"openapi\": {\"service\": \"example.web#Weather\", \"version\": \"3.0.2\"}",
  )
  assert_eq(
    cli_hint(OpenApi31, "", 1, service),
    "smithy build --config smithy-build.json, with the plugin \"openapi\": {\"service\": \"example.web#Weather\", \"version\": \"3.1.0\"}",
  )
  assert_eq(
    cli_hint(OpenRpc, "", 1, Some("example#Calculator")),
    "smithy build --config smithy-build.json, with the plugin \"openrpc\": {\"service\": \"example#Calculator\"}",
  )
}

///|
test "hint: a selector with a single quote stays one argument" {
  assert_eq(
    cli_hint(Selector, "[id='a#B']", 1, None),
    "smithy select --selector '[id='\\''a#B'\\'']' model.smithy",
  )
}

///|
test "picker: every output has its own key and label" {
  let keys = outputs.map(output => output.key())
  assert_eq(keys.length(), 7)
  for output in outputs {
    assert_eq(output_of_key(output.key()), Some(output))
  }
  assert_eq(output_of_key("nope"), None)
  assert_eq(outputs.map(output => output_label(output)), [
    "JSON AST", "Formatted IDL", "Selector query", "JSON Schema", "OpenAPI 3.0.2",
    "OpenAPI 3.1.0", "OpenRPC 1.3.2",
  ])
}

///|
test "elapsed: the status bar shows the seconds from 1 s, and the limit from 5 s" {
  assert_eq(elapsed_text(0), "")
  assert_eq(elapsed_text(1), " · 1 s")
  assert_eq(elapsed_text(4), " · 4 s")
  assert_eq(elapsed_text(5), " · 5 s of 10 s")
  assert_eq(elapsed_text(9), " · 9 s of 10 s")
}

///|
test "busy: each kind of request names what the Worker does" {
  assert_eq(busy_label(Validating), "checking")
  assert_eq(busy_label(Transforming), "running the transform")
  assert_eq(busy_label(Transcribing), "checking the transcript")
}

///|
test "stale: the results status bar warns when the output is older than the model" {
  let (m, _) = update(answered(), TabChosen(TransformTab))
  let (m, _) = update(m, RunClicked)
  let (m, _) = update(
    m,
    Answered(
      seq=m.seq,
      answer=Transformed(files=["model.json"], warnings=[], service=None),
    ),
  )
  assert_eq(results_status_text(m), "JSON AST · model.json")
  assert_eq(results_stale_text(m), None)
  let (m, _) = update(m, Edited)
  assert_eq(results_stale_text(m), Some("older than the model: select Run"))
}

///|
test "stale: the results status bar warns when the transcript check is older than the editors" {
  let (m, _) = update(ready(), TabChosen(TranscriptTab))
  let (m, _) = update(m, RunAllClicked)
  let (m, _) = run(m, [
    Answered(
      seq=m.seq,
      answer=progressed(checked=2, done=true, summary=Some(summary(2, 0))),
    ),
  ])
  assert_eq(results_status_text(m), "2 entries checked · 0 findings")
  assert_eq(results_stale_text(m), None)
  let (m, _) = update(m, TranscriptEdited)
  assert_eq(
    results_stale_text(m),
    Some("older than the editors: select Step or Run all"),
  )
}
