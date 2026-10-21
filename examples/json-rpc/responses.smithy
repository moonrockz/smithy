$version: "2"
namespace example

use smithy.rpc#jsonRpc
use smithy.rpc#method
use smithy.rpc#rpcError

@jsonRpc(versions: ["1.0", "2.0"])
service Replies {
    version: "1"
    operations: [Subtract, GetData, GetObject, Ping, Echo, PostMessage]
}

@method(name: "subtract", params: "either",
    positional: ["minuend", "subtrahend"], resultMember: "value")
operation Subtract { input: SubtractInput, output: SubtractOutput, errors: [Problem] }
structure SubtractInput { @required minuend: Integer, @required subtrahend: Integer }
structure SubtractOutput { @range(min: -20, max: 20) value: Integer }

@error("client")
@rpcError(code: 1001, dataMember: "detail")
structure Problem { @required @length(min: 2) detail: String }

@method(name: "get_data", params: "either", positional: [], resultMember: "items")
operation GetData { output: DataOutput }
list Items { member: Document }
structure DataOutput { @length(min: 2) items: Items }

@method(name: "get_object", params: "either", positional: [])
operation GetObject { output: ObjectOutput }
structure ObjectOutput { @required count: Integer }

@method(name: "ping", params: "either", positional: [], nullResult: true)
operation Ping {}

@method(name: "echo", params: "either", positional: ["message"], resultMember: "message")
operation Echo { input: EchoInput, output: EchoOutput }
structure EchoInput { @required message: String }
structure EchoOutput { message: String }

@method(name: "postMessage", params: "either", positional: ["message"], resultMember: "value")
operation PostMessage { input: EchoInput, output: PostOutput }
structure PostOutput { value: Integer }
