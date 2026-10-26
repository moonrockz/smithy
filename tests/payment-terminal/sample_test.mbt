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

///|
test "neutral description keeps the payment terminal protocol contract" {
  let description = @jsonrpc.Description::for_protocol(
    sample_model(),
    @smithy.ShapeId::parse("example.payments#TerminalProtocol").unwrap(),
    @rpc.V2_0,
  )
  let terminal = description
    .peer(@rpc.PeerName::parse("terminal").unwrap())
    .unwrap()
  let pos = description.peer(@rpc.PeerName::parse("pos").unwrap()).unwrap()
  assert_eq(terminal.accepts.unwrap().methods.length(), 12)
  assert_eq(pos.accepts.unwrap().methods.length(), 4)
  assert_eq(terminal.calls, pos.accepts)
  assert_eq(pos.calls, terminal.accepts)
  let start = terminal.accepts.unwrap().methods
    .iter()
    .find_first(m => m.name.to_string() == "payment.start")
    .unwrap()
  assert_eq(start.kind, @rpc.RequestOnly)
  assert_eq(start.errors.map(e => e.code.to_string()), [
    "1001", "1002", "1003", "1004",
  ])
  let progress = pos.accepts.unwrap().methods
    .iter()
    .find_first(m => m.name.to_string() == "payment.progress")
    .unwrap()
  assert_eq(progress.kind, @rpc.NotificationOnly)
  assert_eq(progress.refers_to_call.unwrap().wire_name, "requestId")
  let session = description.session.unwrap()
  assert_eq(session.states.map(s => s.to_string()), [
    "starting", "initializing", "ready", "paying", "stopping", "stopped",
  ])
  assert_eq(session.capability_refusal.unwrap().to_string(), "1008")
  assert_eq(
    session.refusals.map(r => (r.state.to_string(), r.code.to_string())),
    [
      ("initializing", "1007"),
      ("starting", "1007"),
      ("stopped", "1007"),
      ("stopping", "1007"),
    ],
  )
  let rule = session.methods
    .iter()
    .find_first(m => m.method_name.to_string() == "payment.start")
    .unwrap()
  assert_eq(rule.on_call.unwrap().to_string(), "paying")
  assert_eq(rule.on_success.unwrap().to_string(), "ready")
  assert_eq(rule.on_error.unwrap().to_string(), "ready")
  assert_eq(rule.requires, ["payment"])
}
