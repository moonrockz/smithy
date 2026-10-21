///|
fn api_model(extra~ : String = "") -> @smithy.Model raise {
  let loaded = @rpc.loader()
    .add_idl(
      "api.smithy",
      (
        #|$version: "2"
        #|namespace demo
        #|use smithy.rpc#jsonRpc
        #|use smithy.rpc#method
        #|use smithy.rpc#rpcError
        #|@title("Calculator")
        #|@documentation("A small API.")
        #|@jsonRpc(versions: ["2.0"])
        #|service Api { version: "2026", operations: [Subtract, List, Clear] }
        #|@method(name: "subtract", params: "either", positional: ["right", "left"], resultMember: "value")
        #|operation Subtract { input: Args, output: Answer, errors: [Problem] }
        #|structure Args {
        #|  @required @range(min: 0) @jsonName("L") left: Integer
        #|  @jsonName("R") right: Integer
        #|}
        #|structure Answer { @range(min: -20, max: 20) value: Integer }
        #|@method(name: "list", params: "named", resultMember: "items")
        #|operation List { output: Items }
        #|structure Items { @length(min: 1) items: Values }
        #|list Values { member: Nested }
        #|structure Nested { @required @jsonName("N") name: String, next: Nested }
        #|@method(name: "clear", params: "positional", positional: [], nullResult: true)
        #|operation Clear {}
        #|@error("client")
        #|@rpcError(code: 1001, dataMember: "detail")
        #|structure Problem { @required @length(min: 2) detail: String }
      ) +
      "\n" +
      extra,
    )
    .assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  model
}

///|
fn config() -> @openrpc.Config {
  @openrpc.Config::new(@openrpc.ServiceId::parse("demo#Api").unwrap())
}

///|
fn object(value : Json) -> Map[String, Json] raise {
  guard value is Object(fields) else {
    fail("Expected an object: " + value.stringify())
  }
  fields
}

///|
fn method_(document : Json, name : String) -> Map[String, Json] raise {
  guard document is { "methods": Array(methods), .. } else {
    fail("Expected methods")
  }
  for value in methods {
    if value is { "name": String(found), .. } && found == name {
      return object(value)
    }
  }
  fail("Missing method " + name)
}

///|
test "OpenRPC exports ordered descriptors direct results errors and recursive references" {
  let model = api_model()
  let result = @openrpc.convert_result(model, config())
  let doc = object(result.document)
  assert_eq(doc["openrpc"], Json::string("1.3.2"))
  assert_eq(
    doc["info"],
    @json.parse(
      "{\"title\":\"Calculator\",\"version\":\"2026\",\"description\":\"A small API.\"}",
    ),
  )
  let subtract = method_(result.document, "subtract")
  assert_eq(subtract["paramStructure"], Json::string("either"))
  guard subtract["params"] is Array(params) else {
    fail("Expected descriptors")
  }
  assert_eq(object(params[0])["name"], Json::string("right"))
  assert_eq(object(params[0])["required"], Json::boolean(false))
  assert_eq(object(params[1])["name"], Json::string("left"))
  assert_eq(object(params[1])["required"], Json::boolean(true))
  assert_eq(
    object(subtract["result"])["schema"],
    @json.parse("{\"type\":\"integer\",\"minimum\":-20,\"maximum\":20}"),
  )
  assert_eq(
    subtract["errors"],
    @json.parse("[{\"code\":1001,\"message\":\"Problem\"}]"),
  )
  assert_eq(
    object(method_(result.document, "clear")["result"])["schema"],
    @json.parse("{\"type\":\"null\"}"),
  )
  let list = method_(result.document, "list")
  assert_eq(list["paramStructure"], Json::string("by-name"))
  assert_true(
    object(list["result"])["schema"]
    is { "type": String("array"), "minItems": Number(1, ..), .. },
  )
  assert_eq(
    result.document.stringify(),
    @openrpc.convert(model, config()).stringify(),
  )
  guard doc["components"] is { "schemas": Object(schemas), .. } else {
    fail("Expected shared schemas")
  }
  assert_true(
    schemas.get("Nested")
    is Some(
      {
        "properties": {
          "next": { "$ref": String("#/components/schemas/Nested"), .. },
          ..
        },
        ..
      }
    ),
  )
}

