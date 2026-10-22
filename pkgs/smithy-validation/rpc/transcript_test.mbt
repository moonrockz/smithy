///|
fn entry(sender : String, message : String) -> @rpc.TranscriptEntry {
  { sender: peer(sender), message, receiver: None, location: None, }
}

///|
fn codes(findings : Array[@rpc.TranscriptFinding]) -> Array[String] {
  findings.map(f => f.code.to_string())
}

///|
fn chat() -> @rpc.ProtocolDescription raise {
  describe(load(peers_source()), "example.peers#EchoChat", @rpc.V1_0)
}

///|
fn editor() -> @rpc.ProtocolDescription raise {
  describe(load(peers_source()), "example.peers#Editor", @rpc.V2_0)
}

///|
fn hover(id : String) -> String {
  "{\"jsonrpc\": \"2.0\", \"id\": " +
  id +
  ", \"method\": \"textDocument/hover\", \"params\": {\"uri\": \"file:///a\"}}"
}

///|
fn hover_reply(id : String) -> String {
  "{\"jsonrpc\": \"2.0\", \"id\": " + id + ", \"result\": \"docs\"}"
}

///|
test "version 1 echo transcript is valid" {
  let checker = @rpc.TranscriptChecker::new(chat(), completeness=Complete)
  let found = checker.feed_all([
    entry(
      "client", "{\"method\": \"echo\", \"params\": [\"Hello JSON-RPC\"], \"id\": 1}",
    ),
    entry(
      "server", "{\"result\": \"Hello JSON-RPC\", \"error\": null, \"id\": 1}",
    ),
  ])
  assert_eq(found, [])
  let summary = checker.finish()
  assert_eq(summary.findings, [])
  assert_eq(summary.entries, 2)
  assert_eq(summary.outstanding, 0)
  assert_true(summary.complete)
  assert_true(summary.correlation)
}

///|
test "version 1 chat transcript allows reverse notifications" {
  let checker = @rpc.TranscriptChecker::new(chat(), completeness=Complete)
  let found = checker.feed_all([
    entry(
      "client", "{\"method\": \"postMessage\", \"params\": [\"Hello all!\"], \"id\": 99}",
    ),
    entry("server", "{\"result\": 1, \"error\": null, \"id\": 99}"),
    entry(
      "server", "{\"method\": \"handleMessage\", \"params\": [\"user1\", \"we were just talking\"], \"id\": null}",
    ),
    entry(
      "server", "{\"method\": \"handleMessage\", \"params\": [\"user3\", \"sorry, gotta go now, ttyl\"], \"id\": null}",
    ),
    entry(
      "client", "{\"method\": \"postMessage\", \"params\": [\"I have a question:\"], \"id\": 101}",
    ),
    entry(
      "server", "{\"method\": \"userLeft\", \"params\": [\"user3\"], \"id\": null}",
    ),
    entry("server", "{\"result\": 1, \"error\": null, \"id\": 101}"),
  ])
  assert_eq(found, [])
  let summary = checker.finish()
  assert_eq(summary.findings, [])
  assert_eq(summary.outstanding, 0)
}

///|
test "version 1 null id replies to notifications are findings" {
  let checker = @rpc.TranscriptChecker::new(chat())
  let found = checker.feed_all([
    entry(
      "server", "{\"method\": \"userLeft\", \"params\": [\"user3\"], \"id\": null}",
    ),
    entry("client", "{\"result\": null, \"error\": null, \"id\": null}"),
    entry("client", "{\"result\": null, \"error\": null, \"id\": null}"),
  ])
  assert_eq(codes(found), ["ResponseToNotification", "UnsolicitedResponse"])
  assert_eq(found[0].entry, Some(1))
  assert_eq(found[0].related, [0])
  assert_eq(found[0].sender, Some(peer("client")))
}

///|
test "reply ids match exactly per sender" {
  let checker = @rpc.TranscriptChecker::new(editor(), completeness=Complete)
  let found = checker.feed_all([
    entry("client", hover("1")),
    entry("server", hover_reply("1.0")),
    entry("client", hover("2")),
    entry("server", hover_reply("20e-1")),
    entry("client", hover("3")),
    entry("server", hover_reply("\"3\"")),
  ])
  assert_eq(codes(found), ["UnsolicitedResponse"])
  assert_eq(found[0].entry, Some(5))
  assert_eq(found[0].severity, @validation.Error)
  assert_true(found[0].message.contains("entry 5"))
  assert_true(found[0].message.contains("\"3\""))
  let summary = checker.finish()
  assert_eq(codes(summary.findings), ["MissingResponse"])
  assert_eq(summary.findings[0].entry, Some(4))
}

