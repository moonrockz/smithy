$version: "2"

namespace morphir.ir.v3

use smithy.serialization#jsonEncoding
use smithy.serialization#jsonProfiles

/// A version 3 type expression. Under the profile morphir-v3, each union is an
/// array that starts with its tag, and the members of the node follow at the
/// positions of their tuple rule.
@jsonProfiles([
    {
        id: "morphir-v3"
        defaults: {
            union: { style: "tagArray" }
        }
    }
])
union Type {
    Variable: VariableType
    Reference: ReferenceType
    Tuple: TupleType
    Record: RecordType
    Function: FunctionType
    Unit: UnitType
}

list Types {
    member: Type
}

/// The attributes of a type node: `{}` in a distribution.
structure Attributes {}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "name"] }
    }
)
structure VariableType {
    @required
    attributes: Attributes

    @required
    name: Name
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "fqName", "typeArguments"] }
    }
)
structure ReferenceType {
    @required
    attributes: Attributes

    @required
    fqName: FQName

    @required
    typeArguments: Types
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "elements"] }
    }
)
structure TupleType {
    @required
    attributes: Attributes

    @required
    elements: Types
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "fields"] }
    }
)
structure RecordType {
    @required
    attributes: Attributes

    @required
    fields: Fields
}

list Fields {
    member: Field
}

structure Field {
    @required
    name: Name

    @required
    tpe: Type
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "argumentType", "returnType"] }
    }
)
structure FunctionType {
    @required
    attributes: Attributes

    @required
    argumentType: Type

    @required
    returnType: Type
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes"] }
    }
)
structure UnitType {
    @required
    attributes: Attributes
}

/// ["value", "in", "u", "s", "d"]: a list of lowercase words.
@jsonEncoding(base: { adapter: "morphir.v3.name" })
string Name

/// [packagePath, modulePath, localName].
@jsonEncoding(base: { adapter: "morphir.v3.fqname" })
string FQName
