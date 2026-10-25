$version: "2"

namespace morphir.ir.v4

/// A type expression. Each member is one variant of the tagged union.
union Type {
    Variable: VariableType
    Reference: ReferenceType
    Tuple: TupleType
    Record: RecordType
    ExtensibleRecord: ExtensibleRecordType
    Function: FunctionType
    Unit: UnitType
}

list TypeList {
    member: Type
}

/// Field names to field types.
map FieldMap {
    key: Name
    value: Type
}

structure VariableType {
    attributes: TypeAttributes

    @required
    name: Name
}

structure ReferenceType {
    attributes: TypeAttributes

    @required
    fqname: FQName

    args: TypeList
}

structure TupleType {
    attributes: TypeAttributes

    @required
    elements: TypeList
}

structure RecordType {
    attributes: TypeAttributes

    @required
    fields: FieldMap
}

structure ExtensibleRecordType {
    attributes: TypeAttributes

    @required
    variable: Name

    @required
    fields: FieldMap
}

structure FunctionType {
    attributes: TypeAttributes

    @required
    parameterType: Type

    @required
    returnType: Type
}

structure UnitType {
    attributes: TypeAttributes
}

structure TypeAttributes {
    source: SourceLocation
    constraints: JsonObject
    extensions: JsonObject
}

/// Any JSON object. The schema gives these members only "type: object".
map JsonObject {
    key: String
    value: Document
}

structure SourceLocation {
    @required
    startLine: Integer

    @required
    startColumn: Integer

    @required
    endLine: Integer

    @required
    endColumn: Integer
}

structure Loop {
    @required
    next: Loop
}
