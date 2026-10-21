///|
fn response_model(
  result~ : String = "resultMember: \"value\"",
  output~ : String = "structure Output { @range(min: -20, max: 20) value: Integer }",
  error_mapping~ : String = "code: 1001, dataMember: \"detail\"",
  extra_error~ : String = "",
) -> @smithy.Model raise {
  let loaded = @rpc.loader()
    .add_idl(
      "responses.smithy",
      "$version: \"2\"\nnamespace reply\nuse smithy.rpc#jsonRpc\nuse smithy.rpc#method\nuse smithy.rpc#rpcError\n" +
      "@jsonRpc(versions: [\"1.0\",\"2.0\"])\nservice Api { version: \"1\", operations: [Op] }\n" +
      "@method(name: \"subtract\", params: \"either\", positional: [\"a\",\"b\"], " +
      result +
      ")\n" +
      "operation Op { input: Input, output: Output, errors: [Problem" +
      (if extra_error == "" { "" } else { ", Other" }) +
      "] }\n" +
      "structure Input { @required a: Integer, @required b: Integer }\n" +
      output +
      "\n" +
      "@error(\"client\")\n@rpcError(" +
      error_mapping +
      ")\nstructure Problem { @required @length(min: 2) detail: String }\n" +
      extra_error,
    )
    .assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  model
}

///|
fn response_service(
  version~ : @rpc.ProtocolVersion = @rpc.V2_0,
) -> @rpc.PreparedService raise {
  @rpc.PreparedService::prepare(
    response_model(),
    @smithy.ShapeId::parse("reply#Api").unwrap(),
    version,
  )
}

///|
fn response_method() -> @rpc.ResponseContext {
  @rpc.Method(@rpc.MethodName::parse("subtract").unwrap())
}

///|
test "contextual results use effective scalar array object and null contracts in both versions" {
  for
    (selector, output, good, bad, path, shape) in [
      (
        "resultMember: \"value\"", "structure Output { @range(min: 2) value: Integer }",
        "19", "1", "/result", "reply#Output$value",
      ),
      (
        "resultMember: \"value\"", "structure Output { @length(min: 2) value: Values }\nlist Values { member: String }",
        "[\"hello\",\"world\"]", "[\"hello\",5]", "/result/1", "reply#Values$member",
      ),
      (
        "resultMember: \"value\"", "structure Output { value: Document }", "null",
        "", "", "",
      ),
      (
        "resultMember: \"value\"", "structure Output { value: Nested }\nstructure Nested { @required count: Integer }",
        "{\"count\":1}", "{\"count\":\"1\"}", "/result/count", "reply#Nested$count",
      ),
      (
        "nullResult: true", "structure Output {}", "null", "{}", "/result", "reply#Op",
      ),
      (
        "nullResult: false", "structure Output { @required value: Integer }", "{\"value\":19}",
        "{}", "/result/value", "reply#Output$value",
      ),
    ] {
    for
      (version, prefix, suffix) in [
        (@rpc.V2_0, "\"jsonrpc\":\"2.0\",", ""),
        (@rpc.V1_0, "", ",\"error\":null"),
      ] {
      let service = @rpc.PreparedService::prepare(
        response_model(result=selector, output~),
        @smithy.ShapeId::parse("reply#Api").unwrap(),
        version,
      )
      let checked = service.validate_response(
        "{" + prefix + "\"result\":" + good + suffix + ",\"id\":1}",
        context=Some(response_method()),
      )
      assert_true(checked.is_valid(), msg=@json.to_json(checked).stringify())
      assert_eq(checked.kind, Some(@rpc.Success))
      assert_eq(checked.scope, @rpc.MethodPayload)
      if bad != "" {
        let checked = service.validate_response(
          "{" + prefix + "\"result\":" + bad + suffix + ",\"id\":1}",
          context=Some(
            @rpc.Operation(@smithy.ShapeId::parse("reply#Op").unwrap()),
          ),
        )
        assert_false(checked.is_valid())
        assert_eq(checked.findings[0].path.pointer(), path)
        assert_eq(checked.findings[0].shape.to_string(), shape)
        assert_eq(
          checked.findings[0].operation.unwrap().to_string(),
          "reply#Op",
        )
      }
    }
  }
}

