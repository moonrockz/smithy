///|
test "contract snapshot arrays do not change prepared checks" {
  let model = contract_model(
    "name: \"op\", params: \"either\", positional: [\"a\",\"b\"]",
  )
  let prepared = @rpc.PreparedService::prepare(
    model,
    @smithy.ShapeId::parse("test#Api").unwrap(),
    @rpc.V2_0,
  )
  let methods = prepared.contracts()
  methods[0].positional.clear()
  methods.clear()
  let values = prepared.value_contracts()
  values[0].members.clear()
  values.clear()
  assert_eq(prepared.contracts()[0].positional.length(), 2)
  assert_true(
    prepared
    .validate_request(
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"op\",\"params\":[1,2]}",
    )
    .is_valid(),
  )
  assert_eq(prepared.value_contracts()[0].members.length(), 2)
}

///|
test "session snapshot arrays do not change protocol rules" {
  let prepared = describe(refusal_model(), "refusal#P", @rpc.V2_0)
  let contract = prepared.session_contract().unwrap()
  contract.states.clear()
  contract.capabilities.clear()
  contract.methods[0].allowed.unwrap().clear()
  contract.methods.clear()
  contract.refusals.clear()
  let fresh = prepared.session_contract().unwrap()
  assert_eq(fresh.states.map(s => s.to_string()), ["starting", "ready"])
  assert_eq(fresh.methods[0].allowed.unwrap().map(s => s.to_string()), [
    "starting",
  ])
  assert_eq(fresh.refusals[0].code.to_string(), "1007")
  let checker = @rpc.TranscriptChecker::new(prepared)
  let found = checker.feed(entry("a", call(1, "work")))
  assert_eq(found.map(f => f.code.to_string()), [
    "StateViolation", "CapabilityNotAdvertised",
  ])
}
