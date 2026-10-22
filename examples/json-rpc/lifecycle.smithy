$version: "2"
namespace example.lifecycle

use smithy.rpc#jsonRpc
use smithy.rpc#jsonRpcCancels
use smithy.rpc#jsonRpcLifecycle
use smithy.rpc#jsonRpcProtocol
use smithy.rpc#jsonRpcSession
use smithy.rpc#method

/// A MEP-like protocol: the host starts an extension, uses it and stops it.
/// The initialize result advertises the optional capabilities.
@jsonRpcProtocol(
    versions: ["2.0"]
    peers: [
        { name: "host", accepts: Host }
        { name: "extension", accepts: Extension }
    ]
)
@jsonRpcSession(
    states: ["starting", "initializing", "ready", "stopping", "stopped"]
    capabilities: [
        { name: "progress", method: "initialize", pointer: "/capabilities/progress" }
        { name: "cancellation", method: "initialize", pointer: "/capabilities/cancellation" }
    ]
)
structure Lifecycle {}

@jsonRpc(versions: ["2.0"])
service Extension {
    version: "1"
    operations: [Initialize, Initialized, Describe, Ping, Compile, Shutdown, Exit, CancelRequest]
}

@jsonRpc(versions: ["2.0"])
service Host {
    version: "1"
    operations: [Progress]
}

@method(name: "initialize", params: "named")
@jsonRpcLifecycle(allowedIn: ["starting"], onSuccess: "initializing")
operation Initialize { input: InitializeInput, output: InitializeResult }

structure InitializeInput { @required host: String }

structure InitializeResult { @required capabilities: Capabilities }

structure Capabilities {
    progress: Boolean
    cancellation: Boolean
}

@method(name: "initialized", params: "named", nullResult: true)
@jsonRpcLifecycle(allowedIn: ["initializing"], onCall: "ready")
operation Initialized {}

@method(name: "describe", params: "named", resultMember: "name")
@jsonRpcLifecycle(allowedIn: ["starting", "initializing", "ready"])
operation Describe { output: DescribeOutput }

structure DescribeOutput { name: String }

@method(name: "ping", params: "named", nullResult: true)
@jsonRpcLifecycle(allowedIn: ["starting", "initializing", "ready"])
operation Ping {}

@method(name: "compile", params: "named", resultMember: "output")
@jsonRpcLifecycle(allowedIn: ["ready"])
operation Compile { input: CompileInput, output: CompileOutput }

structure CompileInput { @required source: String }

structure CompileOutput { output: String }

@method(name: "shutdown", params: "named", nullResult: true)
@jsonRpcLifecycle(allowedIn: ["ready"], onSuccess: "stopping")
operation Shutdown {}

@method(name: "exit", params: "named", nullResult: true)
@jsonRpcLifecycle(onCall: "stopped")
operation Exit {}

/// The host cancels one of its own calls. The call may then fail with -32800.
@method(name: "$/cancelRequest", params: "named", nullResult: true)
@jsonRpcLifecycle(requires: ["cancellation"])
@jsonRpcCancels(idMember: "id", code: -32800)
operation CancelRequest { input: CancelRequestInput }

structure CancelRequestInput { @required id: Document }

/// The extension reports progress to the host.
@method(name: "progress", params: "named", nullResult: true)
@jsonRpcLifecycle(requires: ["progress"])
operation Progress { input: ProgressInput }

structure ProgressInput { @required message: String }