///|
test "each peer has its own id space" {
  let checker = @rpc.TranscriptChecker::new(editor(), completeness=Complete)
  let found = checker.feed_all([
    entry("client", hover("1")),
    entry(
      "server", "{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"workspace/configuration\", \"params\": {}}",
    ),
    entry("client", "{\"jsonrpc\": \"2.0\", \"id\": 1, \"result\": [\"a\"]}"),
    entry("server", hover_reply("1")),
  ])
  assert_eq(found, [])
  assert_eq(checker.finish().findings, [])
}

///|
test "replies before calls are unsolicited and the call stays outstanding" {
  let checker = @rpc.TranscriptChecker::new(editor())
  let found = checker.feed_all([
    entry("server", hover_reply("1")),
    entry("client", hover("1")),
  ])
  assert_eq(codes(found), ["UnsolicitedResponse"])
  assert_eq(found[0].entry, Some(0))
  let summary = checker.finish()
  assert_eq(codes(summary.findings), ["OutstandingCall"])
  assert_eq(summary.findings[0].severity, @validation.Advisory)
  assert_eq(summary.findings[0].entry, Some(1))
  assert_eq(summary.outstanding, 1)
}

///|
test "duplicate wrong responder and reused id findings carry related entries" {
  let duplicate = @rpc.TranscriptChecker::new(editor())
  let found = duplicate.feed_all([
    entry("client", hover("1")),
    entry("server", hover_reply("1")),
    entry("server", hover_reply("1")),
  ])
  assert_eq(codes(found), ["DuplicateResponse"])
  assert_eq(found[0].entry, Some(2))
  assert_eq(found[0].related, [1])
  let reused = @rpc.TranscriptChecker::new(editor())
  let found = reused.feed_all([
    entry("client", hover("1")),
    entry("client", hover("1")),
    entry("client", hover_reply("1")),
  ])
  assert_eq(codes(found), ["ActiveIdReused", "WrongResponder"])
  assert_eq(found[0].entry, Some(1))
  assert_eq(found[0].related, [0])
  assert_eq(found[1].entry, Some(2))
  assert_eq(found[1].related, [0])
  assert_true(
    found[1].message.contains("server") && found[1].message.contains("client"),
  )
}

///|
test "matched replies are validated against the called operation" {
  let checker = @rpc.TranscriptChecker::new(editor())
  let found = checker.feed_all([
    entry("client", hover("1")),
    entry("server", "{\"jsonrpc\": \"2.0\", \"id\": 1, \"result\": 5}"),
  ])
  assert_eq(codes(found), ["TypeMismatch"])
  assert_eq(found[0].code, Message(Value(@validation.TypeMismatch)))
  assert_eq(found[0].entry, Some(1))
  assert_eq(found[0].related, [0])
  guard found[0].finding is Some(finding) else { fail("no message finding") }
  assert_eq(
    finding.operation.map(id => id.to_string()),
    Some("example.peers#Hover"),
  )
}

///|
test "null id error replies link unreadable entries" {
  let parse_error = "{\"jsonrpc\": \"2.0\", \"error\": {\"code\": -32700, \"message\": \"Parse error\"}, \"id\": null}"
  let checker = @rpc.TranscriptChecker::new(editor(), completeness=Complete)
  let found = checker.feed(
    entry(
      "client", "{\"jsonrpc\": \"2.0\", \"method\": \"foobar, \"params\": \"bar\", \"baz]",
    ),
  )
  assert_eq(codes(found), ["InvalidJson"])
  assert_eq(checker.feed(entry("server", parse_error)), [])
  assert_eq(codes(checker.feed(entry("server", parse_error))), [
    "UnsolicitedResponse",
  ])
  assert_eq(checker.finish().findings, [])
  let ambiguous = @rpc.TranscriptChecker::new(editor())
  ambiguous.feed(entry("client", "{")) |> ignore
  let found = ambiguous.feed(
    entry(
      "client", "{\"jsonrpc\": \"2.0\", \"id\": null, \"method\": \"shutdown\"}",
    ),
  )
  assert_eq(codes(found), ["DiscouragedId"])
  let found = ambiguous.feed(entry("server", parse_error))
  assert_eq(codes(found), ["AmbiguousId"])
  assert_eq(found[0].severity, @validation.Advisory)
  assert_eq(found[0].related, [0, 1])
  // The explicit-null call is still active.
  assert_eq(ambiguous.finish().outstanding, 1)
}

