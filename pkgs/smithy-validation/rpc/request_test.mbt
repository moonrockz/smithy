///|
fn model() -> @smithy.Model raise {
  let source =
    #|$version: "2"
    #|namespace example
    #|use smithy.rpc#jsonRpc
    #|use smithy.rpc#method
    #|@jsonRpc(versions: ["1.0", "2.0"])
    #|service Calculator { version: "1", operations: [Subtract, Ping] }
    #|@method(name: "subtract", params: "either", positional: ["minuend", "subtrahend"], resultMember: "value")
    #|operation Subtract { input: Input, output: Output }
    #|structure Input {
    #| @required @range(min: 1) minuend: Integer
    #| subtrahend: Integer
    #|}
    #|structure Output { value: Integer }
    #|@method(name: "ping", params: "either", positional: [], nullResult: true)
    #|operation Ping {}
    #|
  let loaded = @rpc.loader().add_idl("api.smithy", source).assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  model
}

///|
test "notification parameter failures are checked in both versions" {
  for
    (version, message) in [
      (
        @rpc.V1_0,
        "{\"method\":\"subtract\",\"params\":[42,\"bad\"],\"id\":null}",
      ),
      (
        @rpc.V2_0,
        "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[42,\"bad\"]}",
      ),
    ] {
    let result = prepared(version).validate_request(message)
    assert_false(result.is_valid())
    assert_eq(result.kind, Some(@rpc.Notification))
    assert_eq(result.findings[0].code.to_string(), "TypeMismatch")
    assert_eq(result.findings[0].path.pointer(), "/params/1")
  }
}

///|
test "combined findings stay bounded and cyclic in-memory IDs do not recurse" {
  let service = @rpc.PreparedService::prepare(
    model(),
    @smithy.ShapeId::parse("example#Calculator").unwrap(),
    @rpc.V2_0,
    config=@validation.Config::new(limits=@validation.Limits::new(findings=1)),
  )
  let result = service.validate_request(
    "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[0,\"bad\"],\"id\":null}",
  )
  assert_false(result.is_valid())
  assert_false(result.complete)
  assert_eq(result.findings.length(), 1)
  assert_eq(result.findings[0].code, @rpc.Value(@validation.LimitExceeded))
  let cycle : Map[String, Json] = Map([])
  let value = Json::object(cycle)
  cycle["id"] = value
  cycle["method"] = Json::string("ping")
  let result = prepared(@rpc.V1_0).validate_json(value)
  assert_false(result.is_valid())
  assert_false(result.complete)
}

///|
test "integer ID advisories compare exact mathematical values" {
  let service = prepared(@rpc.V2_0)
  for raw in ["1.0", "0.1e1", "-0e-1000000", "1e1000000"] {
    let result = service.validate_request(
      "{\"jsonrpc\":\"2.0\",\"method\":\"ping\",\"id\":" + raw + "}",
    )
    assert_true(result.is_valid())
    assert_eq(result.findings.length(), 0, msg=raw)
  }
  let result = service.validate_request(
    "{\"jsonrpc\":\"2.0\",\"method\":\"ping\",\"id\":1e-1000000}",
  )
  assert_true(result.is_valid())
  assert_eq(result.findings[0].severity, @validation.Advisory)
}

///|
fn prepared(version : @rpc.ProtocolVersion) -> @rpc.PreparedService raise {
  @rpc.PreparedService::prepare(
    model(),
    @smithy.ShapeId::parse("example#Calculator").unwrap(),
    version,
  )
}

///|
test "both versions validate parameters with original positions and effective member constraints" {
  for
    (version, prefix) in [(@rpc.V1_0, ""), (@rpc.V2_0, "\"jsonrpc\":\"2.0\",")] {
    let service = prepared(version)
    for
      (params, valid, code, path) in [
        ("[42,23]", true, "", ""),
        ("[42]", true, "", ""),
        ("[42,\"23\"]", false, "TypeMismatch", "/params/1"),
        ("[0,23]", false, "Range", "/params/0"),
        ("[]", false, "RequiredMember", "/params/0"),
        ("[42,null]", false, "TypeMismatch", "/params/1"),
        ("[42,23,1]", false, "InvalidParams", "/params"),
      ] {
      let result = service.validate_request(
        "{" +
        prefix +
        "\"method\":\"subtract\",\"params\":" +
        params +
        ",\"id\":1}",
      )
      assert_eq(result.is_valid(), valid)
      if !valid {
        assert_eq(result.findings[0].code.to_string(), code)
        assert_eq(result.findings[0].path.pointer(), path)
        assert_eq(
          result.findings[0].operation.unwrap().to_string(),
          "example#Subtract",
        )
        if code == "TypeMismatch" {
          assert_eq(
            result.findings[0].shape.to_string(),
            "example#Input$subtrahend",
          )
        }
      }
    }
    assert_true(
      service
      .validate_request(
        "{" + prefix + "\"method\":\"ping\",\"params\":[],\"id\":null}",
      )
      .is_valid(),
    )
  }
}

