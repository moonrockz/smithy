///|
/// Same text as examples/json-rpc/peers.smithy.
fn peers_source() -> String {
  (
    #|$version: "2"
    #|namespace example.peers
    #|
    #|use smithy.rpc#jsonRpc
    #|use smithy.rpc#jsonRpcLifecycle
    #|use smithy.rpc#jsonRpcProtocol
    #|use smithy.rpc#jsonRpcSession
    #|use smithy.rpc#method
    #|
    #|/// JSON-RPC 1.0 section 4 echo and chat examples.
    #|@jsonRpcProtocol(
    #|    versions: ["1.0"]
    #|    peers: [
    #|        { name: "client", accepts: ChatClient }
    #|        { name: "server", accepts: ChatServer }
    #|    ]
    #|)
    #|structure EchoChat {}
    #|
    #|@jsonRpc(versions: ["1.0"])
    #|service ChatServer {
    #|    version: "1"
    #|    operations: [Echo, PostMessage]
    #|}
    #|
    #|@jsonRpc(versions: ["1.0"])
    #|service ChatClient {
    #|    version: "1"
    #|    operations: [HandleMessage, UserLeft]
    #|}
    #|
    #|@method(name: "echo", params: "positional",
    #|    positional: ["text"], resultMember: "text")
    #|operation Echo { input: EchoInput, output: EchoOutput }
    #|
    #|structure EchoInput { @required text: String }
    #|
    #|structure EchoOutput { text: String }
    #|
    #|@method(name: "postMessage", params: "positional",
    #|    positional: ["text"], resultMember: "count")
    #|operation PostMessage { input: PostMessageInput, output: PostMessageOutput }
    #|
    #|structure PostMessageInput { @required text: String }
    #|
    #|structure PostMessageOutput { count: Integer }
    #|
    #|@method(name: "handleMessage", params: "positional",
    #|    positional: ["from", "text"], nullResult: true)
    #|operation HandleMessage { input: HandleMessageInput }
    #|
    #|structure HandleMessageInput {
    #|    @required from: String
    #|    @required text: String
    #|}
    #|
    #|@method(name: "userLeft", params: "positional",
    #|    positional: ["name"], nullResult: true)
    #|operation UserLeft { input: UserLeftInput }
    #|
    #|structure UserLeftInput { @required name: String }
    #|
    #|/// LSP-like editor protocol: the server answers calls and the client may call back.
    #|@jsonRpcProtocol(
    #|    versions: ["2.0"]
    #|    peers: [
    #|        { name: "client", accepts: LanguageClient }
    #|        { name: "server", accepts: LanguageServer }
    #|    ]
    #|)
    #|structure Editor {}
    #|
    #|/// The Editor services with the LSP order: initialize first, then shutdown, then exit.
    #|/// Editor has no session, so it ignores the lifecycle traits of the operations.
    #|@jsonRpcProtocol(
    #|    versions: ["2.0"]
    #|    peers: [
    #|        { name: "client", accepts: LanguageClient }
    #|        { name: "server", accepts: LanguageServer }
    #|    ]
    #|)
    #|@jsonRpcSession(states: ["starting", "running", "stopping", "stopped"])
    #|structure OrderedEditor {}
    #|
    #|@jsonRpc(versions: ["2.0"])
    #|service LanguageServer {
    #|    version: "1"
    #|    operations: [Initialize, Shutdown, Hover, Exit]
    #|}
    #|
    #|@jsonRpc(versions: ["2.0"])
    #|service LanguageClient {
    #|    version: "1"
    #|    operations: [WorkspaceConfiguration]
    #|}
    #|
    #|@method(name: "initialize", params: "named", resultMember: "capabilities")
    #|@jsonRpcLifecycle(allowedIn: ["starting"], onSuccess: "running")
    #|operation Initialize { input: InitializeInput, output: InitializeOutput }
    #|
    #|structure InitializeInput { processId: Integer }
    #|
    #|structure InitializeOutput { capabilities: String }
    #|
    #|@method(name: "shutdown", params: "named", nullResult: true)
    #|@jsonRpcLifecycle(allowedIn: ["running"], onSuccess: "stopping")
    #|operation Shutdown {}
    #|
    #|@method(name: "textDocument/hover", params: "named", resultMember: "contents")
    #|@jsonRpcLifecycle(allowedIn: ["running"])
    #|operation Hover { input: HoverInput, output: HoverOutput }
    #|
    #|structure HoverInput {
    #|    @required uri: String
    #|    line: Integer
    #|    character: Integer
    #|}
    #|
    #|structure HoverOutput { contents: String }
    #|
    #|@method(name: "exit", params: "named", nullResult: true)
    #|@jsonRpcLifecycle(onCall: "stopped")
    #|operation Exit {}
    #|
    #|@method(name: "workspace/configuration", params: "named", resultMember: "items")
    #|@jsonRpcLifecycle(allowedIn: ["running"])
    #|operation WorkspaceConfiguration { input: ConfigurationInput, output: ConfigurationOutput }
    #|
    #|structure ConfigurationInput { section: String }
    #|
    #|structure ConfigurationOutput { items: StringList }
    #|
    #|list StringList { member: String }
    #|
    #|/// The second peer accepts nothing, so it only ever receives replies.
    #|@jsonRpcProtocol(
    #|    versions: ["2.0"]
    #|    peers: [
    #|        { name: "sender", accepts: Sink }
    #|        { name: "listener" }
    #|    ]
    #|)
    #|structure OneWay {}
    #|
    #|@jsonRpc(versions: ["2.0"])
    #|service Sink {
    #|    version: "1"
    #|    operations: [Push]
    #|}
    #|
    #|@method(name: "push", params: "named", nullResult: true)
    #|operation Push { input: PushInput }
    #|
    #|structure PushInput { value: String }
  )
}