///|
test "responses require context and explicit envelope-only checks disclose their scope" {
  let service = response_service()
  let text = "{\"jsonrpc\":\"2.0\",\"result\":\"not a number\",\"id\":1,\"method\":\"subtract\"}"
  assert_eq(
    service.validate_response(text).findings[0].code,
    @rpc.MissingContext,
  )
  let checked = service.validate_response(text, context=Some(@rpc.EnvelopeOnly))
  assert_true(checked.is_valid())
  assert_eq(checked.scope, @rpc.Envelope)
  assert_eq(checked.operation, None)
  assert_eq(checked.findings[0].severity, @validation.Advisory)
  assert_true(
    @json.to_json(checked).stringify().contains("\"scope\":\"envelope\""),
  )
  for
    context in [
      @rpc.Method(@rpc.MethodName::parse("missing").unwrap()),
      @rpc.Operation(@smithy.ShapeId::parse("reply#Missing").unwrap()),
    ] {
    assert_eq(
      service.validate_response(text, context=Some(context)).findings[0].code,
      @rpc.InvalidContext,
    )
  }
}

///|
test "versioned response envelopes preserve absence and null conventions" {
  let v2 = response_service()
  for
    (text, code, path) in [
      ("{\"result\":19,\"id\":1}", @rpc.InvalidVersion, "/jsonrpc"),
      (
        "{\"jsonrpc\":2,\"result\":19,\"id\":1}",
        @rpc.InvalidVersion,
        "/jsonrpc",
      ),
      ("{\"jsonrpc\":\"2.0\",\"result\":19}", @rpc.InvalidId, "/id"),
      ("{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":true}", @rpc.InvalidId, "/id"),
      (
        "{\"jsonrpc\":\"2.0\",\"result\":19,\"error\":null,\"id\":1}",
        @rpc.InvalidEnvelope,
        "",
      ),
      ("{\"jsonrpc\":\"2.0\",\"id\":1}", @rpc.InvalidEnvelope, ""),
      (
        "{\"jsonrpc\":\"2.0\",\"error\":null,\"id\":1}",
        @rpc.InvalidError,
        "/error",
      ),
      ("[]", @rpc.UnsupportedMessage, ""),
      ("null", @rpc.InvalidEnvelope, ""),
    ] {
    let checked = v2.validate_response(text, context=Some(response_method()))
    assert_false(checked.is_valid(), msg=text)
    assert_eq(checked.findings[0].code, code, msg=text)
    assert_eq(checked.findings[0].path.pointer(), path)
  }
  let v1 = response_service(version=@rpc.V1_0)
  for
    text in [
      "{\"result\":19,\"id\":1}", "{\"error\":null,\"id\":1}", "{\"result\":19,\"error\":\"failed\",\"id\":1}",
      "{\"jsonrpc\":\"1.0\",\"result\":19,\"error\":null,\"id\":1}",
    ] {
    assert_false(
      v1.validate_response(text, context=Some(response_method())).is_valid(),
      msg=text,
    )
  }
  let legacy = v1.validate_response(
    "{\"result\":null,\"error\":\"failed\",\"id\":1}",
    context=Some(response_method()),
  )
  assert_true(legacy.is_valid())
  assert_eq(legacy.kind, Some(@rpc.LegacyError))
  assert_eq(legacy.findings[0].code, @rpc.LimitedScope)
}