///|
test "completeness decides missing replies" {
  let complete = @rpc.TranscriptChecker::new(editor(), completeness=Complete)
  assert_eq(complete.feed(entry("client", hover("7"))), [])
  let summary = complete.finish()
  assert_eq(codes(summary.findings), ["MissingResponse"])
  assert_eq(summary.findings[0].severity, @validation.Error)
  assert_eq(summary.findings[0].entry, Some(0))
  assert_eq(summary.findings[0].sender, Some(peer("client")))
  assert_true(summary.findings[0].message.contains("7"))
  let partial = @rpc.TranscriptChecker::new(editor(), completeness=Partial)
  partial.feed(entry("client", hover("7"))) |> ignore
  let summary = partial.finish()
  assert_eq(codes(summary.findings), ["OutstandingCall"])
  assert_eq(summary.findings[0].severity, @validation.Advisory)
  let quiet = @rpc.TranscriptChecker::new(editor(), completeness=Complete)
  assert_eq(
    quiet.feed(entry("client", "{\"jsonrpc\": \"2.0\", \"method\": \"exit\"}")),
    [],
  )
  let summary = quiet.finish()
  assert_eq(summary.findings, [])
  assert_eq(summary.outstanding, 0)
}

///|
test "unknown peers and oversized entries are findings" {
  let limits = @rpc.TranscriptLimits::new(entry_bytes=40)
  let checker = @rpc.TranscriptChecker::new(editor(), limits~)
  let found = checker.feed_all([
    entry("nobody", hover("1")),
    entry("client", hover("1")),
    entry("client", "{\"jsonrpc\": \"2.0\", \"method\": \"exit\"}"),
  ])
  assert_eq(codes(found), ["UnknownPeer", "EntryLimit"])
  assert_eq(found[0].entry, Some(0))
  assert_eq(found[0].sender, Some(peer("nobody")))
  assert_true(found[0].message.contains("nobody"))
  assert_eq(found[1].entry, Some(1))
  assert_eq(checker.finish().outstanding, 0)
  try @rpc.TranscriptLimits::new(active_calls=0) catch {
    @validation.ConfigurationError(message) =>
      assert_true(message.contains("active_calls"))
  } noraise {
    _ => fail("I expected a zero limit to be rejected.")
  }
}

///|
test "finding and active call limits are findings" {
  let checker = @rpc.TranscriptChecker::new(
    editor(),
    limits=@rpc.TranscriptLimits::new(findings=3),
  )
  let found = checker.feed_all([
    entry("nobody", "{}"),
    entry("nobody", "{}"),
    entry("nobody", "{}"),
    entry("nobody", "{}"),
  ])
  assert_eq(codes(found), ["UnknownPeer", "UnknownPeer", "FindingLimit"])
  assert_eq(found[2].severity, @validation.Error)
  assert_false(checker.finish().complete)
  let bounded = @rpc.TranscriptChecker::new(
    editor(),
    completeness=Complete,
    limits=@rpc.TranscriptLimits::new(active_calls=1),
  )
  let found = bounded.feed_all([
    entry("client", hover("1")),
    entry("client", hover("2")),
  ])
  assert_eq(codes(found), ["ActiveCallLimit"])
  assert_eq(found[0].entry, Some(1))
  let summary = bounded.finish()
  assert_eq(summary.outstanding, 1)
  assert_false(summary.complete)
}

///|
test "correlation off checks messages only" {
  let checker = @rpc.TranscriptChecker::new(
    editor(),
    completeness=Complete,
    correlation=false,
  )
  let found = checker.feed_all([
    entry("server", hover_reply("1")),
    entry("client", hover("2")),
    entry("server", "{\"jsonrpc\": \"1.0\", \"id\": 2, \"result\": \"x\"}"),
  ])
  assert_eq(codes(found), ["LimitedScope", "LimitedScope", "InvalidVersion"])
  assert_eq(found[0].severity, @validation.Advisory)
  let summary = checker.finish()
  assert_eq(summary.findings, [])
  assert_false(summary.correlation)
  assert_eq(summary.outstanding, 0)
}

