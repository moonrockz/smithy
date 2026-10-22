///|
/// The batch service of examples/json-rpc/batches.smithy, received by the server.
fn batch_link() -> @rpc.ProtocolDescription raise {
  let model = load(
    (
      #|$version: "2"
      #|namespace batch
      #|use smithy.rpc#jsonRpc
      #|use smithy.rpc#jsonRpcProtocol
      #|use smithy.rpc#method
      #|@jsonRpcProtocol(versions: ["2.0"], peers: [{name: "client"}, {name: "server", accepts: Api}])
      #|structure Link {}
      #|@jsonRpc(versions: ["1.0", "2.0"])
      #|service Api { version: "1", operations: [Sum, Subtract, NotifyHello, GetData] }
      #|@method(name: "sum", params: "either", positional: ["a", "b", "c"], resultMember: "value")
      #|operation Sum { input: Three, output: NumberOutput }
      #|structure Three { @required a: Integer, @required b: Integer, @required c: Integer }
      #|structure NumberOutput { value: Integer }
      #|@method(name: "subtract", params: "either", positional: ["minuend", "subtrahend"], resultMember: "value")
      #|operation Subtract { input: SubtractInput, output: NumberOutput }
      #|structure SubtractInput { @required minuend: Integer, @required subtrahend: Integer }
      #|@method(name: "notify_hello", params: "either", positional: ["value"], nullResult: true)
      #|operation NotifyHello { input: One }
      #|structure One { @required value: Integer }
      #|@method(name: "get_data", params: "either", positional: [], resultMember: "value")
      #|operation GetData { output: AnyOutput }
      #|structure AnyOutput { value: Document }
    ),
  )
  describe(model, "batch#Link", @rpc.V2_0)
}

///|
/// A subtract call with `id`.
fn subtract(id : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[42,23],\"id\":" +
  id +
  "}"
}

///|
/// A subtract result with `id`.
fn difference(id : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":" + id + "}"
}

///|
fn null_error(code : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":" +
  code +
  ",\"message\":\"error\"},\"id\":null}"
}

///|
/// The JSON-RPC 2.0 section 7 mixed batch, as in examples/json-rpc/batch-mixed.json.
let mixed_batch : String =
  #|[
  #|  {"jsonrpc":"2.0","method":"sum","params":[1,2,4],"id":"1"},
  #|  {"jsonrpc":"2.0","method":"notify_hello","params":[7]},
  #|  {"jsonrpc":"2.0","method":"subtract","params":[42,23],"id":"2"},
  #|  {"foo":"boo"},
  #|  {"jsonrpc":"2.0","method":"foo.get","params":{"name":"myself"},"id":"5"},
  #|  {"jsonrpc":"2.0","method":"get_data","id":"9"}
  #|]

///|
/// The unordered replies, as in examples/json-rpc/batch-replies.json.
let mixed_replies : String =
  #|[
  #|  {"jsonrpc":"2.0","result":["hello",5],"id":"9"},
  #|  {"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"},"id":"5"},
  #|  {"jsonrpc":"2.0","result":19,"id":"2"},
  #|  {"jsonrpc":"2.0","error":{"code":-32600,"message":"Invalid Request"},"id":null},
  #|  {"jsonrpc":"2.0","result":7,"id":"1"}
  #|]

///|
test "the specification mixed batch links unordered replies" {
  let checker = @rpc.TranscriptChecker::new(batch_link(), completeness=Complete)
  let found = checker.feed_all([
    entry("client", mixed_batch),
    entry("server", mixed_replies),
  ])
  // The invalid element and the unknown method are request findings only.
  assert_true(
    found.iter().all(f => f.entry == Some(0)),
    msg=codes(found).join(", "),
  )
  assert_true(found.length() > 0)
  let summary = checker.finish()
  assert_eq(summary.findings, [])
  assert_eq(summary.outstanding, 0)
  // A wrong result is checked against its call, and names the batch.
  let checker = @rpc.TranscriptChecker::new(batch_link(), completeness=Complete)
  checker.feed(entry("client", mixed_batch)) |> ignore
  let found = checker.feed(
    entry("server", mixed_replies.replace(old="19", new="\"bad\"")),
  )
  assert_eq(codes(found), ["TypeMismatch"])
  assert_eq(found[0].entry, Some(1))
  assert_eq(found[0].related, [0])
  assert_eq(found[0].finding.map(f => f.path.pointer()), Some("/2/result"))
  assert_eq(checker.finish().findings, [])
}

