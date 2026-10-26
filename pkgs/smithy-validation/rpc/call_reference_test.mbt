///|
fn reference_model() -> @smithy.Model raise {
  load(
    (
      #|$version: "2"
      #|namespace reference
      #|use smithy.rpc#jsonRpc
      #|use smithy.rpc#jsonRpcProtocol
      #|use smithy.rpc#jsonRpcRefersToCall
      #|use smithy.rpc#method
      #|@jsonRpcProtocol(versions: ["2.0"], peers: [{name: "a", accepts: A}, {name: "b", accepts: B}])
      #|structure P {}
      #|@jsonRpc(versions: ["2.0"])
      #|service A { version: "1", operations: [Progress] }
      #|@jsonRpc(versions: ["2.0"])
      #|service B { version: "1", operations: [Work] }
      #|@method(name: "work", params: "named", nullResult: true)
      #|operation Work {}
      #|@method(name: "progress", params: "either", positional: ["requestId"], kind: "notification")
      #|@jsonRpcRefersToCall(idMember: "requestId")
      #|operation Progress { input: ProgressInput }
      #|structure ProgressInput { @required @jsonName("ref") requestId: Document }
    ),
  )
}

///|
test "call references name an active call of the receiving peer" {
  let protocol = @rpc.ProtocolDescription::from_smithy(
    reference_model(),
    @smithy.ShapeId::parse("reference#P").unwrap(),
    @rpc.V2_0,
    config=@validation.Config::new(member_names=@validation.JsonName),
  )
  let checker = @rpc.TranscriptChecker::new(protocol, completeness=Complete)
  let found = checker.feed_all([
    entry("a", call(1, "work")),
    entry("b", notify("progress", params="{\"ref\":1.0}")),
    entry("b", notify("progress", params="[1]")),
    entry("b", notify("progress", params="{\"ref\":\"1\"}")),
    entry("b", success(1, "null")),
    entry("b", notify("progress", params="{\"ref\":1}")),
  ])
  assert_eq(summary_of(found), [
    "UnknownCallReference@3[]", "UnknownCallReference@5[4]",
  ])
  assert_eq(checker.finish().findings, [])
}

///|
test "call reference preparation rejects a missing input member" {
  let model = reference_model()
  let operation = model.shapes[@smithy.ShapeId::parse("reference#Progress").unwrap()]
  operation.traits[@smithy.ShapeId::parse("smithy.rpc#jsonRpcRefersToCall").unwrap()] = @smithy.Object({
      "idMember": @smithy.String("missing"),
    },
  )
  try describe(model, "reference#P", @rpc.V2_0) catch {
    @rpc.InvalidContract(id, message) => {
      assert_eq(id.to_string(), "reference#Progress")
      assert_true(message.contains("idMember"))
    }
    error =>
      fail("I expected a call reference contract error; I found \{error}.")
  } noraise {
    _ => fail("I expected the call reference member missing to be refused.")
  }
}

///|
test "call references can name calls in an earlier batch" {
  let protocol = describe(reference_model(), "reference#P", @rpc.V2_0)
  let checker = @rpc.TranscriptChecker::new(protocol, completeness=Complete)
  let found = checker.feed_all([
    entry("a", "[" + call(1, "work") + "]"),
    entry("b", notify("progress", params="{\"requestId\":1}")),
    entry("b", "[" + success(1, "null") + "]"),
    entry("b", notify("progress", params="{\"requestId\":1}")),
    entry("b", call(2, "work")),
    entry("b", notify("progress", params="{\"requestId\":2}")),
    entry("a", failure(2, -32601)),
  ])
  assert_eq(summary_of(found), [
    "UnknownCallReference@3[]", "UnknownMethod@4[]", "UnknownCallReference@5[]",
  ])
  assert_eq(checker.finish().findings, [])
}