///|
test "finish is idempotent and feed after finish is ignored" {
  let checker = @rpc.TranscriptChecker::new(editor(), completeness=Complete)
  checker.feed(entry("client", hover("1"))) |> ignore
  let first = checker.finish()
  assert_eq(checker.feed(entry("server", hover_reply("1"))), [])
  assert_eq(checker.feed_all([entry("nobody", "{}")]), [])
  let second = checker.finish()
  assert_eq(first.findings, second.findings)
  assert_eq(second.entries, 1)
  assert_eq(second.outstanding, 1)
}

///|
test "peers that accept nothing receive no methods" {
  let one_way = describe(
    load(peers_source()),
    "example.peers#OneWay",
    @rpc.V2_0,
  )
  let checker = @rpc.TranscriptChecker::new(one_way, completeness=Complete)
  let found = checker.feed_all([
    entry(
      "sender", "{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"push\", \"params\": {}}",
    ),
    entry(
      "listener", "{\"jsonrpc\": \"2.0\", \"id\": 4, \"method\": \"push\", \"params\": {}}",
    ),
    entry("sender", "{\"jsonrpc\": \"2.0\", \"id\": 4, \"result\": null}"),
    entry(
      "listener", "{\"jsonrpc\": \"2.0\", \"id\": 1, \"error\": {\"code\": -32601, \"message\": \"no\"}}",
    ),
  ])
  assert_eq(codes(found), ["UnknownMethod"])
  assert_eq(found[0].entry, Some(0))
  guard found[0].finding is Some(finding) else { fail("no message finding") }
  assert_eq(finding.shape.to_string(), "example.peers#OneWay")
  assert_eq(checker.finish().findings, [])
}

///|
test "transcript findings render as JSON" {
  let checker = @rpc.TranscriptChecker::new(editor())
  let found = checker.feed_all([
    entry("client", hover("1")),
    entry("server", "{\"jsonrpc\": \"2.0\", \"id\": 1, \"result\": 5}"),
    entry("server", hover_reply("9")),
    {
      sender: peer("client"),
      receiver: None,
      message: hover("2"),
      location: Some({ line: 3, column: 5, }),
    },
  ])
  let json = found.map(f => @json.to_json(f))
  assert_eq(json.length(), 2)
  guard json[0] is Object(first) else { fail("expected an object") }
  assert_eq(first.get("code"), Some(Json::string("TypeMismatch")))
  assert_eq(first.get("severity"), Some(Json::string("error")))
  assert_eq(first.get("entry"), Some(Json::number(1)))
  assert_eq(first.get("sender"), Some(Json::string("server")))
  assert_eq(first.get("related"), Some(Json::array([Json::number(0)])))
  assert_eq(first.get("operation"), Some(Json::string("example.peers#Hover")))
  assert_eq(first.get("line"), Some(Json::null()))
  guard json[1] is Object(second) else { fail("expected an object") }
  assert_eq(second.get("code"), Some(Json::string("UnsolicitedResponse")))
  assert_eq(second.get("path"), Some(Json::null()))
  assert_eq(second.get("shape"), Some(Json::null()))
  let outstanding = @json.to_json(checker.finish().findings[0])
  guard outstanding is Object(third) else { fail("expected an object") }
  assert_eq(third.get("severity"), Some(Json::string("advisory")))
  assert_eq(third.get("line"), Some(Json::number(3)))
  assert_eq(third.get("column"), Some(Json::number(5)))
}

///|
test "transcript codes keep the stable code names" {
  assert_eq(@rpc.DuplicateReply.to_string(), "DuplicateResponse")
  assert_eq(@rpc.MissingReply.to_string(), "MissingResponse")
  assert_eq(@rpc.AmbiguousReplyId.to_string(), "AmbiguousId")
  assert_eq(
    @rpc.TranscriptCode::Message(@rpc.MissingResponse).to_string(),
    "MissingResponse",
  )
  // FindingCode constructors stay unambiguous without a qualifier.
  let codes = [@rpc.DuplicateResponse, @rpc.MissingResponse, @rpc.AmbiguousId]
  assert_eq(codes.length(), 3)
}

