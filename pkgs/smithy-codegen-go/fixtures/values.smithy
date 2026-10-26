$version: "2"
namespace example.values

use smithy.rpc#jsonRpc
use smithy.rpc#method
use smithy.rpc#rpcError
use smithy.rpc#unknownMembers

@jsonRpc(versions: ["2.0"])
service Api { version: "1", operations: [Exchange, ReadTime] }

@method(name: "exchange", params: "named", kind: "request")
operation Exchange {
    input: Envelope
    output: Envelope
    errors: [OptionalDetail, RequiredDocumentError]
}

structure Envelope {
    @required list: SparseList
    @required map: SparseMap
    @required strict: Strict
    choice: Choice
    blob: Blob
    document: Document
    docBox: DocBox
    mutual: CycleA
    choiceMap: ChoiceMap
    choiceSparseMap: ChoiceSparseMap
    stringMap: StringMap
    timestamps: TimestampBox
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

map ChoiceMap { key: Choice, value: String }
@sparse
map ChoiceSparseMap { key: Choice, value: String }
map StringMap { key: String, value: String }

structure CycleA { @required b: CycleB }
structure CycleB { a: CycleA }

@error("client")
@rpcError(code: 1010, dataMember: "detail")
structure OptionalDetail { detail: String }

@error("client")
@rpcError(code: 1011, dataMember: "detail")
structure RequiredDocumentError { @required detail: Document }

@timestampFormat("date-time")
timestamp IsoTimestamp

@timestampFormat("epoch-seconds")
timestamp EpochTimestamp

structure TimestampBox {
    plainDefault: Timestamp
    @timestampFormat("date-time")
    memberDate: Timestamp
    targetDate: IsoTimestamp
    @timestampFormat("epoch-seconds")
    memberEpoch: IsoTimestamp
    @timestampFormat("date-time")
    overrideEpoch: EpochTimestamp
    dates: TimestampDates
    epochs: TimestampEpochs
    values: TimestampMap
    tagged: TimestampChoice
}

list TimestampDates { @timestampFormat("date-time") member: Timestamp }
list TimestampEpochs { @timestampFormat("epoch-seconds") member: IsoTimestamp }
map TimestampMap { key: String, @timestampFormat("date-time") value: EpochTimestamp }
union TimestampChoice {
    @timestampFormat("date-time") date: EpochTimestamp
    @timestampFormat("epoch-seconds") epoch: IsoTimestamp
}

@method(name: "time.read", params: "named", kind: "request", resultMember: "at")
operation ReadTime { output: TimeOutput, errors: [TimeError] }
structure TimeOutput { @required @timestampFormat("date-time") at: EpochTimestamp }

@error("client")
@rpcError(code: 1012, dataMember: "detail")
structure TimeError { @required @timestampFormat("epoch-seconds") detail: IsoTimestamp }
