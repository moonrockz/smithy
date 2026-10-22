$version: "2"
namespace example.peers

use smithy.rpc#jsonRpc
use smithy.rpc#jsonRpcLifecycle
use smithy.rpc#jsonRpcProtocol
use smithy.rpc#jsonRpcSession
use smithy.rpc#method

/// JSON-RPC 1.0 section 4 echo and chat examples.
@jsonRpcProtocol(
    versions: ["1.0"]
    peers: [
        { name: "client", accepts: ChatClient }
        { name: "server", accepts: ChatServer }
    ]
)
structure EchoChat {}

@jsonRpc(versions: ["1.0"])
service ChatServer {
    version: "1"
    operations: [Echo, PostMessage]
}

@jsonRpc(versions: ["1.0"])
service ChatClient {
    version: "1"
    operations: [HandleMessage, UserLeft]
}

@method(name: "echo", params: "positional",
    positional: ["text"], resultMember: "text")
operation Echo { input: EchoInput, output: EchoOutput }

structure EchoInput { @required text: String }

structure EchoOutput { text: String }

@method(name: "postMessage", params: "positional",
    positional: ["text"], resultMember: "count")
operation PostMessage { input: PostMessageInput, output: PostMessageOutput }

structure PostMessageInput { @required text: String }

structure PostMessageOutput { count: Integer }

@method(name: "handleMessage", params: "positional",
    positional: ["from", "text"], nullResult: true)
operation HandleMessage { input: HandleMessageInput }

structure HandleMessageInput {
    @required from: String
    @required text: String
}

@method(name: "userLeft", params: "positional",
    positional: ["name"], nullResult: true)
operation UserLeft { input: UserLeftInput }

structure UserLeftInput { @required name: String }

/// LSP-like editor protocol: the server answers calls and the client may call back.
@jsonRpcProtocol(
    versions: ["2.0"]
    peers: [
        { name: "client", accepts: LanguageClient }
        { name: "server", accepts: LanguageServer }
    ]
)
structure Editor {}

/// The Editor services with the LSP order: initialize first, then shutdown, then exit.
/// Editor has no session, so it ignores the lifecycle traits of the operations.
@jsonRpcProtocol(
    versions: ["2.0"]
    peers: [
        { name: "client", accepts: LanguageClient }
        { name: "server", accepts: LanguageServer }
    ]
)
@jsonRpcSession(states: ["starting", "running", "stopping", "stopped"])
structure OrderedEditor {}

@jsonRpc(versions: ["2.0"])
service LanguageServer {
    version: "1"
    operations: [Initialize, Shutdown, Hover, Exit]
}

@jsonRpc(versions: ["2.0"])
service LanguageClient {
    version: "1"
    operations: [WorkspaceConfiguration]
}

@method(name: "initialize", params: "named", resultMember: "capabilities")
@jsonRpcLifecycle(allowedIn: ["starting"], onSuccess: "running")
operation Initialize { input: InitializeInput, output: InitializeOutput }

structure InitializeInput { processId: Integer }

structure InitializeOutput { capabilities: String }

@method(name: "shutdown", params: "named", nullResult: true)
@jsonRpcLifecycle(allowedIn: ["running"], onSuccess: "stopping")
operation Shutdown {}

@method(name: "textDocument/hover", params: "named", resultMember: "contents")
@jsonRpcLifecycle(allowedIn: ["running"])
operation Hover { input: HoverInput, output: HoverOutput }

structure HoverInput {
    @required uri: String
    line: Integer
    character: Integer
}

structure HoverOutput { contents: String }

@method(name: "exit", params: "named", nullResult: true)
@jsonRpcLifecycle(onCall: "stopped")
operation Exit {}

@method(name: "workspace/configuration", params: "named", resultMember: "items")
@jsonRpcLifecycle(allowedIn: ["running"])
operation WorkspaceConfiguration { input: ConfigurationInput, output: ConfigurationOutput }

structure ConfigurationInput { section: String }

structure ConfigurationOutput { items: StringList }

list StringList { member: String }

/// The second peer accepts nothing, so it only ever receives replies.
@jsonRpcProtocol(
    versions: ["2.0"]
    peers: [
        { name: "sender", accepts: Sink }
        { name: "listener" }
    ]
)
structure OneWay {}

@jsonRpc(versions: ["2.0"])
service Sink {
    version: "1"
    operations: [Push]
}

@method(name: "push", params: "named", nullResult: true)
operation Push { input: PushInput }

structure PushInput { value: String }
