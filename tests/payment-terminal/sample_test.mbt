///|
fn sample_model() -> @smithy.Model raise {
  let path = "../examples/payment-terminal/model.smithy"
  let loaded = @rpc.loader()
    .add_idl(path, @fs.read_file_to_string(path))
    .assemble()
  assert_eq(loaded.validation_events().filter(e => e.severity == "ERROR"), [])
  loaded.model.unwrap()
}

///|
fn sample_run(name : String) -> @rpc.TranscriptRun raise {
  let protocol = @rpc.ProtocolDescription::from_smithy(
    sample_model(),
    @smithy.ShapeId::parse("example.payments#TerminalProtocol").unwrap(),
    @rpc.V2_0,
  )
  let (document, problems) = @rpc.read_json_transcript(
    @fs.read_file_to_string("../examples/payment-terminal/transcripts/" + name),
  )
  let run = @rpc.run_transcript(protocol, document, problems)
  assert_eq(run.summary.outstanding, 0)
  assert_true(run.summary.complete)
  run
}

///|
test "payment terminal model prepares both peer services" {
  let protocol = @rpc.ProtocolDescription::from_smithy(
    sample_model(),
    @smithy.ShapeId::parse("example.payments#TerminalProtocol").unwrap(),
    @rpc.V2_0,
  )
  assert_eq(protocol.peers().map(p => p.to_string()), ["pos", "terminal"])
  assert_eq(
    protocol
    .service_for(@rpc.PeerName::parse("terminal").unwrap())
    .unwrap()
    .operation(@rpc.MethodName::parse("payment.start").unwrap())
    .unwrap()
    .to_string(),
    "example.payments#StartPayment",
  )
}

///|
test "payment scenario checks callbacks and exact payloads" {
  assert_eq(sample_run("payment.json").findings, [])
}

///|
test "payment cancellation finishes the active call" {
  assert_eq(sample_run("cancellation.json").findings, [])
}

///|
test "payment errors check each data mapping and union choice" {
  assert_eq(sample_run("errors.json").findings, [])
}

///|
test "payment refusals use the modeled error codes" {
  let matched = sample_run("refusals.json").expectations.unwrap()
  assert_eq(matched.missing, [])
  assert_eq(matched.unexpected, [])
}

///|
test "payment method kinds and active call references reject wrong messages" {
  let matched = sample_run("invalid-kinds-and-progress.json").expectations.unwrap()
  assert_eq(matched.missing, [])
  assert_eq(matched.unexpected, [])
}
