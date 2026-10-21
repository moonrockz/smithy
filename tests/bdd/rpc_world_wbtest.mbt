///|
struct RpcWorld {
  mut prepared : @rpc.PreparedService?
  mut result : @rpc.RequestResult?
  mut batch_text : String?
  mut batch : @rpc.RequestBatchResult?
  mut replies : @rpc.ResponseBatchResult?
}

///|
fn RpcWorld::new() -> RpcWorld {
  {
    prepared: None,
    result: None,
    batch_text: None,
    batch: None,
    replies: None,
  }
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
  setup.when1("I validate the RPC request batch {string}", fn(
    message : String,
  ) {
    self.batch_text = Some(message)
    self.batch = Some(self.prepared.unwrap().validate_request_batch(message))
  })
  setup.when1("I validate its response batch {string}", fn(message : String) {
    self.replies = Some(
      self.prepared
      .unwrap()
      .validate_response_batch(
        Some(message),
        context=Some(@rpc.OriginalBatch(self.batch_text.unwrap())),
      ),
    )
  })
  setup.when0("I validate its absent batch response", fn() {
    self.replies = Some(
      self.prepared
      .unwrap()
      .validate_response_batch(
        None,
        context=Some(@rpc.OriginalBatch(self.batch_text.unwrap())),
      ),
    )
  })
  setup.then2("the batch finding is {string} at {string}", fn(
    code : String,
    path : String,
  ) raise {
    let result = self.batch.unwrap()
    assert_false(result.is_valid())
    assert_true(
      result.findings
      .iter()
      .any(f => f.code.to_string() == code && f.path.pointer() == path),
    )
  })
  setup.then0("the response batch is valid", fn() raise {
    assert_true(self.replies.unwrap().is_valid())
  })
  setup.then0("the response batch is invalid", fn() raise {
    assert_false(self.replies.unwrap().is_valid())
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
test "original specification batch fixtures validate through the library" {
  let source = @xfs.read_file_to_string("../examples/json-rpc/batches.smithy")
  let loaded = @rpc.loader().add_idl("batches.smithy", source).assemble()
  let service = @rpc.PreparedService::prepare(
    loaded.model.unwrap(),
    @smithy.ShapeId::parse("batch#Api").unwrap(),
    @rpc.V2_0,
  )
  let mixed = @xfs.read_file_to_string("../examples/json-rpc/batch-mixed.json")
  let replies = @xfs.read_file_to_string(
    "../examples/json-rpc/batch-replies.json",
  )
  let notifications = @xfs.read_file_to_string(
    "../examples/json-rpc/batch-notifications.json",
  )
  assert_false(service.validate_request_batch(mixed).is_valid())
  let result = service.validate_response_batch(
    Some(replies),
    context=Some(@rpc.OriginalBatch(mixed)),
  )
  assert_true(result.is_valid())
  assert_eq(result.entries.map(e => e.request_index), [
    Some(5),
    Some(4),
    Some(2),
    Some(3),
    Some(0),
  ])
  assert_true(service.validate_request_batch(notifications).is_valid())
  assert_true(
    service
    .validate_response_batch(
      None,
      context=Some(@rpc.OriginalBatch(notifications)),
    )
    .is_valid(),
  )
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
