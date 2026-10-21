///|
test "request batches retain original positions and validate each modeled input" {
  let service = response_service()
  let checked = service.validate_request_batch(
    "[{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[42,23],\"id\":1},1,{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[42,\"bad\"]}]",
  )
  assert_false(checked.is_valid())
  assert_true(checked.complete)
  assert_eq(checked.entries.length(), 3)
  assert_eq(checked.entries[2].index, 2)
  assert_eq(checked.entries[2].result.kind, Some(@rpc.Notification))
  assert_true(checked.findings.iter().any(f => f.path.pointer() == "/1"))
  assert_true(
    checked.findings
    .iter()
    .any(f => {
      f.path.pointer() == "/2/params/1" &&
      f.shape.to_string() == "reply#Input$b"
    }),
  )
}

///|
test "response batches associate reordered exact IDs and check the selected result" {
  let service = response_service()
  let original = "[{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[42,23],\"id\":9007199254740993},{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[23,42],\"id\":9007199254740992}]"
  let result = service.validate_response_batch(
    Some(
      "[{\"jsonrpc\":\"2.0\",\"result\":-19,\"id\":9007199254740992},{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":9007199254740993}]",
    ),
    context=Some(@rpc.OriginalBatch(original)),
  )
  assert_true(result.is_valid(), msg=@json.to_json(result).stringify())
  assert_eq(result.entries[0].request_index, Some(1))
  assert_eq(result.entries[1].request_index, Some(0))
}

///|
test "invalid whole batches require one contextual protocol error object" {
  let service = response_service()
  for (request, code) in [("[", "-32700"), ("[]", "-32600"), ("1", "-32600")] {
    assert_false(service.validate_request_batch(request).is_valid())
    let reply = "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":" +
      code +
      ",\"message\":\"error\"},\"id\":null}"
    assert_true(
      service
      .validate_response_batch(
        Some(reply),
        context=Some(@rpc.OriginalBatch(request)),
      )
      .is_valid(),
    )
    assert_false(
      service
      .validate_response_batch(
        Some("[" + reply + "]"),
        context=Some(@rpc.OriginalBatch(request)),
      )
      .is_valid(),
    )
    assert_false(
      service
      .validate_response_batch(None, context=Some(@rpc.OriginalBatch(request)))
      .is_valid(),
    )
  }
}

///|
test "invalid batch elements each receive errors including nested arrays" {
  let service = response_service()
  let reply = "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"},\"id\":null}"
  for
    (request, responses) in [
      ("[1]", "[" + reply + "]"),
      ("[1,2,3]", "[" + reply + "," + reply + "," + reply + "]"),
      ("[[],null,true]", "[" + reply + "," + reply + "," + reply + "]"),
    ] {
    let result = service.validate_response_batch(
      Some(responses),
      context=Some(@rpc.OriginalBatch(request)),
    )
    assert_true(result.is_valid(), msg=@json.to_json(result).stringify())
  }
  assert_false(
    service
    .validate_response_batch(
      Some("[" + reply + "]"),
      context=Some(@rpc.OriginalBatch("[1,2,3]")),
    )
    .is_valid(),
  )
}

///|
test "notification batches accept silence and forbid empty or unsolicited replies" {
  let service = response_service()
  let request = "[{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[1,2]},{\"jsonrpc\":\"2.0\",\"method\":\"missing\"}]"
  assert_true(
    service
    .validate_response_batch(None, context=Some(@rpc.OriginalBatch(request)))
    .is_valid(),
  )
  for response in ["[]", "[{\"jsonrpc\":\"2.0\",\"result\":null,\"id\":null}]"] {
    assert_false(
      service
      .validate_response_batch(
        Some(response),
        context=Some(@rpc.OriginalBatch(request)),
      )
      .is_valid(),
    )
  }
  assert_false(service.validate_response_batch(None).is_valid())
}

///|
test "batch duplicate IDs are advisory for requests and ambiguous for correlation" {
  let service = response_service()
  let request = "[{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[1,2],\"id\":1},{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[1,2],\"id\":1.0}]"
  let checked = service.validate_request_batch(request)
  assert_true(checked.is_valid())
  assert_true(
    checked.findings
    .iter()
    .any(f => {
      f.code == @rpc.AmbiguousId &&
      f.severity == @validation.Advisory &&
      f.path.pointer() == "/1/id"
    }),
  )
  let result = service.validate_response_batch(
    Some("[{\"jsonrpc\":\"2.0\",\"result\":-1,\"id\":1}]"),
    context=Some(@rpc.OriginalBatch(request)),
  )
  assert_false(result.is_valid())
  assert_true(result.findings.iter().any(f => f.code == @rpc.AmbiguousId))
}

