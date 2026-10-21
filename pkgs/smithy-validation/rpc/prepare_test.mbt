///|
test "serialized JSON AST APIs reload without duplicate optional trait definitions" {
  let original = contract_model(
    "name: \"op\", params: \"either\", positional: [\"a\",\"b\"]",
  )
  let loaded = @rpc.loader()
    .add_ast("api.json", original.to_json_ast())
    .assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  let service = @rpc.PreparedService::prepare(
    model,
    @smithy.ShapeId::parse("test#Api").unwrap(),
    @rpc.V2_0,
  )
  assert_true(
    service
    .validate_request(
      "{\"jsonrpc\":\"2.0\",\"method\":\"op\",\"params\":[1,2]}",
    )
    .is_valid(),
  )
}

///|
fn contract_model(
  method_ : String,
  service~ : String = "[\"1.0\",\"2.0\"]",
  input~ : String = "structure Input { a: Integer, b: Integer }",
) -> @smithy.Model raise {
  let loaded = @rpc.loader()
    .add_idl(
      "model.smithy",
      "$version: \"2\"\nnamespace test\nuse smithy.rpc#jsonRpc\nuse smithy.rpc#method\n@jsonRpc(versions: " +
      service +
      ")\nservice Api { version: \"1\", operations: [Op] }\n@method(" +
      method_ +
      ")\noperation Op { input: Input, output: Output }\n" +
      input +
      "\nstructure Output { value: Integer }\n",
    )
    .assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  model
}

///|
test "preparation rejects ambiguous or incompatible method contracts" {
  for
    (method_, service) in [
      (
        "name: \"rpc.internal\", params: \"either\", positional: [\"a\",\"b\"]",
        "[\"2.0\"]",
      ),
      ("name: \"op\", params: \"named\"", "[\"1.0\",\"2.0\"]"),
      ("name: \"op\", params: \"either\"", "[\"2.0\"]"),
      ("name: \"op\", params: \"either\", positional: [\"a\"]", "[\"2.0\"]"),
      (
        "name: \"op\", params: \"either\", positional: [\"a\",\"a\"]", "[\"2.0\"]",
      ),
      (
        "name: \"op\", params: \"either\", positional: [\"a\",\"missing\"]", "[\"2.0\"]",
      ),
      (
        "name: \"op\", params: \"named\", positional: [\"a\",\"b\"]", "[\"2.0\"]",
      ),
      (
        "name: \"op\", params: \"either\", positional: [\"a\",\"b\"], resultMember: \"missing\"",
        "[\"2.0\"]",
      ),
      (
        "name: \"op\", params: \"either\", positional: [\"a\",\"b\"], resultMember: \"value\", nullResult: true",
        "[\"2.0\"]",
      ),
      (
        "name: \"op\", params: \"either\", positional: [\"a\",\"b\"]", "[\"1.0\"]",
      ),
      (
        "name: \"op\", params: \"either\", positional: [\"a\",\"b\"]", "[\"2.0\",\"2.0\"]",
      ),
    ] {
    let model = contract_model(method_, service~)
    let mut rejected = false
    ignore(
      @rpc.PreparedService::prepare(
        model,
        @smithy.ShapeId::parse("test#Api").unwrap(),
        @rpc.V2_0,
      ),
    ) catch {
      @rpc.InvalidContract(_, _) => rejected = true
      _ => fail("Expected an invalid method contract")
    }
    assert_true(rejected, msg=method_ + " " + service)
  }
}

///|
test "parameter modes and jsonName policy preserve positional source locations" {
  for
    (mode, valid_named, valid_positional) in [
      ("named", true, false),
      ("positional", false, true),
      ("either", true, true),
    ] {
    let order = if mode == "named" { "" } else { ", positional: [\"a\",\"b\"]" }
    let model = contract_model(
      "name: \"op\", params: \"" + mode + "\"" + order,
      service="[\"2.0\"]",
      input="structure Input { @jsonName(\"A\") a: Integer, b: Integer }",
    )
    let service = @rpc.PreparedService::prepare(
      model,
      @smithy.ShapeId::parse("test#Api").unwrap(),
      @rpc.V2_0,
      config=@validation.Config::new(member_names=@validation.JsonName),
    )
    assert_eq(
      service
      .validate_request(
        "{\"jsonrpc\":\"2.0\",\"method\":\"op\",\"params\":{\"A\":1}}",
      )
      .is_valid(),
      valid_named,
    )
    assert_eq(
      service
      .validate_request(
        "{\"jsonrpc\":\"2.0\",\"method\":\"op\",\"params\":[1]}",
      )
      .is_valid(),
      valid_positional,
    )
    if valid_positional {
      let result = service.validate_request(
        "{\"jsonrpc\":\"2.0\",\"method\":\"op\",\"params\":[\"bad\"]}",
      )
      assert_eq(result.findings[0].path.pointer(), "/params/0")
      assert_eq(result.findings[0].shape.to_string(), "test#Input$a")
    }
  }
}

///|
test "service closure includes resource operations and rejects duplicate wire names" {
  let loaded = @rpc.loader()
    .add_idl(
      "resources.smithy", "$version: \"2\"\nnamespace test\nuse smithy.rpc#jsonRpc\nuse smithy.rpc#method\n@jsonRpc(versions: [\"2.0\"])\nservice Api { version: \"1\", resources: [Thing] }\nresource Thing { operations: [One, Two] }\n@method(name: \"op\", params: \"either\", positional: [])\noperation One {}\n@method(name: \"op\", params: \"either\", positional: [])\noperation Two {}\n",
    )
    .assemble()
  let mut rejected = false
  ignore(
    @rpc.PreparedService::prepare(
      loaded.model.unwrap(),
      @smithy.ShapeId::parse("test#Api").unwrap(),
      @rpc.V2_0,
    ),
  ) catch {
    @rpc.InvalidContract(_, _) => rejected = true
    _ => fail("Expected duplicate method rejection")
  }
  assert_true(rejected)
}