///|
test "version two named omitted and empty params follow the modeled input" {
  let service = prepared(@rpc.V2_0)
  for
    params in [
      "{\"minuend\":42,\"subtrahend\":23}", "{\"subtrahend\":23,\"minuend\":42}",
    ] {
    assert_true(
      service
      .validate_request(
        "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":" +
        params +
        "}",
      )
      .is_valid(),
    )
  }
  for tail in ["", ",\"params\":{}", ",\"params\":[]"] {
    assert_true(
      service
      .validate_request("{\"jsonrpc\":\"2.0\",\"method\":\"ping\"" + tail + "}")
      .is_valid(),
    )
    let result = service.validate_request(
      "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\"" + tail + "}",
    )
    assert_eq(result.findings[0].code, @rpc.Value(@validation.RequiredMember))
  }
  let result = service.validate_request(
    "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":{\"minuend\":1,\"unknown\":2}}",
  )
  assert_eq(result.findings[0].code, @rpc.Value(@validation.UnknownMember))
  assert_eq(result.findings[0].path.pointer(), "/params/unknown")
}

///|
test "IDs preserve exact values and version-specific notification semantics" {
  let v1 = prepared(@rpc.V1_0)
  let v2 = prepared(@rpc.V2_0)
  for
    raw in [
      "9007199254740993", "0.10000000000000000001", "1e1000000", "-0.00", "null",
      "\"abc\"", "true", "[1,2]", "{\"x\":9007199254740993}",
    ] {
    let result = v1.validate_request(
      "{\"method\":\"ping\",\"params\":[],\"id\":" + raw + "}",
    )
    assert_true(result.is_valid(), msg=raw)
    assert_eq(
      result.kind,
      Some(if raw == "null" { @rpc.Notification } else { @rpc.Call }),
    )
    guard result.id is @rpc.Present(id) else {
      fail("Expected a present legacy ID")
    }
    assert_eq(@json.to_json(id).stringify(), raw)
    let result = v2.validate_request(
      "{\"jsonrpc\":\"2.0\",\"method\":\"ping\",\"id\":" + raw + "}",
    )
    assert_eq(result.kind, Some(@rpc.Call))
    assert_eq(
      result.is_valid(),
      raw != "true" && !raw.has_prefix("[") && !raw.has_prefix("{"),
    )
    if raw == "null" || raw == "0.10000000000000000001" {
      assert_eq(result.findings[0].code, @rpc.DiscouragedId)
      assert_eq(result.findings[0].severity, @validation.Advisory)
    }
  }
  assert_eq(
    v2.validate_request("{\"jsonrpc\":\"2.0\",\"method\":\"ping\"}").kind,
    Some(@rpc.Notification),
  )
  assert_false(
    v1.validate_request("{\"method\":\"ping\",\"params\":[]}").is_valid(),
  )
  assert_eq(
    v2.validate_request("{\"jsonrpc\":\"2.0\",\"method\":\"unknown\"}").kind,
    Some(@rpc.Notification),
  )
}

///|
test "malformed envelopes unsupported entry points duplicate keys and parse offsets" {
  let service = prepared(@rpc.V2_0)
  for
    (message, code) in [
      ("{}", "InvalidVersion"),
      ("null", "InvalidEnvelope"),
      ("[]", "UnsupportedMessage"),
      ("{\"jsonrpc\":\"2.0\",\"result\":1,\"id\":1}", "UnsupportedMessage"),
      ("{\"jsonrpc\":\"2.0\",\"method\":1}", "InvalidEnvelope"),
      ("{\"jsonrpc\":\"2.0\",\"method\":\"rpc.discover\"}", "InvalidEnvelope"),
      ("{\"jsonrpc\":\"2.0\",\"method\":\"Ping\"}", "UnknownMethod"),
      (
        "{\"jsonrpc\":\"2.0\",\"method\":\"ping\",\"params\":null}", "InvalidParams",
      ),
      ("{\"a\":1,\"\\u0061\":2}", "DuplicateJsonKey"),
      ("{\"a\":truX}", "InvalidJson"),
    ] {
    let result = service.validate_request(message)
    assert_false(result.is_valid(), msg=message)
    assert_eq(result.findings[0].code.to_string(), code, msg=message)
    if code == "InvalidJson" {
      assert_true(result.findings[0].offset.unwrap() < message.length())
    }
  }
  assert_true(
    service
    .validate_request(
      "{\"jsonrpc\":\"2.0\",\"method\":\"ping\",\"extension\":{\"any\":true}}",
    )
    .is_valid(),
  )
  assert_false(
    prepared(@rpc.V1_0)
    .validate_request("{\"method\":\"ping\",\"id\":1}")
    .is_valid(),
  )
  assert_false(
    prepared(@rpc.V1_0)
    .validate_request("{\"method\":\"ping\",\"params\":{},\"id\":1}")
    .is_valid(),
  )
}

///|
test "prepared services snapshot contracts and enforce resource limits" {
  let original = model()
  let id = @smithy.ShapeId::parse("example#Calculator").unwrap()
  let service = @rpc.PreparedService::prepare(original, id, @rpc.V2_0)
  original.shapes.clear()
  assert_true(
    service
    .validate_request("{\"jsonrpc\":\"2.0\",\"method\":\"ping\"}")
    .is_valid(),
  )
  assert_eq(
    service.result_selection(@rpc.MethodName::parse("subtract").unwrap()),
    Some(
      @rpc.OutputMember(@smithy.ShapeId::parse("example#Output$value").unwrap()),
    ),
  )
  let service = @rpc.PreparedService::prepare(
    model(),
    id,
    @rpc.V2_0,
    config=@validation.Config::new(limits=@validation.Limits::new(depth=3)),
  )
  let result = service.validate_request(
    "{\"jsonrpc\":\"2.0\",\"method\":\"ping\",\"extra\":[[[[0]]]]}",
  )
  assert_false(result.complete)
  assert_false(result.is_valid())
}
