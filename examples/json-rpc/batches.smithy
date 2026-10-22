$version: "2"
namespace batch

use smithy.rpc#jsonRpc
use smithy.rpc#jsonRpcProtocol
use smithy.rpc#method

/// The JSON-RPC 2.0 section 7 batch examples as a transcript: the client calls and the server replies.
@jsonRpcProtocol(versions: ["2.0"], peers: [{name: "client"}, {name: "server", accepts: Api}])
structure Link {}

@jsonRpc(versions: ["1.0", "2.0"])
service Api { version: "1", operations: [Sum, Subtract, NotifyHello, NotifySum, GetData, Ping] }

@method(name: "sum", params: "either", positional: ["a", "b", "c"], resultMember: "value")
operation Sum { input: Three, output: NumberOutput }
structure Three { @required a: Integer, @required b: Integer, @required c: Integer }
structure NumberOutput { value: Integer }

@method(name: "subtract", params: "either", positional: ["minuend", "subtrahend"], resultMember: "value")
operation Subtract { input: SubtractInput, output: NumberOutput }
structure SubtractInput { @required minuend: Integer, @required subtrahend: Integer }

@method(name: "notify_hello", params: "either", positional: ["value"], nullResult: true)
operation NotifyHello { input: One }
structure One { @required value: Integer }

@method(name: "notify_sum", params: "either", positional: ["a", "b", "c"], nullResult: true)
operation NotifySum { input: Three }

@method(name: "get_data", params: "either", positional: [], resultMember: "value")
operation GetData { output: AnyOutput }
structure AnyOutput { value: Document }

@method(name: "ping", params: "either", positional: [], nullResult: true)
operation Ping {}
