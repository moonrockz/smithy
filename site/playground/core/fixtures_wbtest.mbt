///|
let chat_model : String =
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

///|
/// The model of the mockup: a typo in the type of `count`.
let bad_model : String = chat_model.replace(
  old="count: Integer",
  new="count: Intger",
)

///|
/// The chat transcript of the mockup: a wrong result and a call without a reply.
let chat_markdown : String =
  #|---
  #|version: 1.0
  #|complete: true
  #|---
  #|# Chat
  #|
  #|```jsonrpc client -> server
  #|{"method": "postMessage", "params": ["Hello all!"], "id": 99}
  #|```
  #|
  #|```jsonrpc server -> client
  #|{"method": "handleMessage", "params": ["user1", "I'm in!"], "id": null}
  #|```
  #|
  #|```jsonrpc server
  #|{"result": "one", "error": null, "id": 99}
  #|```
  #|
  #|```jsonrpc client -> server
  #|{"method": "echo", "params": [], "id": 100}
  #|```

///|
let calculator_model : String =
  #|$version: "2"
  #|namespace example
  #|use smithy.rpc#jsonRpc
  #|use smithy.rpc#method
  #|@jsonRpc(versions: ["1.0", "2.0"])
  #|service Calculator {
  #|    version: "1"
  #|    operations: [Subtract, Ping]
  #|}
  #|@method(name: "subtract", params: "either",
  #|    positional: ["minuend", "subtrahend"], resultMember: "value")
  #|operation Subtract { input: SubtractInput, output: SubtractOutput }
  #|structure SubtractInput {
  #|    @required
  #|    minuend: Integer
  #|    @required
  #|    subtrahend: Integer
  #|}
  #|structure SubtractOutput { value: Integer }
  #|@method(name: "ping", params: "either", positional: [], nullResult: true)
  #|operation Ping {}

///|
let web_model : String =
  #|$version: "2"
  #|namespace example.web
  #|use aws.protocols#restJson1
  #|@restJson1
  #|service Weather { version: "1", operations: [GetCity] }
  #|@readonly
  #|@http(method: "GET", uri: "/city")
  #|operation GetCity { output: CityOutput }
  #|structure CityOutput { name: String }

///|
/// Two services. `AlphaRpc` sorts first and has no protocol trait for OpenAPI.
/// The Validate tab marks `restJson1` here, as for `web_model`; the OpenAPI
/// transform loads the bundled protocol definitions.
let mixed_model : String =
  #|$version: "2"
  #|namespace example.mixed
  #|use aws.protocols#restJson1
  #|use smithy.rpc#jsonRpc
  #|use smithy.rpc#method
  #|@jsonRpc(versions: ["2.0"])
  #|service AlphaRpc { version: "1", operations: [Ping] }
  #|@method(name: "ping", params: "either", positional: [], nullResult: true)
  #|operation Ping {}
  #|@restJson1
  #|service Weather { version: "1", operations: [GetCity] }
  #|@readonly
  #|@http(method: "GET", uri: "/city")
  #|operation GetCity { output: CityOutput }
  #|structure CityOutput { name: String }

///|
/// Two JSON-RPC services. `LegacyRpc` sorts first and speaks version 1.0 only.
let versions_model : String =
  #|$version: "2"
  #|namespace example.versions
  #|use smithy.rpc#jsonRpc
  #|use smithy.rpc#method
  #|@jsonRpc(versions: ["1.0"])
  #|service LegacyRpc { version: "1", operations: [Ping] }
  #|@jsonRpc(versions: ["2.0"])
  #|service NewRpc { version: "1", operations: [Ping] }
  #|@method(name: "ping", params: "either", positional: [], nullResult: true)
  #|operation Ping {}

///|
/// Two JSON-RPC 2.0 services. `Zed` comes first in the file and has the
/// shorter shape ID, but `Alphabet` comes first by shape ID.
let order_model : String =
  #|$version: "2"
  #|namespace example.order
  #|use smithy.rpc#jsonRpc
  #|use smithy.rpc#method
  #|@jsonRpc(versions: ["2.0"])
  #|service Zed { version: "1", operations: [Ping] }
  #|@jsonRpc(versions: ["2.0"])
  #|service Alphabet { version: "1", operations: [Ping] }
  #|@method(name: "ping", params: "either", positional: [], nullResult: true)
  #|operation Ping {}

///|
/// A restJson1 service with an HTTP method that OpenAPI omits.
let warning_model : String =
  #|$version: "2"
  #|namespace example.web
  #|use aws.protocols#restJson1
  #|@restJson1
  #|service Weather { version: "1", operations: [GetCity] }
  #|@http(method: "CONNECT", uri: "/city")
  #|operation GetCity { output: CityOutput }
  #|structure CityOutput { name: String }

///|
/// The chat transcript of the mockup as a JSON document.
let chat_json : String =
  #|{
  #|  "version": "1.0",
  #|  "complete": true,
  #|  "entries": [
  #|    { "from": "client", "message": {"method": "postMessage", "params": ["Hello all!"], "id": 99} },
  #|    { "from": "server", "message": {"method": "handleMessage", "params": ["user1", "I'm in!"], "id": null} },
  #|    { "from": "server", "message": {"result": "one", "error": null, "id": 99} },
  #|    { "from": "client", "message": {"method": "echo", "params": [], "id": 100} }
  #|  ]
  #|}

///|
/// A log with a line that is not JSON and a line that is not a message.
let chat_log : String =
  #|chat bridge starting
  #|{"dir": "request", "message": {"method": "postMessage", "params": ["Hello all!"], "id": 99}}
  #|{"dir": "response", "message": {"result": 1, "error": null, "id": 99}}
  #|{"level": "info"}