///|
test "a named receiver must be the other peer" {
  let checker = @rpc.TranscriptChecker::new(editor())
  let found = checker.feed_all([
    { ..entry("client", hover("1")), receiver: Some(peer("server")), },
    { ..entry("client", hover("2")), receiver: Some(peer("client")), },
    { ..entry("client", hover("3")), receiver: Some(peer("nobody")), },
  ])
  assert_eq(codes(found), ["UnknownPeer", "UnknownPeer"])
  assert_eq(found.map(f => f.entry), [Some(1), Some(2)])
  assert_eq(checker.finish().outstanding, 1)
}

///|
test "version 1 replies to unreadable entries and invalid calls check the envelope" {
  let error_reply = "{\"result\": null, \"error\": \"bad request\", \"id\": null}"
  // A null-id reply links the unreadable entry and adds no context finding.
  let checker = @rpc.TranscriptChecker::new(chat(), completeness=Complete)
  assert_eq(codes(checker.feed(entry("client", "{"))), ["InvalidJson"])
  assert_eq(checker.feed(entry("server", error_reply)), [])
  assert_eq(checker.finish().findings, [])
  // A call with an invalid 1.0 envelope and a usable id is linked by its id.
  let invalid = @rpc.TranscriptChecker::new(chat(), completeness=Complete)
  let found = invalid.feed(entry("client", "{\"method\": \"echo\", \"id\": 1}"))
  assert_true(found.length() > 0)
  assert_true(found.iter().all(f => f.code.to_string() != "InvalidContext"))
  assert_eq(
    invalid.feed(
      entry(
        "server", "{\"result\": null, \"error\": \"bad request\", \"id\": 1}",
      ),
    ),
    [],
  )
  assert_eq(invalid.finish().findings, [])
  // Envelope errors in such a reply are still reported, linked to the call.
  let broken = @rpc.TranscriptChecker::new(chat(), completeness=Complete)
  broken.feed(entry("client", "{")) |> ignore
  let found = broken.feed(entry("server", "{\"result\": 1, \"id\": null}"))
  assert_true(found.length() > 0)
  assert_true(
    found
    .iter()
    .all(f => {
      f.severity == @validation.Error &&
      f.related == [0] &&
      f.code.to_string() != "InvalidContext" &&
      f.code.to_string() != "LimitedScope"
    }),
  )
}

///|
test "version 1 structured ids correlate by structure" {
  fn call(id : String) -> String {
    "{\"method\": \"echo\", \"params\": [\"a\"], \"id\": " + id + "}"
  }

  fn reply(id : String) -> String {
    "{\"result\": \"a\", \"error\": null, \"id\": " + id + "}"
  }

  let checker = @rpc.TranscriptChecker::new(chat(), completeness=Complete)
  let found = checker.feed_all([
    entry("client", call("[1,{\"b\":2}]")),
    entry("client", call("{\"k\":[1,2]}")),
    // Whitespace and member order do not change a structured id.
    entry("server", reply("{ \"k\" : [1, 2] }")),
    entry("server", reply("[1, {\"b\": 2}]")),
  ])
  assert_eq(found.filter(f => f.severity == @validation.Error), [])
  assert_eq(checker.finish().findings, [])
  // A second reply to a structured id is a duplicate of the first.
  let twice = @rpc.TranscriptChecker::new(chat(), completeness=Complete)
  let found = twice.feed_all([
    entry("client", call("{\"k\":[1,2]}")),
    entry("server", reply("{\"k\":[1,2]}")),
    entry("server", reply("{\"k\":[1,2]}")),
    // A different structure matches no call.
    entry("server", reply("{\"k\":[2,1]}")),
  ])
  let errors = found.filter(f => f.severity == @validation.Error)
  assert_eq(codes(errors), ["DuplicateResponse", "UnsolicitedResponse"])
  assert_eq(errors[0].entry, Some(2))
  assert_eq(errors[0].related, [1])
  assert_eq(errors[1].entry, Some(3))
  // Two calls whose structured ids are equal reuse an active id.
  let reused = @rpc.TranscriptChecker::new(chat())
  let found = reused.feed_all([
    entry("client", call("[1,{\"b\":2}]")),
    entry("client", call("[1, {\"b\" : 2}]")),
  ])
  assert_eq(codes(found.filter(f => f.severity == @validation.Error)), [
    "ActiveIdReused",
  ])
}