///|
fn load(source : String) -> @smithy.Model raise {
  let loaded = @rpc.loader().add_idl("protocol.smithy", source).assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  model
}

///|
fn describe(
  model : @smithy.Model,
  name : String,
  version : @rpc.ProtocolVersion,
) -> @rpc.ProtocolDescription raise {
  @rpc.ProtocolDescription::from_smithy(
    model,
    @smithy.ShapeId::parse(name).unwrap(),
    version,
  )
}

///|
fn peer(name : String) -> @rpc.PeerName {
  @rpc.PeerName::parse(name).unwrap()
}

///|
test "prepares one service per receiving peer" {
  let model = load(peers_source())
  let editor = describe(model, "example.peers#Editor", @rpc.V2_0)
  assert_eq(editor.peers().map(p => p.to_string()), ["client", "server"])
  assert_eq(editor.version(), @rpc.V2_0)
  assert_eq(editor.protocol().to_string(), "example.peers#Editor")
  assert_eq(editor.other(peer("client")), Some(peer("server")))
  assert_eq(editor.other(peer("server")), Some(peer("client")))
  assert_eq(editor.other(peer("nobody")), None)
  assert_true(editor.service_for(peer("client")) is Some(_))
  assert_true(editor.service_for(peer("server")) is Some(_))
  let chat = describe(model, "example.peers#EchoChat", @rpc.V1_0)
  assert_true(chat.service_for(peer("server")) is Some(_))
}

///|
test "a peer may accept nothing" {
  let model = load(peers_source())
  let one_way = describe(model, "example.peers#OneWay", @rpc.V2_0)
  assert_true(one_way.service_for(peer("sender")) is Some(_))
  assert_true(one_way.service_for(peer("listener")) is None)
}

///|
/// Fails unless the protocol is rejected as an invalid contract, with a
/// message that has `mentions` when it is given.
fn expect_invalid(
  source : String,
  version : @rpc.ProtocolVersion,
  mentions? : String,
) -> Unit raise {
  let model = load(source)
  try describe(model, "t#P", version) catch {
    @rpc.InvalidContract(_, message) =>
      if mentions is Some(word) && !message.contains(word) {
        fail("I expected a message with \{word}; I found \{message}")
      }
    e => fail("unexpected error: \{e}")
  } noraise {
    _ => fail("I expected the protocol to be rejected.")
  }
}

///|
fn protocol_model(trait_args : String, service_versions : String) -> String {
  "$version: \"2\"\nnamespace t\nuse smithy.rpc#jsonRpc\nuse smithy.rpc#jsonRpcProtocol\n" +
  "@jsonRpc(versions: \{service_versions})\nservice S { version: \"1\" }\n" +
  trait_args
}

