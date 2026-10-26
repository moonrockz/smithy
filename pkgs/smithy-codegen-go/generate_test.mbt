///|
fn echo_model() -> @smithy.Model {
  @rpc.loader()
  .add_idl(
    "echo.smithy",
    (
      #|$version: "2"
      #|namespace example
      #|use smithy.rpc#jsonRpc
      #|use smithy.rpc#method
      #|@jsonRpc(versions: ["2.0"])
      #|service Echo { version: "1", operations: [EchoValue] }
      #|@method(name: "echo", params: "named", kind: "request")
      #|operation EchoValue { input: Input, output: Input }
      #|structure Input { @required text: String }
    ),
  )
  .assemble().model.unwrap()
}

///|
test "a plain service generates a typed client and its pinned module" {
  let files = @go.plugin(
    echo_model(),
    @json.parse(
      (
        #|{"service":"example#Echo","peer":"client","module":"example.com/echo","package":"echo"}
      ),
    ),
  )
  assert_true(files["go.mod"].contains("module example.com/echo\n"))
  assert_true(files["types.go"].contains("`json:\"text\"`"))
  assert_true(
    files["peer.go"].contains(
      "EchoValue(ctx context.Context, input Input) (Input, error)",
    ),
  )
}

///|
test "the plain client fixture records its public generated files" (
  t : @test.Test,
) {
  let files = @go.plugin(
    echo_model(),
    @json.parse(
      (
        #|{"service":"example#Echo","peer":"client","module":"example.com/echo","package":"echo"}
      ),
    ),
  )
  for path in ["contract.go", "errors.go", "peer.go", "types.go"] {
    t.write("== " + path + " ==\n" + files[path])
  }
  t.snapshot(filename="echo-client.txt")
}

///|
test "an error code outside int64 fails before it writes Go" {
  let model = @rpc.loader()
  .add_idl(
    "large-code.smithy",
    (
      #|$version: "2"
      #|namespace example
      #|use smithy.rpc#jsonRpc
      #|use smithy.rpc#method
      #|use smithy.rpc#rpcError
      #|@jsonRpc(versions: ["2.0"])
      #|service Api { version: "1", operations: [Run] }
      #|@method(name: "run", params: "named", nullResult: true)
      #|operation Run { errors: [TooLarge] }
      #|@error("server")
      #|@rpcError(code: 1001, absentData: true)
      #|structure TooLarge {}
    ),
  )
  .assemble().model.unwrap()
  let shape = model.get("example#TooLarge").unwrap()
  let traits = shape.traits.copy()
  traits[@smithy.ShapeId::parse("smithy.rpc#rpcError").unwrap()] = @smithy.NodeValue::Object({
      "code": Number(@smithy.NodeNumber::parse("9223372036854775808").unwrap()),
      "absentData": Boolean(true),
    },
  )
  model.shapes[shape.id] = { ..shape, traits, }
  let message = try {
    let _ = @go.plugin(model, @json.parse("{\"service\":\"example#Api\"}"))
    "no error"
  } catch {
    @build.InvalidBuildConfig(message) => message
    error => fail("I found an unexpected build error: \{error}.")
  }
  assert_true(message.contains("I expected an int64 error code"))
  assert_true(message.contains("example#TooLarge"))
}

