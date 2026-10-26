///|
fn refusal_model() -> @smithy.Model raise {
  load(
    (
      #|$version: "2"
      #|namespace refusal
      #|use smithy.rpc#jsonRpc
      #|use smithy.rpc#jsonRpcProtocol
      #|use smithy.rpc#jsonRpcSession
      #|use smithy.rpc#jsonRpcLifecycle
      #|use smithy.rpc#method
      #|@jsonRpcProtocol(versions: ["2.0"], peers: [{name: "a"}, {name: "b", accepts: S}])
      #|@jsonRpcSession(states: ["starting", "ready"], refusals: [{states: ["starting"], code: 1007}], capabilityRefusal: 1008, capabilities: [{name: "fast", method: "init", pointer: "/fast"}])
      #|structure P {}
      #|@jsonRpc(versions: ["2.0"])
      #|service S { version: "1", operations: [Init, Work] }
      #|@method(name: "init", params: "named")
      #|@jsonRpcLifecycle(allowedIn: ["starting"], onSuccess: "ready")
      #|operation Init { output: InitOutput }
      #|structure InitOutput { fast: Boolean }
      #|@method(name: "work", params: "named", nullResult: true)
      #|@jsonRpcLifecycle(allowedIn: ["ready"], requires: ["fast"])
      #|operation Work {}
    ),
  )
}

///|
test "refused calls require the modeled refusal reply" {
  let protocol = describe(refusal_model(), "refusal#P", @rpc.V2_0)
  for reply in [success(1, "null"), failure(1, 1006), failure(1, 1007)] {
    let checker = @rpc.TranscriptChecker::new(protocol, completeness=Complete)
    let found = checker.feed_all([
      entry("a", call(1, "work")),
      entry("b", reply),
    ])
    assert_eq(
      summary_of(found),
      if reply == failure(1, 1007) {
        ["StateViolation@0[]", "CapabilityNotAdvertised@0[]"]
      } else {
        [
          "StateViolation@0[]", "CapabilityNotAdvertised@0[]", "RefusalExpected@1[0]",
        ]
      },
    )
    assert_eq(checker.finish().findings, [])
  }
}

///|
test "capability refusals use their code and state refusals without a code accept any error" {
  let protocol = describe(refusal_model(), "refusal#P", @rpc.V2_0)
  let checker = @rpc.TranscriptChecker::new(protocol, completeness=Complete)
  let found = checker.feed_all([
    entry("a", call(1, "init")),
    entry("b", success(1, "{}")),
    entry("a", call(2, "work")),
    entry("b", failure(2, 1008)),
    entry("a", call(3, "work")),
    entry("b", failure(3, 1007)),
    entry("a", call(4, "init")),
    entry("b", failure(4, -32600)),
    entry("a", call(5, "init")),
    entry("b", success(5, "{}")),
  ])
  assert_eq(summary_of(found), [
    "CapabilityNotAdvertised@2[0]", "CapabilityNotAdvertised@4[0]", "RefusalExpected@5[4]",
    "StateViolation@6[1]", "StateViolation@8[1]", "RefusalExpected@9[8]",
  ])
  assert_eq(checker.finish().findings, [])
}

///|
test "batch replies use the refusal codes of their calls" {
  let protocol = describe(refusal_model(), "refusal#P", @rpc.V2_0)
  let checker = @rpc.TranscriptChecker::new(protocol, completeness=Complete)
  let found = checker.feed_all([
    entry("a", "[" + call(1, "work") + "," + call(2, "work") + "]"),
    entry("b", "[" + failure(1, 1007) + "," + success(2, "null") + "]"),
  ])
  assert_eq(summary_of(found), [
    "StateViolation@0[]", "CapabilityNotAdvertised@0[]", "StateViolation@0[]", "CapabilityNotAdvertised@0[]",
    "RefusalExpected@1[0]",
  ])
  assert_eq(checker.finish().findings, [])
}

///|
test "refusal preparation rejects invalid state and code mappings" {
  for
    raw in [
      "{\"refusals\":\"bad\"}", "{\"refusals\":[{\"states\":[\"starting\"]}]}", "{\"refusals\":[{\"states\":[],\"code\":7}]}",
      "{\"refusals\":[{\"states\":[\"missing\"],\"code\":7}]}", "{\"refusals\":[{\"states\":[\"starting\",\"starting\"],\"code\":7}]}",
      "{\"refusals\":[{\"states\":[\"starting\"],\"code\":1.5}]}", "{\"capabilityRefusal\":\"7\"}",
    ] {
    let model = refusal_model()
    let protocol = model.shapes[@smithy.ShapeId::parse("refusal#P").unwrap()]
    let session_id = @smithy.ShapeId::parse("smithy.rpc#jsonRpcSession").unwrap()
    guard protocol.traits[session_id] is @smithy.Object(session) &&
      @smithy.NodeValue::from_json(@json.parse(raw)) is @smithy.Object(changes) else {
      fail("I expected session trait objects.")
    }
    for key, value in changes {
      session[key] = value
    }
    try describe(model, "refusal#P", @rpc.V2_0) catch {
      @rpc.InvalidContract(_, message) =>
        assert_true(message.contains("jsonRpcSession"))
      error => fail("I expected a refusal contract error; I found \{error}.")
    } noraise {
      _ => fail("I expected an invalid refusal mapping to be refused.")
    }
  }
}

///|
test "legacy refusal without a modeled code accepts an opaque error" {
  let model = load(
    (
      #|$version: "2"
      #|namespace legacyrefusal
      #|use smithy.rpc#jsonRpc
      #|use smithy.rpc#jsonRpcProtocol
      #|use smithy.rpc#jsonRpcSession
      #|use smithy.rpc#jsonRpcLifecycle
      #|use smithy.rpc#method
      #|@jsonRpcProtocol(versions: ["1.0"], peers: [{name: "a"}, {name: "b", accepts: S}])
      #|@jsonRpcSession(states: ["starting", "ready"])
      #|structure P {}
      #|@jsonRpc(versions: ["1.0"])
      #|service S { version: "1", operations: [Work] }
      #|@method(name: "work", params: "either", positional: [], nullResult: true)
      #|@jsonRpcLifecycle(allowedIn: ["ready"])
      #|operation Work {}
    ),
  )
  let checker = @rpc.TranscriptChecker::new(
    describe(model, "legacyrefusal#P", @rpc.V1_0),
    completeness=Complete,
  )
  let found = checker.feed_all([
    entry("a", "{\"id\":1,\"method\":\"work\",\"params\":[]}"),
    entry("b", "{\"id\":1,\"result\":null,\"error\":\"refused\"}"),
  ])
  assert_eq(summary_of(found), ["StateViolation@0[]"])
  assert_eq(checker.finish().findings, [])
}
