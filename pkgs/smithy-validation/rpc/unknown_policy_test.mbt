///|
test "service policy applies to params results and nested structures" {
  let source =
    #|$version: "2"
    #|namespace policy
    #|use smithy.rpc#jsonRpc
    #|use smithy.rpc#method
    #|use smithy.rpc#unknownMembers
    #|@unknownMembers("ignore")
    #|@jsonRpc(versions: ["2.0"])
    #|service Api { version: "1", operations: [Run] }
    #|@method(name: "run", params: "named")
    #|operation Run { input: Input, output: Output }
    #|structure Input { value: Nested }
    #|structure Nested { known: String }
    #|@unknownMembers("reject")
    #|structure Output { known: String }
  let loaded = @rpc.loader().add_idl("policy.smithy", source).assemble()
  let prepared = @rpc.PreparedService::prepare(
    loaded.model.unwrap(),
    @smithy.ShapeId::parse("policy#Api").unwrap(),
    @rpc.V2_0,
  )
  assert_true(
    prepared
    .validate_request(
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"run\",\"params\":{\"extra\":1,\"value\":{\"extra\":2}}}",
    )
    .is_valid(),
  )
  let context = @rpc.Method(@rpc.MethodName::parse("run").unwrap())
  let result = prepared.validate_response(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"extra\":1}}",
    context=Some(context),
  )
  assert_false(result.is_valid())
}