///|
test "collections resolve member targets and keep sealed union codecs" (
  t : @test.Test,
) {
  let model = @rpc.loader()
  .add_idl(
    "collections.smithy",
    (
      #|$version: "2"
      #|namespace example.collections
      #|use smithy.rpc#jsonRpc
      #|use smithy.rpc#method
      #|@jsonRpc(versions: ["2.0"])
      #|service Api { version: "1", operations: [Exchange] }
      #|@method(name: "exchange", params: "positional", positional: ["items", "table"])
      #|operation Exchange { input: Input, output: Input }
      #|structure Input { @required items: Items, table: Table }
      #|list Items { member: Choice }
      #|map Table { key: String, value: Choice }
      #|union Choice { text: String, decimal: BigDecimal, integer: BigInteger }
    ),
  )
  .assemble().model.unwrap()
  let files = @go.plugin(
    model,
    @json.parse(
      (
        #|{"service":"example.collections#Api","peer":"client","module":"example.com/collections"}
      ),
    ),
  )
  assert_true(files["types.go"].contains("type Items []Choice"))
  assert_true(files["types.go"].contains("type Table map[string]Choice"))
  assert_true(
    files["types.go"].contains("type Choice interface { isChoice() }"),
  )
  assert_true(files["types.go"].contains("Value rpc.Number"))
  assert_true(files["types.go"].contains("Value rpc.Integer"))
  for path in ["contract.go", "peer.go", "types.go"] {
    t.write("== " + path + " ==\n" + files[path])
  }
  t.snapshot(filename="collections-client.txt")
}

///|
fn build_message(model : @smithy.Model, settings : String) -> String raise {
  try {
    let _ = @go.plugin(model, @json.parse(settings))
    "no error"
  } catch {
    @build.InvalidBuildConfig(message) => message
    error => fail("I found an unexpected build error: \{error}.")
  }
}

///|
test "settings errors name their construct in lexical order" {
  let model = echo_model()
  assert_eq(
    build_message(
      model,
      (
        #|{"service":"example#Echo","z":1,"a":1}
      ),
    ),
    "I found unknown setting `a`.",
  )
  assert_true(
    build_message(
      model,
      (
        #|{"service":"example#Echo","package":"type"}
      ),
    ).contains("Go package name in setting `package`"),
  )
  assert_true(
    build_message(
      model,
      (
        #|{"service":"example#Echo","module":"../escape"}
      ),
    ).contains("Go module path in setting `module`"),
  )
  assert_true(
    build_message(
      model,
      (
        #|{"service":"example#Echo","peer":"missing"}
      ),
    ).contains("peer `missing`"),
  )
  assert_true(
    build_message(
      model,
      (
        #|{"service":"example#Echo","transports":["udp"]}
      ),
    ).contains("setting `transports`"),
  )
}

///|
test "a prepared description generates the same files as the plugin" {
  let model = echo_model()
  let description = @jsonrpc.Description::for_service(
    model,
    @smithy.ShapeId::parse("example#Echo").unwrap(),
    @rpc.V2_0,
  )
  let direct = @go.generate(
    model,
    description,
    @rpc.PeerName::parse("server").unwrap(),
  )
  let adapted = @go.plugin(
    model,
    @json.parse("{\"service\":\"example#Echo\",\"peer\":\"server\"}"),
  )
  assert_eq(direct, adapted)
  assert_true(
    direct["peer.go"].contains(
      "EchoValue func(ctx context.Context, input Input) (Input, error)",
    ),
  )
}

///|
test "service rename runs before Go casing" {
  let model = @rpc.loader()
  .add_idl(
    "rename.smithy",
    (
      #|$version: "2"
      #|namespace example.rename
      #|use smithy.rpc#jsonRpc
      #|use smithy.rpc#method
      #|@jsonRpc(versions: ["2.0"])
      #|service Api {
      #| version: "1", operations: [Run]
      #| rename: { "example.rename#Input": "request_value" }
      #|}
      #|@method(name: "run", params: "named", nullResult: true)
      #|operation Run { input: Input }
      #|structure Input { @required value: String }
    ),
  )
  .assemble().model.unwrap()
  let files = @go.plugin(
    model,
    @json.parse("{\"service\":\"example.rename#Api\"}"),
  )
  assert_true(files["types.go"].contains("type RequestValue struct"))
  assert_true(files["peer.go"].contains("input RequestValue"))
}

