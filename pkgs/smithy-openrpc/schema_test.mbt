///|
test "base64 byte lengths and recorded leap-second policies are explicit schema limitations" {
  let loaded = @rpc.loader()
    .add_idl(
      "binary.smithy",
      (
        #|$version: "2"
        #|namespace binary
        #|use smithy.rpc#jsonRpc
        #|use smithy.rpc#method
        #|@jsonRpc(versions: ["2.0"])
        #|service Api { version: "1", operations: [Op] }
        #|@method(name: "op", params: "named", nullResult: true)
        #|operation Op { input: Input }
        #|structure Input {
        #| @length(min: 3, max: 3) bytes: Blob
        #| @timestampFormat("date-time") time: Timestamp
        #|}
      ),
    )
    .assemble()
  let converted = @openrpc.convert_result(
    loaded.model.unwrap(),
    @openrpc.Config::new(@openrpc.ServiceId::parse("binary#Api").unwrap()),
  )
  guard method_(converted.document, "op")["params"] is Array(params) else {
    fail("Expected descriptors")
  }
  let blob = object(object(params[0])["schema"])
  assert_false(blob.contains("maxLength"))
  assert_false(blob.contains("minLength"))
  assert_eq(blob["x-smithy-byteLength"], @json.parse("{\"min\":3,\"max\":3}"))
  assert_true(blob.get("pattern") is Some(String(_)))
  assert_eq(
    object(object(params[1])["schema"])["x-smithy-timestamp-policy"],
    Json::string("recorded-leap-seconds"),
  )
  assert_true(
    converted.warnings
    .iter()
    .any(w => {
      w.code == @openrpc.SchemaLimitation &&
      w.shape.to_string() == "binary#Input$bytes"
    }),
  )
  assert_true(
    converted.warnings
    .iter()
    .any(w => {
      w.code == @openrpc.SchemaLimitation &&
      w.shape.to_string() == "binary#Input$time"
    }),
  )
}

///|
test "literal dollar-ref example data is not a schema reference" {
  let loaded = @rpc.loader()
    .add_idl(
      "document.smithy",
      (
        #|$version: "2"
        #|namespace doc
        #|use smithy.rpc#jsonRpc
        #|use smithy.rpc#method
        #|use smithy.rpc#rpcError
        #|@jsonRpc(versions: ["2.0"])
        #|service Api { version: "1", operations: [Op] }
        #|@method(name: "op", params: "named", nullResult: true)
        #|@examples([{title:"literal",input:{},error:{shapeId:"doc#Problem",content:{data:{"$ref":"https://example.com/data"}}}}])
        #|operation Op { errors: [Problem] }
        #|@error("client") @rpcError(code:1001,dataMember:"data")
        #|structure Problem { data: Document }
      ),
    )
    .assemble()
  assert_false(loaded.has_errors())
  let converted = @openrpc.convert(
    loaded.model.unwrap(),
    @openrpc.Config::new(@openrpc.ServiceId::parse("doc#Api").unwrap()),
  )
  assert_true(
    method_(converted, "op")["x-smithy-error-examples"] is Array(values) &&
    values.length() == 1,
  )
}

///|
test "schema properties named like JSON Schema keywords retain their component references" {
  let loaded = @rpc.loader()
    .add_idl(
      "names.smithy",
      (
        #|$version: "2"
        #|namespace names
        #|use smithy.rpc#jsonRpc
        #|use smithy.rpc#method
        #|@jsonRpc(versions: ["2.0"])
        #|service Api { version: "1", operations: [Op] }
        #|@method(name: "op", params: "named")
        #|operation Op { output: Output }
        #|structure Output { examples: Child, default: Child, const: Child, enum: Child }
        #|structure Child { name: String }
      ),
    )
    .assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  let converted = @openrpc.convert(
    model,
    @openrpc.Config::new(@openrpc.ServiceId::parse("names#Api").unwrap()),
  )
  assert_true(
    converted is { "components": { "schemas": { "Child": _, .. }, .. }, .. },
  )
}

///|
test "a contextual Unit collision fails rather than changing union payload contracts" {
  let loaded = @rpc.loader()
    .add_idl(
      "unit.smithy",
      (
        #|$version: "2"
        #|namespace unit
        #|use smithy.rpc#jsonRpc
        #|use smithy.rpc#method
        #|@jsonRpc(versions: ["2.0"])
        #|service Api { version: "1", operations: [Op] }
        #|@method(name: "op", params: "named")
        #|operation Op { output: Output }
        #|structure Output { value: Choice }
        #|union Choice { empty: smithy.api#Unit, payload: Unit }
        #|structure Unit { @required name: String }
      ),
    )
    .assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  let mut rejected = false
  ignore(
    @openrpc.convert(
      model,
      @openrpc.Config::new(@openrpc.ServiceId::parse("unit#Api").unwrap()),
    ),
  ) catch {
    @openrpc.SchemaConversion(id, message) => {
      rejected = true
      assert_eq(id.to_string(), "unit#Api")
      assert_true(message.contains("Unit"))
    }
    _ => fail("Expected schema collision")
  }
  assert_true(rejected)
}

///|
test "an empty top-level JSON wire name cannot become an invalid OpenRPC descriptor" {
  let loaded = @rpc.loader()
    .add_idl(
      "empty-name.smithy",
      (
        #|$version: "2"
        #|namespace emptyname
        #|use smithy.rpc#jsonRpc
        #|use smithy.rpc#method
        #|@jsonRpc(versions: ["2.0"])
        #|service Api { version: "1", operations: [Op] }
        #|@method(name: "op", params: "named", nullResult: true)
        #|operation Op { input: Input }
        #|structure Input { @jsonName("") value: String }
      ),
    )
    .assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  let id = @openrpc.ServiceId::parse("emptyname#Api").unwrap()
  let mut rejected = false
  ignore(
    @openrpc.convert(
      model,
      @openrpc.Config::new(id, member_names=@validation.JsonName),
    ),
  ) catch {
    @openrpc.UnsupportedMapping(subject, _) => {
      rejected = true
      assert_eq(subject.to_string(), "emptyname#Input$value")
    }
    _ => fail("Expected an unrepresentable descriptor name")
  }
  assert_true(rejected)
  assert_true(
    @openrpc.convert(model, @openrpc.Config::new(id))
    is { "openrpc": String("1.3.2"), .. },
  )
}

///|
test "extension policies preserve properties whose wire names match schema metadata" {
  let loaded = @rpc.loader()
    .add_idl(
      "names.smithy",
      (
        #|$version: "2"
        #|namespace metadata
        #|use smithy.rpc#jsonRpc
        #|use smithy.rpc#method
        #|@jsonRpc(versions: ["2.0"])
        #|service Api { version: "1", operations: [Op] }
        #|@method(name: "op", params: "named")
        #|operation Op { output: Output }
        #|structure Output { @required @jsonName("x-smithy-byteLength") value: String }
      ),
    )
    .assemble()
  assert_false(loaded.has_errors())
  for policy in [@openrpc.Preserve, @openrpc.Omit] {
    let converted = @openrpc.convert_result(
      loaded.model.unwrap(),
      @openrpc.Config::new(
        @openrpc.ServiceId::parse("metadata#Api").unwrap(),
        member_names=@validation.JsonName,
        extensions=policy,
      ),
    )
    assert_true(
      object(method_(converted.document, "op")["result"])["schema"]
      is {
        "properties": {
          "x-smithy-byteLength": { "type": String("string"), .. },
          ..
        },
        ..
      },
    )
    assert_false(
      converted.warnings.iter().any(w => w.code == @openrpc.SchemaLimitation),
    )
  }
}