///|
test "OpenRPC uses the selected wire-name policy without changing positional order" {
  let result = @openrpc.convert(
    api_model(),
    @openrpc.Config::new(
      @openrpc.ServiceId::parse("demo#Api").unwrap(),
      member_names=@validation.JsonName,
    ),
  )
  guard method_(result, "subtract")["params"] is Array(params) else {
    fail("Expected params")
  }
  assert_eq(object(params[0])["name"], Json::string("R"))
  assert_eq(object(params[1])["name"], Json::string("L"))
}

///|
test "OpenRPC invalid service protocol document versions and missing mappings are shape-linked" {
  for
    (settings, shape) in [
      ("{\"service\":\"demo#Missing\"}", "demo#Missing"),
      ("{\"service\":\"demo#Args\"}", "demo#Args"),
      ("{\"service\":\"demo#Api\",\"version\":\"1.4.0\"}", "demo#Api"),
      ("{\"service\":\"demo#Api\",\"protocolVersion\":\"1.0\"}", "demo#Api"),
    ] {
    let mut rejected = false
    ignore(
      @openrpc.convert(
        api_model(),
        @openrpc.Config::from_json(@json.parse(settings)),
      ),
    ) catch {
      @openrpc.InvalidConfiguration(id, _) | @openrpc.InvalidContract(id, _) => {
        rejected = true
        assert_eq(id.to_string(), shape)
      }
      _ => fail("Expected shape-linked conversion error")
    }
    assert_true(rejected, msg=settings)
  }
}

///|
test "empty operation output remains a closed empty structure rather than null" {
  let loaded = @rpc.loader()
    .add_idl(
      "empty.smithy",
      (
        #|$version: "2"
        #|namespace empty
        #|use smithy.rpc#jsonRpc
        #|use smithy.rpc#method
        #|@jsonRpc(versions: ["2.0"])
        #|service Api { version: "1", operations: [Op] }
        #|@method(name: "op", params: "named")
        #|operation Op {}
      ),
    )
    .assemble()
  let document = @openrpc.convert(
    loaded.model.unwrap(),
    @openrpc.Config::new(@openrpc.ServiceId::parse("empty#Api").unwrap()),
  )
  assert_eq(
    object(method_(document, "op")["result"])["schema"],
    @json.parse(
      "{\"type\":\"object\",\"properties\":{},\"additionalProperties\":false}",
    ),
  )
}

///|
test "export failures preserve invalid mapping subjects and explicit loss policy" {
  let model = api_model()
  let operation = model.get("demo#Subtract").unwrap()
  operation.traits.remove(@smithy.ShapeId::parse("smithy.rpc#method").unwrap())
  |> ignore
  let mut rejected = false
  ignore(@openrpc.convert(model, config())) catch {
    @openrpc.InvalidContract(id, _) => {
      rejected = true
      assert_eq(id.to_string(), "demo#Subtract")
    }
    _ => fail("Expected the operation mapping failure")
  }
  assert_true(rejected)
  let converted = @openrpc.convert_result(
    api_model(),
    @openrpc.Config::new(
      @openrpc.ServiceId::parse("demo#Api").unwrap(),
      extensions=@openrpc.Omit,
    ),
  )
  assert_true(
    converted.warnings
    .iter()
    .any(w => {
      w.code == @openrpc.OmittedErrorData &&
      w.shape.to_string() == "demo#Subtract"
    }),
  )
  assert_true(
    converted.warnings
    .iter()
    .any(w => {
      w.code == @openrpc.OmittedProtocolSemantics &&
      w.shape.to_string() == "demo#Api"
    }),
  )
  assert_false(
    method_(converted.document, "subtract").contains("x-smithy-error-data"),
  )
}

///|
test "export rejects wire-name collisions before emitting methods" {
  let model = api_model()
  let op = model.get("demo#Subtract").unwrap()
  let trait_id = @smithy.ShapeId::parse("smithy.rpc#method").unwrap()
  guard op.traits[trait_id] is @smithy.Object(mapping) else {
    fail("Expected mapping")
  }
  mapping["name"] = @smithy.String("list")
  let mut rejected = false
  ignore(@openrpc.convert(model, config())) catch {
    @openrpc.InvalidContract(id, message) => {
      rejected = true
      assert_eq(id.to_string(), "demo#Subtract")
      assert_true(message.contains("unique wire method"))
    }
    _ => fail("Expected collision failure")
  }
  assert_true(rejected)
}
