$version: "2"
namespace example.values

use smithy.rpc#jsonRpc
use smithy.rpc#method
use smithy.rpc#unknownMembers

@jsonRpc(versions: ["2.0"])
service Api { version: "1", operations: [Exchange] }

@method(name: "exchange", params: "named", kind: "request")
operation Exchange { input: Envelope, output: Envelope }

structure Envelope {
    @required list: SparseList
    @required map: SparseMap
    @required strict: Strict
    choice: Choice
    blob: Blob
    document: Document
    docBox: DocBox
    mutual: CycleA
}

structure DocBox { @required value: Document }

@sparse
list SparseList { member: String }

@sparse
map SparseMap { key: String, value: String }

@unknownMembers("reject")
structure Strict { @required text: String }

enum Choice {
    YES = "yes"
    NO = "no"
}

structure CycleA { @required b: CycleB }
structure CycleB { a: CycleA }
