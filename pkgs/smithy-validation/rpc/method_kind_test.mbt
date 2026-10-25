///|
fn kind_model() -> @smithy.Model raise {
  load(
    (
      #|$version: "2"
      #|namespace kind
      #|use smithy.rpc#jsonRpc
      #|use smithy.rpc#jsonRpcProtocol
      #|use smithy.rpc#method
      #|@jsonRpcProtocol(versions: ["2.0"], peers: [{name: "client"}, {name: "server", accepts: S}])
      #|structure P {}
      #|@jsonRpc(versions: ["1.0", "2.0"])
      #|service S { version: "1", operations: [Exit, Ping, Both] }
      #|@method(name: "exit", params: "either", positional: [], kind: "notification")
      #|operation Exit {}
      #|@method(name: "ping", params: "either", positional: [], kind: "request", nullResult: true)
      #|operation Ping {}
      #|@method(name: "both", params: "either", positional: [], nullResult: true)
      #|operation Both {}
    ),
  )
}

///|
test "method kind checks both protocol versions" {
  let model = kind_model()
  for version in [@rpc.V1_0, @rpc.V2_0] {
    let service = @rpc.PreparedService::prepare(
      model,
      @smithy.ShapeId::parse("kind#S").unwrap(),
      version,
    )
    let marker = if version == @rpc.V2_0 { "\"jsonrpc\":\"2.0\"," } else { "" }
    let notify_id = if version == @rpc.V1_0 { ",\"id\":null" } else { "" }
    let result = service.validate_request(
      "{" + marker + "\"method\":\"exit\",\"params\":[],\"id\":8}",
    )
    assert_eq(result.findings.map(f => f.code.to_string()), [
      "NotificationExpected",
    ])
    let result = service.validate_request(
      "{" + marker + "\"method\":\"ping\",\"params\":[]" + notify_id + "}",
    )
    assert_eq(result.findings.map(f => f.code.to_string()), ["RequestExpected"])
    assert_true(
      service
      .validate_request(
        "{" + marker + "\"method\":\"exit\",\"params\":[]" + notify_id + "}",
      )
      .is_valid(),
    )
    assert_true(
      service
      .validate_request(
        "{" + marker + "\"method\":\"both\",\"params\":[]" + notify_id + "}",
      )
      .is_valid(),
    )
  }
}

///|
test "notification-only calls stay tracked but need no reply" {
  let model = kind_model()
  let protocol = describe(model, "kind#P", @rpc.V2_0)
  let checker = @rpc.TranscriptChecker::new(protocol, completeness=Complete)
  let findings = checker.feed_all([
    entry("client", call(8, "exit")),
    entry("client", call(9, "exit")),
    entry("server", success(9, "{}")),
  ])
  assert_eq(summary_of(findings), [
    "NotificationExpected@0[]", "NotificationExpected@1[]",
  ])
  assert_eq(checker.finish().findings, [])
  assert_eq(checker.finish().outstanding, 0)
}

///|
test "notification-only batch calls have optional replies" {
  let protocol = describe(kind_model(), "kind#P", @rpc.V2_0)
  for replied in [false, true] {
    let checker = @rpc.TranscriptChecker::new(protocol, completeness=Complete)
    let found = checker.feed(
      entry("client", "[" + call(8, "exit") + "," + call(9, "ping") + "]"),
    )
    assert_eq(summary_of(found), ["NotificationExpected@0[]"])
    let replies = if replied { success(8, "{}") + "," } else { "" }
    assert_eq(
      checker.feed(entry("server", "[" + replies + success(9, "null") + "]")),
      [],
    )
    assert_eq(checker.finish().findings, [])
  }
  let checker = @rpc.TranscriptChecker::new(protocol, completeness=Complete)
  checker.feed(entry("client", "[" + call(8, "exit") + "]")) |> ignore
  assert_eq(checker.finish().findings, [])
}
