///|
fn server_error_model(
  policy~ : String = "",
  code~ : String = "-32011",
  selector~ : String = "",
  service_error~ : Bool = false,
  extra_error~ : String = "",
) -> @smithy.Model raise {
  let errors = "errors: [Problem" +
    (if extra_error == "" { "" } else { ", Other" }) +
    "]"
  let loaded = @rpc.loader()
    .add_idl(
      "server-errors.smithy",
      "$version: \"2\"\nnamespace servererrors\n" +
      "use smithy.rpc#jsonRpc\nuse smithy.rpc#method\nuse smithy.rpc#rpcError\n" +
      "@jsonRpc(versions: [\"2.0\"]" +
      policy +
      ")\n" +
      "service Api { version: \"1\", operations: [Op]" +
      (if service_error { ", " + errors } else { "" }) +
      " }\n" +
      "@method(name: \"init\", params: \"named\")\n" +
      "operation Op { input: Input, output: Output" +
      (if service_error { "" } else { ", " + errors }) +
      " }\n" +
      "structure Input {}\nstructure Output {}\n" +
      "@error(\"client\")\n@rpcError(code: " +
      code +
      selector +
      ")\n" +
      "structure Problem {\n  @required hostVersions: Versions\n  @required extensionVersions: Versions\n  optionalDetail: String\n}\n" +
      "map Versions { key: String, value: String }\n" +
      extra_error,
    )
    .assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  model
}

///|
fn prepare_server_errors(model : @smithy.Model) -> @rpc.PreparedService raise {
  @rpc.PreparedService::prepare(
    model,
    @smithy.ShapeId::parse("servererrors#Api").unwrap(),
    @rpc.V2_0,
  )
}

///|
fn check_server_error(
  service : @rpc.PreparedService,
  code : String,
  data~ : String = "",
) -> @rpc.ResponseResult {
  service.validate_response(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":" +
    code +
    ",\"message\":\"failure\"" +
    data +
    "}}",
    context=Some(@rpc.Method(@rpc.MethodName::parse("init").unwrap())),
  )
}

///|
test "declared operation and service server codes validate required data" {
  for service_error in [false, true] {
    for code in ["-32099", "-32011", "-32000"] {
      let service = prepare_server_errors(
        server_error_model(code~, service_error~),
      )
      let good = check_server_error(
        service,
        code,
        data=",\"data\":{\"hostVersions\":{\"core\":\"1\"},\"extensionVersions\":{\"x\":\"2\"}}",
      )
      assert_true(good.is_valid())
      assert_eq(good.kind, Some(@rpc.ProtocolError))
      assert_eq(good.findings.length(), 0)
      let bad = check_server_error(
        service,
        code,
        data=",\"data\":{\"hostVersions\":{}}",
      )
      assert_false(bad.is_valid())
      assert_true(
        bad.findings
        .iter()
        .any(f => f.path.pointer() == "/error/data/extensionVersions"),
      )
    }
  }
}

///|
test "undeclared server errors default to silent acceptance and allow explicit accept" {
  for policy in ["", ", undeclaredServerErrors: \"accept\""] {
    let service = prepare_server_errors(
      server_error_model(policy~, code="1001"),
    )
    let report = check_server_error(service, "-32050")
    assert_true(report.is_valid())
    assert_eq(report.findings.length(), 0)
  }
}

///|
test "undeclared server error advisory and error policies use the plural trait member" {
  for
    (policy, severity, valid) in [
      ("advisory", @validation.Advisory, true),
      ("error", @validation.Error, false),
    ] {
    let service = prepare_server_errors(
      server_error_model(
        policy=", undeclaredServerErrors: \"\{policy}\"",
        code="1001",
      ),
    )
    let report = check_server_error(service, "-32050")
    assert_eq(report.is_valid(), valid)
    assert_eq(report.findings.length(), 1)
    assert_eq(report.findings[0].code, @rpc.UnknownError)
    assert_eq(report.findings[0].severity, severity)
    assert_eq(report.findings[0].path.pointer(), "/error/code")
  }
}

///|
test "declared server errors always check data independently of undeclared policy" {
  for policy in ["accept", "advisory", "error"] {
    let service = prepare_server_errors(
      server_error_model(policy=", undeclaredServerErrors: \"\{policy}\""),
    )
    let report = check_server_error(service, "-32011")
    assert_false(report.is_valid())
    assert_true(
      report.findings.iter().any(f => f.path.pointer() == "/error/data"),
    )
  }
}

///|
test "server errors retain selected member and absent data contracts" {
  for
    (selector, good_data, bad_data) in [
      (
        ", dataMember: \"hostVersions\"", ",\"data\":{\"core\":\"1\"}", ",\"data\":null",
      ),
      (", dataMember: \"optionalDetail\"", "", ",\"data\":17"),
      (", absentData: true", "", ",\"data\":null"),
    ] {
    let service = prepare_server_errors(server_error_model(selector~))
    assert_true(
      check_server_error(service, "-32011", data=good_data).is_valid(),
    )
    assert_false(
      check_server_error(service, "-32011", data=bad_data).is_valid(),
    )
  }
}

///|
test "server mappings still reject standard reserved and duplicate error codes" {
  for
    code in [
      "-32768", "-32700", "-32600", "-32601", "-32602", "-32603", "-32100",
    ] {
    let mut rejected = false
    ignore(prepare_server_errors(server_error_model(code~))) catch {
      @rpc.InvalidContract(_, _) => rejected = true
      e => fail(e.to_string())
    }
    assert_true(rejected, msg=code)
  }
  let mut rejected = false
  ignore(
    prepare_server_errors(
      server_error_model(
        extra_error="@error(\"client\")\n@rpcError(code: -32011)\nstructure Other {}",
      ),
    ),
  ) catch {
    @rpc.InvalidContract(_, _) => rejected = true
    e => fail(e.to_string())
  }
  assert_true(rejected, msg="duplicate server code")
}

///|
test "invalid undeclared server error policies fail model loading" {
  for value in ["\"ignore\"", "true", "null", "17"] {
    let loaded = @rpc.loader()
      .add_idl(
        "bad-policy.smithy",
        "$version: \"2\"\nnamespace bad\nuse smithy.rpc#jsonRpc\n" +
        "@jsonRpc(versions: [\"2.0\"], undeclaredServerErrors: " +
        value +
        ")\n" +
        "service Api { version: \"1\" }",
      )
      .assemble()
    assert_true(loaded.model is None, msg=value)
    assert_true(
      loaded.diagnostics
      .iter()
      .any(d => d.message.contains("undeclaredServerErrors")),
    )
  }
}
