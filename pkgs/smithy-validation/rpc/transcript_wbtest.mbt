///|
/// The largest active, unreadable, answered, notification and pending batch
/// table of any peer.
fn TranscriptChecker::table_sizes(
  self : TranscriptChecker,
) -> (Int32, Int32, Int32, Int32, Int32) {
  let mut active = 0
  let mut unreadable = 0
  let mut batches = 0
  let mut answered = 0
  let mut notifications = 0
  for state in self.peers {
    active = larger(active, state.active.length())
    unreadable = larger(unreadable, state.unreadable.length())
    answered = larger(
      answered,
      larger(state.answered.length(), state.answered_order.length()),
    )
    notifications = larger(notifications, state.notifications.length())
    batches = larger(batches, state.batches.length())
  }
  (active, unreadable, answered, notifications, batches)
}

///|
fn larger(a : Int32, b : Int32) -> Int32 {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn bounded_protocol(version : ProtocolVersion) -> ProtocolDescription raise {
  let loaded = loader()
    .add_idl(
      "bounded.smithy",
      (
        #|$version: "2"
        #|namespace bounded
        #|use smithy.rpc#jsonRpc
        #|use smithy.rpc#jsonRpcProtocol
        #|use smithy.rpc#method
        #|@jsonRpcProtocol(versions: ["1.0", "2.0"], peers: [{name: "client"}, {name: "server", accepts: Api}])
        #|structure Link {}
        #|@jsonRpc(versions: ["1.0", "2.0"])
        #|service Api { version: "1", operations: [Ping] }
        #|@method(name: "ping", params: "positional", positional: ["value"], nullResult: true)
        #|operation Ping { input: PingInput }
        #|structure PingInput { value: String }
      ),
    )
    .assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  ProtocolDescription::from_smithy(
    model,
    @smithy.ShapeId::parse("bounded#Link").unwrap(),
    version,
  )
}

///|
/// Answered calls, duplicate replies, unanswered calls, notifications,
/// unreadable entries and, for 2.0, unanswered batches.
fn bounded_entry(version : ProtocolVersion, i : Int32) -> TranscriptEntry {
  let marker = if version == V2_0 { "\"jsonrpc\": \"2.0\", " } else { "" }
  let error = if version == V1_0 { ", \"error\": null" } else { "" }
  let (sender, message) = match i % 6 {
    0 =>
      (
        "client",
        "{" + marker + "\"method\": \"ping\", \"params\": [], \"id\": \{i}}",
      )
    1 =>
      (
        "server",
        "{" + marker + "\"result\": null" + error + ", \"id\": \{i - 1}}",
      )
    2 =>
      (
        "client",
        "{" + marker + "\"method\": \"ping\", \"params\": [], \"id\": null}",
      )
    3 => ("client", "{")
    // Every tenth cycle leaves a call unanswered.
    4 if i / 6 % 10 == 0 =>
      (
        "client",
        "{" +
        marker +
        "\"method\": \"ping\", \"params\": [], \"id\": \"open-\{i}\"}",
      )
    // Another cycle leaves a 2.0 batch unanswered.
    4 if version == V2_0 && i / 6 % 10 == 5 =>
      (
        "client",
        "[{" +
        marker +
        "\"method\": \"ping\", \"params\": [], \"id\": \"batch-\{i}\"}]",
      )
    _ =>
      (
        "server",
        "{" + marker + "\"result\": null" + error + ", \"id\": \{i - 5}}",
      )
  }
  { sender: PeerName::parse(sender).unwrap(), message, location: None, }
}

///|
test "tables stay within limits" {
  for version in [V1_0, V2_0] {
    let limits = TranscriptLimits::new(active_calls=4, answered_ids=4)
    let checker = TranscriptChecker::new(
      bounded_protocol(version),
      completeness=Complete,
      limits~,
    )
    let mut largest = (0, 0, 0, 0, 0)
    for i in 0..<10000 {
      checker.feed(bounded_entry(version, i)) |> ignore
      let (active, unreadable, answered, notifications, batches) = checker.table_sizes()
      assert_true(active <= 4, msg="active calls at entry \{i}")
      assert_true(unreadable <= 4, msg="unreadable entries at entry \{i}")
      assert_true(answered <= 4, msg="answered ids at entry \{i}")
      assert_true(notifications <= 4, msg="notifications at entry \{i}")
      assert_true(batches <= 4, msg="pending batches at entry \{i}")
      largest = (
        larger(largest.0, active),
        larger(largest.1, unreadable),
        larger(largest.2, answered),
        larger(largest.3, notifications),
        larger(largest.4, batches),
      )
    }
    // Every table was exercised up to its limit.
    assert_eq(largest.0, 4)
    assert_eq(largest.1, 4)
    assert_eq(largest.2, 4)
    if version == V1_0 {
      assert_eq(largest.3, 4)
    } else {
      assert_eq(largest.4, 4)
    }
    let summary = checker.finish()
    assert_eq(summary.entries, 10000)
    assert_false(summary.complete)
  }
}