///|
test "model insertion order does not change output" {
  let model = echo_model()
  let settings = @json.parse("{\"service\":\"example#Echo\"}")
  let first = @go.plugin(model, settings)
  let entries = model.shapes.to_array()
  model.shapes.clear()
  for (id, shape) in entries.rev() {
    model.shapes[id] = shape
  }
  assert_eq(first, @go.plugin(model, settings))
}

///|
test "the direct API checks the Go output names" {
  let model = echo_model()
  let description = @jsonrpc.Description::for_service(
    model,
    @smithy.ShapeId::parse("example#Echo").unwrap(),
    @rpc.V2_0,
  )
  let peer = @rpc.PeerName::parse("client").unwrap()
  let rejected_module = try {
    let _ = @go.generate(model, description, peer, module_name="../escape")
    false
  } catch {
    _ => true
  }
  assert_true(rejected_module)
  let rejected_package = try {
    let _ = @go.generate(model, description, peer, package_name="type")
    false
  } catch {
    _ => true
  }
  assert_true(rejected_package)
}

///|
test "the prepared default selects the timestamp type" {
  let model = @rpc.loader()
  .add_idl(
    "time.smithy",
    (
      #|$version: "2"
      #|namespace example.time
      #|use smithy.rpc#jsonRpc
      #|use smithy.rpc#method
      #|@jsonRpc(versions: ["2.0"])
      #|service Api { version: "1", operations: [Run] }
      #|@method(name: "run", params: "named", nullResult: true)
      #|operation Run { input: Input }
      #|structure Input { @required at: Timestamp, @required other: Date }
      #|timestamp Date
    ),
  )
  .assemble().model.unwrap()
  let description = @jsonrpc.Description::for_service(
    model,
    @smithy.ShapeId::parse("example.time#Api").unwrap(),
    @rpc.V2_0,
    config=@validation.Config::new(timestamp_format=@validation.DateTime),
  )
  let files = @go.generate(
    model,
    description,
    @rpc.PeerName::parse("client").unwrap(),
  )
  assert_true(files["types.go"].contains("At string `json:\"at\"`"))
  assert_true(files["types.go"].contains("type Date = string"))
}

///|
test "a union variant cannot replace a modeled declaration" {
  let model = @rpc.loader()
  .add_idl(
    "names.smithy",
    (
      #|$version: "2"
      #|namespace example.names
      #|use smithy.rpc#jsonRpc
      #|use smithy.rpc#method
      #|@jsonRpc(versions: ["2.0"])
      #|service Api { version: "1", operations: [Run] }
      #|@method(name: "run", params: "named", nullResult: true)
      #|operation Run { input: Input }
      #|structure Input { choice: Choice, collision: ChoiceText }
      #|union Choice { text: String }
      #|structure ChoiceText {}
    ),
  )
  .assemble().model.unwrap()
  let message = build_message(model, "{\"service\":\"example.names#Api\"}")
  assert_true(message.contains("Go declaration name conflict"))
  assert_true(message.contains("ChoiceText"))
}

///|
test "generated methods and decoders keep distinct names" {
  let cases = [
    ("Serve", "structure Input { text: String }", "Go method name conflict"),
    (
      "Run", "structure Input { unmarshalJSON: String }", "Go member name conflict",
    ),
    (
      "Run", "structure Input { detail: RunError }\nunion RunError { text: String }",
      "Go declaration name conflict",
    ),
  ]
  for (operation_name, shapes, expected) in cases {
    let text = "$version: \"2\"\nnamespace example.names\nuse smithy.rpc#jsonRpc\nuse smithy.rpc#method\n@jsonRpc(versions: [\"2.0\"])\nservice Api { version: \"1\", operations: [\{operation_name}] }\n@method(name: \"run\", params: \"named\", nullResult: true)\noperation \{operation_name} { input: Input }\n\{shapes}\n"
    let model = @rpc.loader().add_idl("names.smithy", text).assemble().model.unwrap()
    assert_true(
      build_message(model, "{\"service\":\"example.names#Api\"}").contains(
        expected,
      ),
    )
  }
}