///|
test "batch matching preserves exact numeric identity without expanding exponents" {
  let service = response_service()
  for
    (id, reply_id) in [
      ("1.0", "1e0"),
      ("-0.0", "0e10000000"),
      ("1e100000000", "10e99999999"),
      ("0.10000000000000000001", "0.100000000000000000010"),
      ("null", "null"),
      ("\"1\"", "\"1\""),
    ] {
    let request = "[{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[1,2],\"id\":" +
      id +
      "}]"
    let result = service.validate_response_batch(
      Some("[{\"jsonrpc\":\"2.0\",\"result\":-1,\"id\":" + reply_id + "}]"),
      context=Some(@rpc.OriginalBatch(request)),
    )
    assert_true(result.is_valid(), msg=@json.to_json(result).stringify())
  }
}

///|
test "batch responses reject duplicates missing calls and wrong payload paths" {
  let service = response_service()
  let request = "[{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[1,2],\"id\":1}]"
  let reply = "{\"jsonrpc\":\"2.0\",\"result\":-1,\"id\":1}"
  for
    (response, code, pointer) in [
      (Some("[" + reply + "," + reply + "]"), @rpc.DuplicateResponse, "/1/id"),
      (None, @rpc.MissingResponse, ""),
      (
        Some("[{\"jsonrpc\":\"2.0\",\"result\":\"bad\",\"id\":1}]"),
        @rpc.Value(@validation.TypeMismatch),
        "/0/result",
      ),
      (
        Some("[{\"jsonrpc\":\"2.0\",\"result\":-1,\"id\":2}]"),
        @rpc.UnexpectedResponse,
        "/0/id",
      ),
    ] {
    let result = service.validate_response_batch(
      response,
      context=Some(@rpc.OriginalBatch(request)),
    )
    assert_false(result.is_valid())
    assert_true(
      result.findings
      .iter()
      .any(f => f.code == code && f.path.pointer() == pointer),
      msg=@json.to_json(result).stringify(),
    )
  }
}

///|
test "batch APIs bound whole documents and combined findings" {
  let limits = @validation.Limits::new(work=15)
  let service = @rpc.PreparedService::prepare(
    response_model(),
    @smithy.ShapeId::parse("reply#Api").unwrap(),
    @rpc.V2_0,
    config=@validation.Config::new(limits~),
  )
  let call = "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[1,2],\"id\":1}"
  assert_true(service.validate_request(call).complete)
  assert_false(
    service.validate_request_batch("[" + call + "," + call + "," + call + "]").complete,
  )
  let service = @rpc.PreparedService::prepare(
    response_model(),
    @smithy.ShapeId::parse("reply#Api").unwrap(),
    @rpc.V2_0,
    config=@validation.Config::new(limits=@validation.Limits::new(findings=3)),
  )
  let result = service.validate_request_batch("[1,2,3,4,5]")
  assert_false(result.complete)
  assert_eq(result.findings.length(), 3)
  assert_eq(result.findings[2].code, @rpc.Value(@validation.LimitExceeded))
  assert_true(result.entries.length() < 5)
  let context = "[{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"id\":1,\"id\":2}]"
  let reply = "[{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32700,\"message\":\"error\"},\"id\":null}]"
  let result = service.validate_response_batch(
    Some(reply),
    context=Some(@rpc.OriginalBatch(context)),
  )
  assert_false(result.is_valid())
  assert_false(result.complete)
  assert_true(result.findings.iter().any(f => f.code == @rpc.InvalidContext))
}

///|
test "legacy batches are explicitly unsupported and JSON APIs retain limited scope" {
  let legacy = response_service(version=@rpc.V1_0)
  assert_eq(
    legacy.validate_request_batch("[]").findings[0].code,
    @rpc.UnsupportedMessage,
  )
  assert_eq(
    legacy.validate_response_batch(None).findings[0].code,
    @rpc.UnsupportedMessage,
  )
  let service = response_service()
  assert_true(
    service
    .validate_request_batch_json(
      @json.parse(
        "[{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[1,2]}]",
      ),
    )
    .is_valid(),
  )
  let result = service.validate_response_batch_json(
    Some(@json.parse("[{\"jsonrpc\":\"2.0\",\"result\":{},\"id\":1}]")),
    context=Some(@rpc.BatchEnvelopeOnly),
  )
  assert_true(result.is_valid())
  assert_eq(result.scope, @rpc.Envelope)
  assert_eq(result.findings[0].code, @rpc.LimitedScope)
  assert_false(
    service
    .validate_response_batch(Some("[]"), context=Some(@rpc.BatchEnvelopeOnly))
    .is_valid(),
  )
}