///|
test "original requests correlate exact arbitrary legacy IDs and exact version two IDs" {
  for version in [@rpc.V1_0, @rpc.V2_0] {
    let service = response_service(version~)
    let prefix = if version == @rpc.V2_0 { "\"jsonrpc\":\"2.0\"," } else { "" }
    let suffix = if version == @rpc.V1_0 { ",\"error\":null" } else { "" }
    for
      id in [
        "9007199254740993", "0.10000000000000000001", "1e1000000", "\"call\"", "null",
        "true", "[1,{\"x\":9007199254740993}]", "{\"nested\":[1e1000000]}",
      ] {
      if (version == @rpc.V1_0 && id == "null") ||
        (
          version == @rpc.V2_0 &&
          (id == "true" || id.has_prefix("[") || id.has_prefix("{"))
        ) {
        continue
      }
      let request = "{" +
        prefix +
        "\"method\":\"subtract\",\"params\":[42,23],\"id\":" +
        id +
        "}"
      let checked = service.validate_response(
        "{" + prefix + "\"result\":19" + suffix + ",\"id\":" + id + "}",
        context=Some(@rpc.OriginalRequest(request)),
      )
      assert_true(checked.is_valid(), msg=@json.to_json(checked).stringify())
      assert_eq(checked.scope, @rpc.RequestContext)
      let wrong = service.validate_response(
        "{" + prefix + "\"result\":19" + suffix + ",\"id\":9007199254740992}",
        context=Some(@rpc.OriginalRequest(request)),
      )
      assert_true(wrong.findings.iter().any(f => f.code == @rpc.IdMismatch))
    }
  }
  let service = response_service()
  let checked = service.validate_response(
    "{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":1.0}",
    context=Some(
      @rpc.OriginalRequest(
        "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[42,23],\"id\":1}",
      ),
    ),
  )
  assert_true(checked.is_valid())
}

///|
test "notifications cannot supply a response even for unknown methods" {
  for
    (version, request, response) in [
      (
        @rpc.V2_0,
        "{\"jsonrpc\":\"2.0\",\"method\":\"missing\"}",
        "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32601,\"message\":\"Method not found\"},\"id\":null}",
      ),
      (
        @rpc.V1_0,
        "{\"method\":\"subtract\",\"params\":[42,23],\"id\":null}",
        "{\"result\":19,\"error\":null,\"id\":null}",
      ),
    ] {
    let checked = response_service(version~).validate_response(
      response,
      context=Some(@rpc.OriginalRequest(request)),
    )
    assert_true(
      checked.findings.iter().any(f => f.code == @rpc.UnexpectedResponse),
    )
  }
}

///|
test "protocol errors are separated from modeled application errors and future reserved codes" {
  let service = response_service()
  for
    (code, valid, kind) in [
      ("-32700", true, @rpc.ProtocolError),
      ("-32600", true, @rpc.ProtocolError),
      ("-32601", true, @rpc.ProtocolError),
      ("-32602", true, @rpc.ProtocolError),
      ("-32603", true, @rpc.ProtocolError),
      ("-32099", true, @rpc.ProtocolError),
      ("-32000", true, @rpc.ProtocolError),
      ("-32050.0", true, @rpc.ProtocolError),
      ("-32768", false, @rpc.ProtocolError),
      ("-32001e0", true, @rpc.ProtocolError),
      ("1001", true, @rpc.ApplicationError),
      ("1002", false, @rpc.ApplicationError),
      ("9007199254740993", false, @rpc.ApplicationError),
    ] {
    let checked = service.validate_response(
      "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":" +
      code +
      ",\"message\":\"failure\",\"data\":\"detail\"},\"id\":null}",
      context=Some(response_method()),
    )
    assert_eq(checked.is_valid(), valid, msg=code)
    assert_eq(checked.kind, Some(kind))
  }
  for
    error in [
      "{}", "{\"code\":1.5,\"message\":\"x\"}", "{\"code\":\"1001\",\"message\":\"x\"}",
      "{\"code\":1001,\"message\":null}", "{\"code\":1001}", "[]",
    ] {
    assert_false(
      service
      .validate_response(
        "{\"jsonrpc\":\"2.0\",\"error\":" + error + ",\"id\":1}",
        context=Some(response_method()),
      )
      .is_valid(),
      msg=error,
    )
  }
  for
    (data, code) in [
      ("1", @rpc.Value(@validation.TypeMismatch)),
      ("\"x\"", @rpc.Value(@validation.Length)),
    ] {
    let checked = service.validate_response(
      "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":1001,\"message\":\"failure\",\"data\":" +
      data +
      "},\"id\":1}",
      context=Some(response_method()),
    )
    assert_eq(checked.findings[0].code, code)
    assert_eq(checked.findings[0].path.pointer(), "/error/data")
    assert_eq(checked.findings[0].shape.to_string(), "reply#Problem$detail")
    assert_eq(checked.findings[0].path.steps(), [
      @validation.Field("error", 0),
      @validation.Field("data", 0),
    ])
  }
}

