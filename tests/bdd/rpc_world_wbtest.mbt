///|
struct RpcWorld {
  mut prepared : @rpc.PreparedService?
  mut result : @rpc.RequestResult?
}

///|
fn RpcWorld::new() -> RpcWorld {
  { prepared: None, result: None, }
}

///|
impl @moonspec.World for RpcWorld with fn configure(self, setup) {
  setup.given1("the calculator API prepared for JSON-RPC {string}", fn(
    version : String,
  ) raise {
    let source = @xfs.read_file_to_string(
      "../examples/json-rpc/calculator.smithy",
    )
    let loaded = @rpc.loader().add_idl("calculator.smithy", source).assemble()
    self.prepared = Some(
      @rpc.PreparedService::prepare(
        loaded.model.unwrap(),
        @smithy.ShapeId::parse("example#Calculator").unwrap(),
        @rpc.ProtocolVersion::parse(version).unwrap(),
      ),
    )
  })
  setup.when1("I validate the RPC message {string}", fn(message : String) {
    self.result = Some(self.prepared.unwrap().validate_request(message))
  })
  setup.then1("the RPC message is a valid {string}", fn(kind : String) raise {
    let result = self.result.unwrap()
    assert_true(result.is_valid())
    assert_eq(
      result.kind,
      Some(if kind == "notification" { @rpc.Notification } else { @rpc.Call }),
    )
  })
  setup.then3("the RPC finding is {string} at {string} on {string}", fn(
    code : String,
    path : String,
    shape : String,
  ) raise {
    let result = self.result.unwrap()
    assert_false(result.is_valid())
    assert_eq(result.findings[0].code.to_string(), code)
    assert_eq(result.findings[0].path.pointer(), path)
    assert_eq(result.findings[0].shape.to_string(), shape)
  })
  setup.then0("the RPC message has only an ID advisory", fn() raise {
    let result = self.result.unwrap()
    assert_true(result.is_valid())
    assert_eq(result.findings.length(), 1)
    assert_eq(result.findings[0].severity, @validation.Advisory)
  })
}

///|
async test "JSON-RPC request and notification acceptance" {
  @moonspec.run_or_fail(
    RpcWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/json-rpc.feature"),
    ]),
  )
  |> ignore
}
