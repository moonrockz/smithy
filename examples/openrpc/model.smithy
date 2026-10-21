$version: "2"
namespace example.rpc

use smithy.rpc#jsonRpc
use smithy.rpc#method
use smithy.rpc#rpcError

@title("Calculator")
@documentation("An API described in Smithy and exported as OpenRPC.")
@jsonRpc(versions: ["2.0"])
service Calculator {
    version: "2026-10-21"
    operations: [Subtract, History, Clear]
}

@examples([
    {title: "subtract", input: {minuend: 42, subtrahend: 23}, output: {value: 19}},
    {title: "rejected", input: {minuend: 42}, error: {shapeId: "example.rpc#Problem", content: {detail: "Try again"}}}
])
@method(name: "subtract", params: "either",
    positional: ["minuend", "subtrahend"], resultMember: "value")
operation Subtract { input: Arguments, output: Answer, errors: [Problem] }

structure Arguments {
    @required
    @range(min: 0)
    minuend: Integer
    subtrahend: Integer
}

structure Answer { @range(min: -100, max: 100) value: Integer }

@method(name: "history", params: "named", resultMember: "values")
operation History { output: HistoryOutput }
structure HistoryOutput { values: Values }
list Values { member: Entry }
structure Entry { @required value: Integer, previous: Entry }

@examples([{title: "cleared", input: {}, output: {}}])
@method(name: "clear", params: "positional", positional: [], nullResult: true)
operation Clear {}

@error("client")
@rpcError(code: 1001, dataMember: "detail")
structure Problem { @required @length(min: 2) detail: String }