///|
test "empty and invalid whole batches expect one null id error" {
  for (request, code) in [("[]", "-32600"), ("[", "-32700"), ("1", "-32600")] {
    let checker = @rpc.TranscriptChecker::new(
      batch_link(),
      completeness=Complete,
    )
    let found = checker.feed_all([
      entry("client", request),
      entry("server", null_error(code)),
    ])
    assert_true(found.iter().all(f => f.entry == Some(0)), msg=request)
    assert_eq(checker.finish().findings, [], msg=request)
  }
  // The empty batch needs the invalid-request code.
  let checker = @rpc.TranscriptChecker::new(batch_link(), completeness=Complete)
  let found = checker.feed_all([
    entry("client", "[]"),
    entry("server", null_error("-32601")),
  ])
  let reply = found.filter(f => f.entry == Some(1))
  assert_true(reply.length() > 0)
  assert_true(reply.iter().all(f => f.related == [0]))
  // An array reply is not the one error object, so it answers nothing.
  let checker = @rpc.TranscriptChecker::new(batch_link(), completeness=Complete)
  let found = checker.feed_all([
    entry("client", "[]"),
    entry("server", "[" + null_error("-32600") + "]"),
  ])
  assert_eq(codes(found.filter(f => f.entry == Some(1))), [
    "UnsolicitedResponse",
  ])
  assert_eq(codes(checker.finish().findings), ["MissingResponse"])
}

///|
test "all-notification batches need no reply" {
  let checker = @rpc.TranscriptChecker::new(batch_link(), completeness=Complete)
  let found = checker.feed(
    entry(
      "client", "[{\"jsonrpc\":\"2.0\",\"method\":\"notify_hello\",\"params\":[7]},{\"jsonrpc\":\"2.0\",\"method\":\"notify_hello\",\"params\":[8]}]",
    ),
  )
  assert_eq(found, [])
  let summary = checker.finish()
  assert_eq(summary.findings, [])
  assert_eq(summary.outstanding, 0)
}

///|
test "reply batches choose the earliest batch that contains their ids" {
  let checker = @rpc.TranscriptChecker::new(batch_link(), completeness=Complete)
  let found = checker.feed_all([
    entry("client", "[" + subtract("1") + "," + subtract("2") + "]"),
    entry("client", "[" + subtract("2") + "," + subtract("3") + "]"),
    // Both batches contain 2; the earlier one is chosen, and its call 1 has no reply.
    entry("server", "[" + difference("2") + "]"),
    // Only the second batch contains 3.
    entry("server", "[" + difference("3") + "," + difference("2.0") + "]"),
    // No batch waits any more.
    entry("server", "[" + difference("1") + "]"),
  ])
  assert_eq(codes(found), ["MissingResponse", "UnsolicitedResponse"])
  assert_eq(found[0].entry, Some(2))
  assert_eq(found[0].related, [0])
  assert_eq(found[1].entry, Some(4))
  assert_eq(found[1].related, [])
  assert_true(found[1].message.contains("entry 4"))
  assert_true(found[1].message.contains("id 1"))
  assert_eq(checker.finish().findings, [])
}

///|
test "single replies to batch calls are the wrong reply form" {
  let checker = @rpc.TranscriptChecker::new(batch_link(), completeness=Complete)
  let found = checker.feed_all([
    entry("client", "[" + subtract("1") + "]"),
    entry("server", difference("1")),
    entry("client", "[1]"),
    entry("server", null_error("-32600")),
  ])
  let replies = found.filter(f => f.entry == Some(1) || f.entry == Some(3))
  assert_eq(codes(replies), ["WrongReplyForm", "WrongReplyForm"])
  assert_eq(replies[0].related, [0])
  assert_eq(replies[1].related, [2])
  assert_true(replies[0].message.contains("entry 1"))
  assert_true(replies[0].message.contains("id 1"))
  // Both batches still wait for a reply batch.
  let summary = checker.finish()
  assert_eq(codes(summary.findings), ["MissingResponse", "MissingResponse"])
  assert_eq(summary.outstanding, 2)
}

