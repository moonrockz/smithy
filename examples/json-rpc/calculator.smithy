$version: "2"
namespace example

use smithy.rpc#jsonRpc
use smithy.rpc#method

@jsonRpc(versions: ["1.0", "2.0"])
service Calculator {
    version: "1"
    operations: [Subtract, Ping]
}

@method(name: "subtract", params: "either",
    positional: ["minuend", "subtrahend"], resultMember: "value")
operation Subtract { input: SubtractInput, output: SubtractOutput }

structure SubtractInput {
    @required
    minuend: Integer
    @required
    subtrahend: Integer
}

structure SubtractOutput { value: Integer }

@method(name: "ping", params: "either", positional: [], nullResult: true)
operation Ping {}
