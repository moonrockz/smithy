///|
/// Same text as examples/json-rpc/peers.smithy.
fn peers_source() -> String {
  (
    #|$version: "2"
    #|namespace example.peers
    #|
    #|use smithy.rpc#jsonRpc
    #|use smithy.rpc#jsonRpcProtocol
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
    #|operation Initialize { input: InitializeInput, output: InitializeOutput }
    #|
    #|structure InitializeInput { processId: Integer }
    #|
    #|structure InitializeOutput { capabilities: String }
    #|
    #|@method(name: "shutdown", params: "named", nullResult: true)
    #|operation Shutdown {}
    #|
    #|@method(name: "textDocument/hover", params: "named", resultMember: "contents")
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
    #|operation Exit {}
    #|
    #|@method(name: "workspace/configuration", params: "named", resultMember: "items")
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
fn expect_invalid(
  source : String,
  version : @rpc.ProtocolVersion,
) -> Unit raise {
  let model = load(source)
  try describe(model, "t#P", version) catch {
    @rpc.InvalidContract(_, _) => ()
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