///|
test "unanswered batches are outstanding or missing" {
  let batch = "[" + subtract("1") + "," + subtract("2") + "]"
  let partial = @rpc.TranscriptChecker::new(batch_link())
  assert_eq(partial.feed(entry("client", batch)), [])
  let summary = partial.finish()
  assert_eq(codes(summary.findings), ["OutstandingCall"])
  assert_eq(summary.findings[0].severity, @validation.Advisory)
  assert_eq(summary.findings[0].entry, Some(0))
  assert_eq(summary.findings[0].related, [0])
  assert_eq(summary.findings[0].sender, Some(peer("client")))
  assert_eq(summary.outstanding, 1)
  let complete = @rpc.TranscriptChecker::new(
    batch_link(),
    completeness=Complete,
  )
  complete.feed(entry("client", batch)) |> ignore
  let summary = complete.finish()
  assert_eq(codes(summary.findings), ["MissingResponse"])
  assert_eq(summary.findings[0].severity, @validation.Error)
  assert_eq(summary.findings[0].related, [0])
  assert_true(summary.findings[0].message.contains("entry 0"))
  assert_eq(summary.outstanding, 1)
}

///|
test "version 1 array entries are unsupported" {
  let checker = @rpc.TranscriptChecker::new(chat())
  let found = checker.feed(
    entry("client", "[{\"method\": \"echo\", \"params\": [\"a\"], \"id\": 1}]"),
  )
  assert_eq(codes(found), ["UnsupportedMessage"])
  assert_true(found[0].message.contains("1.0"))
  assert_eq(checker.finish().outstanding, 0)
}

///|
test "batches to a peer that accepts nothing are unknown methods" {
  let one_way = describe(
    load(peers_source()),
    "example.peers#OneWay",
    @rpc.V2_0,
  )
  let checker = @rpc.TranscriptChecker::new(one_way, completeness=Complete)
  let push = "{\"jsonrpc\": \"2.0\", \"method\": \"push\", \"params\": {}, \"id\": "
  let refused = "{\"jsonrpc\": \"2.0\", \"error\": {\"code\": -32601, \"message\": \"no\"}, \"id\": "
  let found = checker.feed_all([
    entry("sender", "[" + push + "1}, " + push + "2}]"),
    entry("listener", "[" + refused + "2}, " + refused + "1}]"),
  ])
  assert_eq(codes(found), ["UnknownMethod"])
  assert_eq(found[0].entry, Some(0))
  guard found[0].finding is Some(finding) else { fail("no message finding") }
  assert_eq(finding.shape.to_string(), "example.peers#OneWay")
  assert_eq(checker.finish().findings, [])
}

///|
test "batches checked only in part still link their reply batch" {
  let checker = @rpc.TranscriptChecker::new(batch_link(), completeness=Complete)
  // Each call has two type mismatches, so 60 calls exceed the 100 findings of the service.
  let calls = []
  let replies = []
  for i in 0..<60 {
    calls.push(
      "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[\"a\",\"b\"],\"id\":\{i}}",
    )
    replies.push(difference(i.to_string()))
  }
  calls.push("{\"foo\":\"boo\"}")
  calls.push("{\"jsonrpc\":\"2.0\",\"method\":\"notify_hello\",\"params\":[7]}")
  replies.push(null_error("-32600"))
  let found = checker.feed_all([
    entry("client", "[" + calls.join(",") + "]"),
    entry("server", "[" + replies.join(",") + "]"),
  ])
  let reply = found.filter(f => f.entry == Some(1))
  assert_eq(codes(reply), ["InvalidContext"])
  assert_eq(reply[0].related, [0])
  let summary = checker.finish()
  assert_eq(summary.findings, [])
  assert_eq(summary.outstanding, 0)
  assert_false(summary.complete)
}
