///|
/// The largest active, unreadable, answered, notification, pending batch and
/// cancelled call table of any peer.
fn TranscriptChecker::table_sizes(
  self : TranscriptChecker,
) -> (Int32, Int32, Int32, Int32, Int32, Int32) {
  let mut cancelled = 0
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
    cancelled = larger(cancelled, state.cancelled.length())
  }
  (active, unreadable, answered, notifications, batches, cancelled)
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
  {
    sender: PeerName::parse(sender).unwrap(),
    message,
    receiver: None,
    location: None,
  }
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
      let (active, unreadable, answered, notifications, batches, _) = checker.table_sizes()
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

///|
/// A session protocol whose cancel notification names a ping call.
fn cancelling_protocol() -> ProtocolDescription raise {
  let loaded = loader()
    .add_idl(
      "cancelling.smithy",
      (
        #|$version: "2"
        #|namespace cancelling
        #|use smithy.rpc#jsonRpc
        #|use smithy.rpc#jsonRpcCancels
        #|use smithy.rpc#jsonRpcProtocol
        #|use smithy.rpc#jsonRpcSession
        #|use smithy.rpc#method
        #|@jsonRpcProtocol(versions: ["2.0"], peers: [{name: "client"}, {name: "server", accepts: Api}])
        #|@jsonRpcSession(states: ["open"])
        #|structure Link {}
        #|@jsonRpc(versions: ["2.0"])
        #|service Api { version: "1", operations: [Ping, Cancel] }
        #|@method(name: "ping", params: "named", nullResult: true)
        #|operation Ping {}
        #|@method(name: "cancel", params: "named", nullResult: true)
        #|@jsonRpcCancels(idMember: "id", code: -32800)
        #|operation Cancel { input: CancelInput }
        #|structure CancelInput { id: Integer }
      ),
    )
    .assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  ProtocolDescription::from_smithy(
    model,
    @smithy.ShapeId::parse("cancelling#Link").unwrap(),
    V2_0,
  )
}

///|
test "cancelled calls stay within the active call limit" {
  let limits = TranscriptLimits::new(active_calls=4)
  let checker = TranscriptChecker::new(cancelling_protocol(), limits~)
  let mut largest = 0
  for i in 0..<3000 {
    let message = match i % 3 {
      // Calls pile up beyond the limit, and every one is cancelled.
      0 => "{\"jsonrpc\": \"2.0\", \"id\": \{i}, \"method\": \"ping\"}"
      1 =>
        "{\"jsonrpc\": \"2.0\", \"method\": \"cancel\", \"params\": {\"id\": \{i - 1}}}"
      // Every fifth cycle answers one of the cancelled calls.
      _ if i / 3 % 5 == 0 =>
        "{\"jsonrpc\": \"2.0\", \"id\": \{i - 2}, \"error\": {\"code\": -32800, \"message\": \"cancelled\"}}"
      _ =>
        "{\"jsonrpc\": \"2.0\", \"method\": \"cancel\", \"params\": {\"id\": 0}}"
    }
    let sender = if message.contains("error") { "server" } else { "client" }
    checker.feed({
      sender: PeerName::parse(sender).unwrap(),
      message,
      receiver: None,
      location: None,
    })
    |> ignore
    let (active, _, _, _, _, cancelled) = checker.table_sizes()
    assert_true(cancelled <= 4, msg="cancelled calls at entry \{i}")
    assert_true(cancelled <= active, msg="cancelled calls at entry \{i}")
    largest = larger(largest, cancelled)
  }
  assert_eq(largest, 4)
}

///|
test "batch cancellations stay within their batches" {
  let limits = TranscriptLimits::new(active_calls=4)
  let checker = TranscriptChecker::new(cancelling_protocol(), limits~)
  let client = PeerName::parse("client").unwrap()
  let server = PeerName::parse("server").unwrap()
  let ping = id => "{\"jsonrpc\": \"2.0\", \"id\": \{id}, \"method\": \"ping\"}"
  let cancel = id => {
    "{\"jsonrpc\": \"2.0\", \"method\": \"cancel\", \"params\": {\"id\": \{id}}}"
  }
  let failure = id => {
    "{\"jsonrpc\": \"2.0\", \"id\": \{id}, \"error\": {\"code\": -32800, \"message\": \"cancelled\"}}"
  }
  let mut largest = 0
  // The cycles whose batch the checker tracks and no reply answered.
  let tracked : Array[Int32] = []
  for i in 0..<1000 {
    let (a, b) = (2 * i, 2 * i + 1)
    // Batches pile up beyond the limit, and every call in them is cancelled,
    // alone and from another batch.
    let batch = checker.feed({
      sender: client,
      message: "[" + ping(a) + ", " + ping(b) + "]",
      receiver: None,
      location: None,
    })
    if batch.is_empty() {
      tracked.push(i)
    }
    for message in [cancel(a), "[" + cancel(b) + "]"] {
      checker.feed({ sender: client, message, receiver: None, location: None, })
      |> ignore
    }
    // Every fifth cycle answers the oldest tracked batch.
    if i % 5 == 0 && !tracked.is_empty() {
      let j = tracked.remove(0)
      let found = checker.feed({
        sender: server,
        message: "[" + failure(2 * j) + ", " + failure(2 * j + 1) + "]",
        receiver: None,
        location: None,
      })
      assert_eq(found, [], msg="excused batch reply at cycle \{i}")
    }
    let (active, _, _, _, batches, cancelled) = checker.table_sizes()
    assert_true(cancelled <= active, msg="cancelled calls at cycle \{i}")
    assert_true(batches <= 4, msg="pending batches at cycle \{i}")
    for state in checker.peers {
      for batch in state.batches {
        assert_true(
          batch.cancelled.length() <= batch.keys.length() &&
          batch.cancelled.keys().all(key => batch.keys.contains(key)),
          msg="batch cancellations at cycle \{i}",
        )
        largest = larger(largest, batch.cancelled.length())
      }
    }
  }
  assert_eq(largest, 2)
}