///|
test "application error data selection distinguishes absent null member and structure" {
  for
    (mapping, valid_tail, bad_tail) in [
      ("code: 1001, absentData: true", "", ",\"data\":null"),
      ("code: 1001", ",\"data\":{\"detail\":\"good\"}", ",\"data\":{}"),
      ("code: 1001, dataMember: \"detail\"", ",\"data\":\"good\"", ""),
    ] {
    for version in [@rpc.V1_0, @rpc.V2_0] {
      let service = @rpc.PreparedService::prepare(
        response_model(error_mapping=mapping),
        @smithy.ShapeId::parse("reply#Api").unwrap(),
        version,
      )
      let prefix = if version == @rpc.V2_0 {
        "\"jsonrpc\":\"2.0\","
      } else {
        "\"result\":null,"
      }
      for (tail, valid) in [(valid_tail, true), (bad_tail, false)] {
        let checked = service.validate_response(
          "{" +
          prefix +
          "\"error\":{\"code\":1001,\"message\":\"failure\"" +
          tail +
          "},\"id\":1}",
          context=Some(response_method()),
          legacy_errors=@rpc.CodeMessageData,
        )
        assert_eq(
          checked.is_valid(),
          valid,
          msg=@json.to_json(checked).stringify(),
        )
      }
    }
  }
}

///|
test "original specification responses and single invalid-request contexts" {
  let service = response_service()
  for
    (request, response) in [
      (
        "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[42,23],\"id\":1}",
        "{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":1}",
      ),
      (
        "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[23,42],\"id\":2}",
        "{\"jsonrpc\":\"2.0\",\"result\":-19,\"id\":2}",
      ),
      (
        "{\"jsonrpc\":\"2.0\",\"method\":\"foobar\",\"id\":\"1\"}", "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32601,\"message\":\"Method not found\"},\"id\":\"1\"}",
      ),
      (
        "{\"jsonrpc\":\"2.0\",\"method\":\"foobar, \"params\": \"bar\", \"baz]",
        "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32700,\"message\":\"Parse error\"},\"id\":null}",
      ),
      (
        "{\"jsonrpc\":\"2.0\",\"method\":1,\"params\":\"bar\"}", "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"},\"id\":null}",
      ),
    ] {
    let checked = service.validate_response(
      response,
      context=Some(@rpc.OriginalRequest(request)),
    )
    assert_true(checked.is_valid(), msg=@json.to_json(checked).stringify())
    let wrong = service.validate_response(
      "{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":null}",
      context=Some(@rpc.OriginalRequest(request)),
    )
    assert_false(wrong.is_valid())
  }
  let legacy = @rpc.loader()
    .add_idl(
      "legacy.smithy",
      "$version: \"2\"\nnamespace legacy\nuse smithy.rpc#jsonRpc\nuse smithy.rpc#method\n" +
      "@jsonRpc(versions: [\"1.0\"])\nservice Api { version: \"1\", operations: [Echo, Post] }\n" +
      "@method(name: \"echo\", params: \"positional\", positional: [\"message\"], resultMember: \"message\")\noperation Echo { input: Input, output: EchoOutput }\n" +
      "@method(name: \"postMessage\", params: \"positional\", positional: [\"message\"], resultMember: \"value\")\noperation Post { input: Input, output: PostOutput }\n" +
      "structure Input { @required message: String }\nstructure EchoOutput { message: String }\nstructure PostOutput { value: Integer }\n",
    )
    .assemble()
  let service = @rpc.PreparedService::prepare(
    legacy.model.unwrap(),
    @smithy.ShapeId::parse("legacy#Api").unwrap(),
    @rpc.V1_0,
  )
  for
    (method_, message, id, result) in [
      ("echo", "Hello JSON-RPC", 1, "\"Hello JSON-RPC\""),
      ("postMessage", "Hello all!", 99, "1"),
      ("postMessage", "I have a question:", 101, "1"),
    ] {
    let request = "{\"method\":\"" +
      method_ +
      "\",\"params\":[\"" +
      message +
      "\"],\"id\":" +
      id.to_string() +
      "}"
    let checked = service.validate_response(
      "{\"result\":" + result + ",\"error\":null,\"id\":" + id.to_string() + "}",
      context=Some(@rpc.OriginalRequest(request)),
    )
    assert_true(checked.is_valid(), msg=@json.to_json(checked).stringify())
  }
}