///|
test "batch contexts validate arbitrary result values and modeled errors" {
  let service = @rpc.PreparedService::prepare(
    response_model(output="structure Output { value: Document }"),
    @smithy.ShapeId::parse("reply#Api").unwrap(),
    @rpc.V2_0,
  )
  let context = @rpc.OriginalBatch(
    "[{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[1,2],\"id\":1}]",
  )
  for
    value in [
      "null", "true", "42", "\"hello\"", "[\"hello\",5]", "{\"count\":1}",
    ] {
    let result = service.validate_response_batch(
      Some("[{\"jsonrpc\":\"2.0\",\"result\":" + value + ",\"id\":1}]"),
      context=Some(context),
    )
    assert_true(result.is_valid(), msg=value)
  }
  let result = service.validate_response_batch(
    Some(
      "[{\"jsonrpc\":\"2.0\",\"error\":{\"code\":1001,\"message\":\"bad\",\"data\":1},\"id\":1}]",
    ),
    context=Some(context),
  )
  assert_false(result.is_valid())
  assert_eq(result.findings[0].path.pointer(), "/0/error/data")
  assert_eq(result.findings[0].shape.to_string(), "reply#Problem$detail")
}

///|
test "batch invalid null IDs coexist with explicit-null calls in either response order" {
  let service = response_service()
  let context = @rpc.OriginalBatch(
    "[1,{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[1,2],\"id\":null}]",
  )
  let success = "{\"jsonrpc\":\"2.0\",\"result\":-1,\"id\":null}"
  let error = "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32600,\"message\":\"bad\"},\"id\":null}"
  for responses in [success + "," + error, error + "," + success] {
    assert_true(
      service
      .validate_response_batch(
        Some("[" + responses + "]"),
        context=Some(context),
      )
      .is_valid(),
    )
  }
}

///|
test "batch response parser and whole document bounds cannot be bypassed" {
  let service = response_service()
  for
    (response, code) in [
      ("[", @rpc.InvalidJson),
      ("[{\"id\":1,\"id\":2}]", @rpc.DuplicateJsonKey),
    ] {
    let result = service.validate_response_batch(
      Some(response),
      context=Some(@rpc.BatchEnvelopeOnly),
    )
    assert_false(result.is_valid())
    assert_false(result.complete)
    assert_eq(result.findings[0].code, code)
  }
  let service = @rpc.PreparedService::prepare(
    response_model(),
    @smithy.ShapeId::parse("reply#Api").unwrap(),
    @rpc.V2_0,
    config=@validation.Config::new(limits=@validation.Limits::new(work=10)),
  )
  let result = service.validate_response_batch(
    Some(
      "[{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":1},{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":2},{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":3}]",
    ),
    context=Some(@rpc.BatchEnvelopeOnly),
  )
  assert_false(result.complete)
  assert_false(result.is_valid())
}

///|
test "batch payload-only contexts declare their scope and validate every result" {
  let service = response_service()
  for
    context in [
      @rpc.BatchMethod(@rpc.MethodName::parse("subtract").unwrap()),
      @rpc.BatchOperation(@smithy.ShapeId::parse("reply#Op").unwrap()),
    ] {
    let result = service.validate_response_batch(
      Some(
        "[{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":1},{\"jsonrpc\":\"2.0\",\"result\":\"bad\",\"id\":2}]",
      ),
      context=Some(context),
    )
    assert_false(result.is_valid())
    assert_eq(result.scope, @rpc.MethodPayload)
    assert_eq(result.findings[0].path.pointer(), "/1/result")
    assert_eq(result.findings[0].shape.to_string(), "reply#Output$value")
  }
  let result = service.validate_response_batch(
    Some("[{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":1}]"),
  )
  assert_false(result.is_valid())
  assert_eq(result.findings[0].code, @rpc.MissingContext)
}

///|
test "batch contextual parameter errors coexist with notification omissions" {
  let service = response_service()
  let original = "[{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[1,\"bad\"],\"id\":1},{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[1,\"bad\"]}]"
  let result = service.validate_response_batch(
    Some(
      "[{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32602,\"message\":\"Invalid params\"},\"id\":1}]",
    ),
    context=Some(@rpc.OriginalBatch(original)),
  )
  assert_true(result.is_valid())
  let result = service.validate_response_batch(
    Some("[{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":1}]"),
    context=Some(@rpc.OriginalBatch(original)),
  )
  assert_false(result.is_valid())
  assert_true(result.findings.iter().any(f => f.code == @rpc.InvalidContext))
}
