///|
test "exported method contracts retain wire order selectors and detached arrays" {
  let model = response_model()
  let service = @rpc.PreparedService::prepare(
    model,
    @smithy.ShapeId::parse("reply#Api").unwrap(),
    @rpc.V2_0,
  )
  let methods = service.contracts()
  assert_eq(methods.length(), 1)
  let method_ = methods[0]
  assert_eq(method_.name.to_string(), "subtract")
  assert_eq(method_.operation.to_string(), "reply#Op")
  assert_eq(method_.input.to_string(), "reply#Input")
  assert_eq(method_.mode, @rpc.Either)
  assert_eq(method_.positional.map(id => id.to_string()), [
    "reply#Input$a", "reply#Input$b",
  ])
  assert_eq(
    method_.result,
    @rpc.OutputMember(@smithy.ShapeId::parse("reply#Output$value").unwrap()),
  )
  assert_eq(method_.errors[0].shape.to_string(), "reply#Problem")
  assert_eq(method_.errors[0].code.to_string(), "1001")
  assert_eq(
    method_.errors[0].data,
    Some(@smithy.ShapeId::parse("reply#Problem$detail").unwrap()),
  )
  assert_true(method_.errors[0].data_required)
  method_.positional.clear()
  method_.errors.clear()
  methods.clear()
  assert_eq(service.contracts()[0].positional.length(), 2)
  assert_eq(service.contracts()[0].errors.length(), 1)
  assert_true(
    service
    .validate_request(
      "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[3,2]}",
    )
    .is_valid(),
  )
  assert_true(
    service
    .validate_response(
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":1001,\"message\":\"bad\",\"data\":\"ok\"}}",
      context=Some(@rpc.Method(method_.name)),
    )
    .is_valid(),
  )
}