///|
test "response parsing limits and isolated context failures remain incomplete" {
  let service = response_service()
  for
    (text, code) in [
      ("{\"a\":truX}", @rpc.InvalidJson),
      ("{\"a\":1,\"\\u0061\":2}", @rpc.DuplicateJsonKey),
    ] {
    let checked = service.validate_response(
      text,
      context=Some(response_method()),
    )
    assert_false(checked.complete)
    assert_eq(checked.findings[0].code, code)
    if code == @rpc.InvalidJson {
      assert_eq(checked.findings[0].offset, Some(8))
    }
  }
  let checked = service.validate_response(
    "{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":1}",
    context=Some(@rpc.OriginalRequest("{\"a\":1,\"a\":2}")),
  )
  assert_false(checked.complete)
  assert_false(checked.is_valid())
  let limited = @rpc.PreparedService::prepare(
    response_model(),
    @smithy.ShapeId::parse("reply#Api").unwrap(),
    @rpc.V2_0,
    config=@validation.Config::new(limits=@validation.Limits::new(findings=1)),
  )
  let checked = limited.validate_response(
    "{\"result\":false}",
    context=Some(response_method()),
  )
  assert_false(checked.complete)
  assert_eq(checked.findings.length(), 1)
  assert_eq(checked.findings[0].code, @rpc.Value(@validation.LimitExceeded))
  let cycle : Map[String, Json] = Map([])
  let value = Json::object(cycle)
  cycle["id"] = value
  assert_false(
    service.validate_response_json(value, context=Some(@rpc.EnvelopeOnly)).complete,
  )
}

///|
test "error mappings reject reserved duplicate missing and conflicting selectors" {
  for
    mapping in [
      "code: -32601", "code: -32768", "code: -32000", "code: 1001, dataMember: \"missing\"",
      "code: 1001, dataMember: \"detail\", absentData: true",
    ] {
    let mut rejected = false
    ignore(
      @rpc.PreparedService::prepare(
        response_model(error_mapping=mapping),
        @smithy.ShapeId::parse("reply#Api").unwrap(),
        @rpc.V2_0,
      ),
    ) catch {
      @rpc.InvalidContract(_, _) => rejected = true
      e => fail(e.to_string())
    }
    assert_true(rejected, msg=mapping)
  }
  let extra = "@error(\"client\")\n@rpcError(code: 1001)\nstructure Other {}"
  let mut rejected = false
  ignore(
    @rpc.PreparedService::prepare(
      response_model(extra_error=extra),
      @smithy.ShapeId::parse("reply#Api").unwrap(),
      @rpc.V2_0,
    ),
  ) catch {
    @rpc.InvalidContract(_, _) => rejected = true
    e => fail(e.to_string())
  }
  assert_true(rejected)
}

