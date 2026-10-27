$version: "2"

namespace morphir.ir.v4

use smithy.serialization#jsonEncoding
use smithy.serialization#jsonProfiles

/// A type expression. The profile morphir-v4 also reads the compact spellings:
/// a bare name is a type variable, a bare FQName is a reference, and a bare
/// array is a tuple.
@jsonProfiles([
    {
        id: "morphir-v4"
    }
])
@jsonEncoding(
    base: {
        forms: [
            {
                member: "Variable"
                read: { kind: "string", adapter: "morphir.v4.name" }
                bind: "name"
                write: {}
            }
            {
                member: "Reference"
                read: { kind: "string", adapter: "morphir.v4.fqname" }
                bind: "fqname"
                write: { empty: ["args"] }
            }
            {
                member: "Tuple"
                read: { kind: "array" }
                bind: "elements"
            }
        ]
    }
)
union Type {
    Variable: VariableType
    Reference: ReferenceType
    Tuple: TupleType
    Record: RecordType
    Unit: UnitType
}

list Types {
    member: Type
}

structure VariableType {
    @required
    name: Name
}

/// {"Reference": "fq"} and {"Reference": ["fq", argument, ...]} are compact
/// forms of this structure.
@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "string" }
                bind: "fqname"
            }
            {
                read: { kind: "array" }
                positions: ["fqname"]
                rest: "args"
                write: { present: ["args"] }
            }
        ]
    }
)
structure ReferenceType {
    @required
    fqname: FQName

    args: Types
}

structure TupleType {
    @required
    elements: Types
}

structure RecordType {
    @required
    fields: FieldMap
}

@jsonEncoding(
    base: {
        dictionary: { layout: "object", key: "morphir.v4.name", order: "preserve" }
    }
)
map FieldMap {
    key: String
    value: Type
}

structure UnitType {}

/// "value-in-USD". The adapter also reads the old word array ["value", "in", "u", "s", "d"].
@jsonEncoding(base: { adapter: "morphir.v4.name" })
string Name

/// "package:module#name".
@jsonEncoding(base: { adapter: "morphir.v4.fqname" })
string FQName