///|
test "rejects undeclared versions duplicate peers and missing traits" {
  let ok_peers = "peers: [{name: \"a\", accepts: S}, {name: \"b\"}]"
  // version not declared by the protocol
  expect_invalid(
    protocol_model(
      "@jsonRpcProtocol(versions: [\"1.0\"], " + ok_peers + ")\nstructure P {}",
      "[\"1.0\", \"2.0\"]",
    ),
    @rpc.V2_0,
  )
  // same peer name twice
  expect_invalid(
    protocol_model(
      "@jsonRpcProtocol(versions: [\"2.0\"], peers: [{name: \"a\", accepts: S}, {name: \"a\"}])\nstructure P {}",
      "[\"2.0\"]",
    ),
    @rpc.V2_0,
  )
  // no protocol trait
  expect_invalid(protocol_model("structure P {}", "[\"2.0\"]"), @rpc.V2_0)
  // missing shape
  expect_invalid(protocol_model("structure Q {}", "[\"2.0\"]"), @rpc.V2_0)
  // accepted service lacks the version
  expect_invalid(
    protocol_model(
      "@jsonRpcProtocol(versions: [\"2.0\"], " + ok_peers + ")\nstructure P {}",
      "[\"1.0\"]",
    ),
    @rpc.V2_0,
  )
}

///|
test "peer names are validated" {
  assert_true(@rpc.PeerName::parse("host") is Some(_))
  assert_true(@rpc.PeerName::parse("a-b_9") is Some(_))
  assert_true(@rpc.PeerName::parse("") is None)
  assert_true(@rpc.PeerName::parse("1x") is None)
  assert_true(@rpc.PeerName::parse("a b") is None)
  assert_true(@rpc.PeerName::parse("a".repeat(65)) is None)
  assert_true(@rpc.PeerName::parse("a".repeat(64)) is Some(_))
}

///|
test "the trait definitions are built in and stay out of exports" {
  let loaded = @rpc.loader().add_idl("peers.smithy", peers_source()).assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  assert_eq(
    model.get("smithy.rpc#jsonRpc").unwrap().source.file,
    "<smithy-rpc-traits>",
  )
  let shapes = model.to_json_ast().shapes.unwrap_or(Map([]))
  assert_false(shapes.keys().any(id => id.has_prefix("smithy.rpc#")))
  assert_true(shapes.contains("example.peers#ChatServer"))
  assert_eq(model.to_idl().keys().to_array(), ["example.peers"])
  let copy = @rpc.loader()
    .add_idl("traits.smithy", @rpc.trait_definitions())
    .add_idl("peers.smithy", peers_source())
    .assemble()
  assert_true(copy.model is Some(_))
  assert_false(copy.diagnostics.iter().any(d => d.severity == Error))
}

///|
/// Assemble peers.smithy with the trait definitions as a user source named
/// like the built-in one.
fn plain_peers() -> @smithy.Model raise {
  let loaded = @smithy.Loader::new()
    .add_idl("<smithy-rpc-traits>", @rpc.trait_definitions())
    .add_idl("peers.smithy", peers_source())
    .assemble()
  guard loaded.model is Some(model) &&
    !loaded.diagnostics.iter().any(d => d.severity == Error) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  model
}

///|
test "a plain loader gives the same model before and after rpc.loader runs" {
  let before = plain_peers()
  let earlier = @smithy.Loader::new()
  .add_idl("peers.smithy", peers_source())
  .add_idl("traits.smithy", @rpc.trait_definitions())
  .assemble().model.unwrap()
  let exported = earlier.to_json_ast().to_json()
  ignore(@rpc.loader().add_idl("peers.smithy", peers_source()).assemble())
  let after = plain_peers()
  assert_eq(after, before)
  assert_false(after.get("smithy.rpc#jsonRpc").unwrap().source.is_builtin())
  assert_true(
    after.to_json_ast().shapes.unwrap_or(Map([])).contains("smithy.rpc#jsonRpc"),
  )
  // A model assembled before still exports its trait definitions.
  assert_eq(earlier.to_json_ast().to_json(), exported)
  assert_true(
    earlier.to_json_ast().shapes
    .unwrap_or(Map([]))
    .contains("smithy.rpc#method"),
  )
}

///|
test "the loader can add the protocol test traits" {
  let plain = @rpc.loader().assemble().model.unwrap()
  assert_true(plain.get("smithy.test#httpRequestTests") is None)
  let loaded = @rpc.loader(protocol_tests=true).assemble().model.unwrap()
  assert_true(loaded.get("smithy.test#httpRequestTests") is Some(_))
  assert_true(loaded.get("smithy.rpc#method") is Some(_))
}