///|
test "optional selected error data may be absent and nullable document data stays present" {
  let model = response_model()
  let member_id = @smithy.ShapeId::parse("reply#Problem$detail").unwrap()
  let member_ = model.shapes.get(member_id).unwrap()
  member_.traits.remove(@smithy.ShapeId::parse("smithy.api#required").unwrap())
  |> ignore
  let service = @rpc.PreparedService::prepare(
    model,
    @smithy.ShapeId::parse("reply#Api").unwrap(),
    @rpc.V2_0,
  )
  assert_true(
    service
    .validate_response(
      "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":1001,\"message\":\"failure\"},\"id\":1}",
      context=Some(response_method()),
    )
    .is_valid(),
  )
  assert_false(
    service
    .validate_response(
      "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":1001,\"message\":\"failure\",\"data\":null},\"id\":1}",
      context=Some(response_method()),
    )
    .is_valid(),
  )
  let nullable = response_model()
  let member_ = nullable.shapes.get(member_id).unwrap()
  member_.traits.remove(@smithy.ShapeId::parse("smithy.api#length").unwrap())
  |> ignore
  nullable.shapes[member_id] = {
    ..member_,
    body: @smithy.Member(
      target=@smithy.ShapeId::parse("smithy.api#Document").unwrap(),
    ),
  }
  let service = @rpc.PreparedService::prepare(
    nullable,
    @smithy.ShapeId::parse("reply#Api").unwrap(),
    @rpc.V2_0,
  )
  assert_true(
    service
    .validate_response(
      "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":1001,\"message\":\"failure\",\"data\":null},\"id\":1}",
      context=Some(response_method()),
    )
    .is_valid(),
  )
  assert_false(
    service
    .validate_response(
      "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":1001,\"message\":\"failure\"},\"id\":1}",
      context=Some(response_method()),
    )
    .is_valid(),
  )
}

///|
test "original context separates envelope parameter types from modeled parameter constraints" {
  let service = response_service()
  for
    (params, expected) in [
      ("\"invalid\"", "-32600"),
      ("[42,\"bad\"]", "-32602"),
      ("[]", "-32602"),
    ] {
    let request = "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":" +
      params +
      ",\"id\":1}"
    let checked = service.validate_response(
      "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":" +
      expected +
      ",\"message\":\"failed\"},\"id\":1}",
      context=Some(@rpc.OriginalRequest(request)),
    )
    assert_true(checked.is_valid(), msg=@json.to_json(checked).stringify())
  }
  let checked = service.validate_response(
    "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32600,\"message\":\"failed\"},\"id\":null}",
    context=Some(@rpc.OriginalRequest("[]")),
  )
  assert_false(checked.is_valid())
  assert_eq(checked.findings[0].code, @rpc.UnsupportedMessage)
}

///|
test "prepared responses snapshot results and service-level error mappings" {
  let model = response_model()
  let api_id = @smithy.ShapeId::parse("reply#Api").unwrap()
  let api = model.shapes.get(api_id).unwrap()
  let op_id = @smithy.ShapeId::parse("reply#Op").unwrap()
  let op = model.shapes.get(op_id).unwrap()
  guard api.body
    is @smithy.Service(version~, operations~, resources~, rename~, ..) &&
    op.body is @smithy.Operation(input~, output~, errors~) else {
    fail("Expected service and operation")
  }
  model.shapes[api_id] = {
    ..api,
    body: @smithy.Service(version~, operations~, resources~, rename~, errors~),
  }
  model.shapes[op_id] = {
    ..op,
    body: @smithy.Operation(input~, output~, errors=[]),
  }
  let service = @rpc.PreparedService::prepare(model, api_id, @rpc.V2_0)
  model.shapes.clear()
  assert_true(
    service
    .validate_response(
      "{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":1}",
      context=Some(response_method()),
    )
    .is_valid(),
  )
  assert_false(
    service
    .validate_response(
      "{\"jsonrpc\":\"2.0\",\"result\":21,\"id\":1}",
      context=Some(response_method()),
    )
    .is_valid(),
  )
  assert_true(
    service
    .validate_response(
      "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":1001,\"message\":\"failed\",\"data\":\"detail\"},\"id\":1}",
      context=Some(response_method()),
    )
    .is_valid(),
  )
  assert_false(
    service
    .validate_response(
      "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":1001,\"message\":\"failed\",\"data\":1},\"id\":1}",
      context=Some(response_method()),
    )
    .is_valid(),
  )
}

///|
test "error code boundary accepts exact mathematical integers without machine bounds" {
  for number in ["1.0", "0.1e1", "9007199254740993", "1e1000000", "-0e-1000000"] {
    assert_true(
      @rpc.ErrorCode::from_number(@smithy.NodeNumber::parse(number).unwrap())
      is Some(_),
    )
  }
  assert_eq(
    @rpc.ErrorCode::from_number(
      @smithy.NodeNumber::parse("1e-1000000").unwrap(),
    ),
    None,
  )
}
