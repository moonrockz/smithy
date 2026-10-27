$version: "2"

/// Morphir IR version 3: the classic tagged-array JSON written by morphir-elm.
///
/// Authority: finos/morphir-elm at bc99af69 (src/Morphir/IR/**/Codec.elm, vendored under
/// examples/morphir-codecs/upstream/finos-morphir-elm), with the v3.1 Specs distribution and the formatVersion
/// contract from finos/morphir at 5c5307d8. "D<n>" refers to the decisions table of the wire reference
/// (examples/morphir-codecs/COVERAGE.md lists them with the cases they affect).
///
/// Every union is a tag-first array under the morphir-v3 profile. A structure that follows a tag declares its
/// array positions with a tuple rule; its member order is the Elm argument order. Dictionaries are arrays of
/// [key, value] entries, written in Elm Dict order (lexicographic word lists).
///
/// Strictness decisions (D11): arrays have exactly the positions Elm writes (the v3 schema's minItems and
/// maxItems), objects have no unknown members, duplicate dictionary keys are refused, type attributes are the
/// empty object `{}`, and a CharLiteral has exactly one character. morphir-elm itself is more lenient: it
/// ignores extra positions and members, keeps the last duplicate key and reads any type attribute.
namespace morphir.ir.v3

use smithy.serialization#jsonEncoding
use smithy.serialization#jsonProfiles

/// A v3.0 single-file artifact: formatVersion 3 (or "3.0.x") and a Library distribution.
@jsonProfiles([
    {
        id: "morphir-v3"
        documentation: "Morphir IR v3 JSON as written by morphir-elm: tag-first arrays and entry-array dictionaries."
        defaults: {
            union: { style: "tagArray" }
        }
    }
])
structure IRFile30 {
    @required
    formatVersion: FormatVersion30

    @required
    distribution: Distribution30
}

/// A v3.1 single-file artifact. 3.1.0 adds the Specs distribution (finos/morphir
/// docs/spec/ir/schemas/v3/whats-new.md). A Specs distribution with release 3 or "3.0.x" is selected by the
/// v3.0 binding, whose distribution union has no Specs member, so it is refused (specs_before_3_1).
structure IRFile31 {
    @required
    formatVersion: FormatVersion31

    @required
    distribution: Distribution31
}

/// Releases 3.0.x. The adapter normalizes integer 3 and "3.0.0" to "3.0.0" and writes integer 3 for it.
@jsonEncoding(base: { adapter: "morphir.format-version" })
@pattern("^3\\.0\\.(0|[1-9][0-9]*)$")
string FormatVersion30

/// Releases 3.1.x, always written as the exact string (D14: the decoded release is kept).
@jsonEncoding(base: { adapter: "morphir.format-version" })
@pattern("^3\\.1\\.(0|[1-9][0-9]*)$")
string FormatVersion31

union Distribution30 {
    Library: Library
}

union Distribution31 {
    Library: Library
    Specs: Specs
}

/// ["Library", packageName, dependencies, packageDefinition] (Distribution/Codec.elm:52-99).
@jsonEncoding(
    base: {
        tuple: { members: ["packageName", "dependencies", "definition"] }
    }
)
structure Library {
    @required
    packageName: Path

    @required
    dependencies: Dependencies

    @required
    definition: PackageDefinition
}

/// ["Specs", packageName, dependencies, packageSpecification] (v3.1).
@jsonEncoding(
    base: {
        tuple: { members: ["packageName", "dependencies", "specification"] }
    }
)
structure Specs {
    @required
    packageName: Path

    @required
    dependencies: Dependencies

    @required
    specification: PackageSpecification
}

// ---- Names ----------------------------------------------------------------------------------------------

/// ["value", "in", "u", "s", "d"]; the logical text joins the words with "-".
@jsonEncoding(base: { adapter: "morphir.v3.name" })
string Name

/// [["morphir"], ["s", "d", "k"]]; the logical text joins the names with "/".
@jsonEncoding(base: { adapter: "morphir.v3.path" })
string Path

/// [packagePath, modulePath, localName]; the logical text is "package:module#name".
@jsonEncoding(base: { adapter: "morphir.v3.fqname" })
string FQName

/// The logical key of a Name-keyed dictionary. The dictionary rule names the key adapter.
string NameKey

/// The logical key of a Path-keyed dictionary.
string PathKey

list Names {
    member: Name
}

// ---- Access control and documentation -------------------------------------------------------------------

/// "Public" or "Private" (AccessControlled/Codec.elm:28-62).
enum Access {
    Public
    Private
}

// ---- Packages and modules -------------------------------------------------------------------------------

@jsonEncoding(
    base: {
        dictionary: { layout: "entries", key: "morphir.v3.path", order: "adapter" }
    }
)
map Dependencies {
    key: PathKey
    value: PackageSpecification
}

/// {"modules": [[modulePath, moduleSpecification], ...]} (Package/Codec.elm:48-79).
structure PackageSpecification {
    @required
    modules: ModuleSpecifications
}

@jsonEncoding(
    base: {
        dictionary: { layout: "entries", key: "morphir.v3.path", order: "adapter" }
    }
)
map ModuleSpecifications {
    key: PathKey
    value: ModuleSpecification
}

/// {"modules": [[modulePath, {"access", "value": moduleDefinition}], ...]} (Package/Codec.elm:84-115).
structure PackageDefinition {
    @required
    modules: ModuleDefinitions
}

@jsonEncoding(
    base: {
        dictionary: { layout: "entries", key: "morphir.v3.path", order: "adapter" }
    }
)
map ModuleDefinitions {
    key: PathKey
    value: AccessControlledModuleDefinition
}

structure AccessControlledModuleDefinition {
    @required
    access: Access

    @required
    value: ModuleDefinition
}

/// Module/Codec.elm:34-87. `doc` is written as null when absent and read as absent when null or missing.
structure ModuleSpecification {
    @required
    types: TypeSpecifications

    @required
    values: ValueSpecifications

    @jsonEncoding(base: { absent: "null" })
    doc: String
}

/// Module/Codec.elm:90-143.
structure ModuleDefinition {
    @required
    types: TypeDefinitions

    @required
    values: ValueDefinitions

    @jsonEncoding(base: { absent: "null" })
    doc: String
}

@jsonEncoding(
    base: {
        dictionary: { layout: "entries", key: "morphir.v3.name", order: "adapter" }
    }
)
map TypeSpecifications {
    key: NameKey
    value: DocumentedTypeSpecification
}

@jsonEncoding(
    base: {
        dictionary: { layout: "entries", key: "morphir.v3.name", order: "adapter" }
    }
)
map ValueSpecifications {
    key: NameKey
    value: DocumentedValueSpecification
}

@jsonEncoding(
    base: {
        dictionary: { layout: "entries", key: "morphir.v3.name", order: "adapter" }
    }
)
map TypeDefinitions {
    key: NameKey
    value: AccessControlledTypeDefinition
}

@jsonEncoding(
    base: {
        dictionary: { layout: "entries", key: "morphir.v3.name", order: "adapter" }
    }
)
map ValueDefinitions {
    key: NameKey
    value: AccessControlledValueDefinition
}

/// {"doc", "value"} (Documented/Codec.elm:25-41). D12: Elm writes this wrapper with a string doc. It also reads
/// an unwrapped value with doc "", which this model refuses, as the v3 schema does.
structure DocumentedTypeSpecification {
    @required
    doc: String

    @required
    value: TypeSpecification
}

structure DocumentedValueSpecification {
    @required
    doc: String

    @required
    value: ValueSpecification
}

structure AccessControlledTypeDefinition {
    @required
    access: Access

    @required
    value: DocumentedTypeDefinition
}

structure DocumentedTypeDefinition {
    @required
    doc: String

    @required
    value: TypeDefinition
}

structure AccessControlledValueDefinition {
    @required
    access: Access

    @required
    value: DocumentedValueDefinition
}

structure DocumentedValueDefinition {
    @required
    doc: String

    @required
    value: ValueDefinition
}

// ---- Types (Type/Codec.elm) -----------------------------------------------------------------------------

/// The attributes of a type node. Distributions fix them to Unit, which Elm writes as `{}`.
structure Attributes {}

/// The attributes of a value or pattern node: a v3 Type in a distribution (Distribution/Codec.elm:65-95) or
/// `{}` in a standalone node (MCK versions-0001). The JSON kinds differ, so the union is untagged.
@jsonEncoding(
    profiles: {
        "morphir-v3": {
            union: { style: "untagged" }
        }
    }
)
union ValueAttributes {
    empty: Attributes
    typed: Type
}

/// Type/Codec.elm:31-146.
union Type {
    Variable: VariableType
    Reference: ReferenceType
    Tuple: TupleType
    Record: RecordType
    ExtensibleRecord: ExtensibleRecordType
    Function: FunctionType
    Unit: UnitType
}

list Types {
    member: Type
}

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

/// ["Reference", attributes, fqName, typeArguments]; the argument list is always written.
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

/// Record fields are an ordered list of {"name", "tpe"} objects (MCK versions-0008).
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

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "variableName", "fields"] }
    }
)
structure ExtensibleRecordType {
    @required
    attributes: Attributes

    @required
    variableName: Name

    @required
    fields: Fields
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

list Fields {
    member: Field
}

structure Field {
    @required
    name: Name

    @required
    tpe: Type
}

/// Type/Codec.elm:165-240.
union TypeSpecification {
    TypeAliasSpecification: TypeAliasSpecification
    OpaqueTypeSpecification: OpaqueTypeSpecification
    CustomTypeSpecification: CustomTypeSpecification
    DerivedTypeSpecification: DerivedTypeSpecification
}

@jsonEncoding(
    base: {
        tuple: { members: ["typeParams", "typeExp"] }
    }
)
structure TypeAliasSpecification {
    @required
    typeParams: Names

    @required
    typeExp: Type
}

@jsonEncoding(
    base: {
        tuple: { members: ["typeParams"] }
    }
)
structure OpaqueTypeSpecification {
    @required
    typeParams: Names
}

@jsonEncoding(
    base: {
        tuple: { members: ["typeParams", "constructors"] }
    }
)
structure CustomTypeSpecification {
    @required
    typeParams: Names

    @required
    constructors: Constructors
}

/// ["DerivedTypeSpecification", params, {"baseType", "fromBaseType", "toBaseType"}] (MCK versions-0007).
@jsonEncoding(
    base: {
        tuple: { members: ["typeParams", "config"] }
    }
)
structure DerivedTypeSpecification {
    @required
    typeParams: Names

    @required
    config: DerivedTypeConfig
}

structure DerivedTypeConfig {
    @required
    baseType: Type

    @required
    fromBaseType: FQName

    @required
    toBaseType: FQName
}

/// Type/Codec.elm:244-280.
union TypeDefinition {
    TypeAliasDefinition: TypeAliasDefinition
    CustomTypeDefinition: CustomTypeDefinition
}

@jsonEncoding(
    base: {
        tuple: { members: ["typeParams", "typeExp"] }
    }
)
structure TypeAliasDefinition {
    @required
    typeParams: Names

    @required
    typeExp: Type
}

@jsonEncoding(
    base: {
        tuple: { members: ["typeParams", "constructors"] }
    }
)
structure CustomTypeDefinition {
    @required
    typeParams: Names

    @required
    constructors: AccessControlledConstructors
}

structure AccessControlledConstructors {
    @required
    access: Access

    @required
    value: Constructors
}

/// [[constructorName, [[argumentName, type], ...]], ...] in Elm Dict order of constructor names; the argument
/// list keeps its order (Type/Codec.elm:283-317).
@jsonEncoding(
    base: {
        dictionary: { layout: "entries", key: "morphir.v3.name", order: "adapter" }
    }
)
map Constructors {
    key: NameKey
    value: ConstructorArguments
}

list ConstructorArguments {
    member: ConstructorArgument
}

@jsonEncoding(
    base: {
        tuple: { members: ["name", "type"] }
    }
)
structure ConstructorArgument {
    @required
    name: Name

    @required
    type: Type
}

// ---- Literals (Literal/Codec.elm) -----------------------------------------------------------------------

/// ["BoolLiteral", true], ["WholeNumberLiteral", 42], ["DecimalLiteral", "10.50"] ... Number tokens are kept:
/// Elm writes a whole FloatLiteral without a point, for example ["FloatLiteral", 100].
union Literal {
    BoolLiteral: Boolean
    CharLiteral: CharText
    StringLiteral: String
    WholeNumberLiteral: BigInteger
    FloatLiteral: Double
    DecimalLiteral: DecimalText
}

/// One character (the v3 schema's minLength/maxLength 1; Elm keeps the first character of a longer string).
@length(min: 1, max: 1)
string CharText

/// Decimal.toString text (MCK versions-0006 keeps "10.50"). The v3 schema pattern.
@pattern("^-?[0-9]+(\\.[0-9]+)?$")
string DecimalText

// ---- Patterns (Value/Codec.elm:350-464) -----------------------------------------------------------------

union Pattern {
    WildcardPattern: WildcardPattern
    AsPattern: AsPattern
    TuplePattern: TuplePattern
    ConstructorPattern: ConstructorPattern
    EmptyListPattern: EmptyListPattern
    HeadTailPattern: HeadTailPattern
    LiteralPattern: LiteralPattern
    UnitPattern: UnitPattern
}

list Patterns {
    member: Pattern
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes"] }
    }
)
structure WildcardPattern {
    @required
    attributes: ValueAttributes
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "pattern", "name"] }
    }
)
structure AsPattern {
    @required
    attributes: ValueAttributes

    @required
    pattern: Pattern

    @required
    name: Name
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "elements"] }
    }
)
structure TuplePattern {
    @required
    attributes: ValueAttributes

    @required
    elements: Patterns
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "constructorName", "arguments"] }
    }
)
structure ConstructorPattern {
    @required
    attributes: ValueAttributes

    @required
    constructorName: FQName

    @required
    arguments: Patterns
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes"] }
    }
)
structure EmptyListPattern {
    @required
    attributes: ValueAttributes
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "head", "tail"] }
    }
)
structure HeadTailPattern {
    @required
    attributes: ValueAttributes

    @required
    head: Pattern

    @required
    tail: Pattern
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "literal"] }
    }
)
structure LiteralPattern {
    @required
    attributes: ValueAttributes

    @required
    literal: Literal
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes"] }
    }
)
structure UnitPattern {
    @required
    attributes: ValueAttributes
}

// ---- Values (Value/Codec.elm:30-347) --------------------------------------------------------------------

union Value {
    Literal: LiteralValue
    Constructor: ConstructorValue
    Tuple: TupleValue
    List: ListValue
    Record: RecordValue
    Variable: VariableValue
    Reference: ReferenceValue
    Field: FieldValue
    FieldFunction: FieldFunctionValue
    Apply: ApplyValue
    Lambda: LambdaValue
    LetDefinition: LetDefinitionValue
    LetRecursion: LetRecursionValue
    Destructure: DestructureValue
    IfThenElse: IfThenElseValue
    PatternMatch: PatternMatchValue
    UpdateRecord: UpdateRecordValue
    Unit: UnitValue
}

list Values {
    member: Value
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "literal"] }
    }
)
structure LiteralValue {
    @required
    attributes: ValueAttributes

    @required
    literal: Literal
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "name"] }
    }
)
structure ConstructorValue {
    @required
    attributes: ValueAttributes

    @required
    name: FQName
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "elements"] }
    }
)
structure TupleValue {
    @required
    attributes: ValueAttributes

    @required
    elements: Values
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "items"] }
    }
)
structure ListValue {
    @required
    attributes: ValueAttributes

    @required
    items: Values
}

/// Record value fields are a Dict: [[name, value], ...] in Elm order.
@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "fields"] }
    }
)
structure RecordValue {
    @required
    attributes: ValueAttributes

    @required
    fields: ValueFields
}

@jsonEncoding(
    base: {
        dictionary: { layout: "entries", key: "morphir.v3.name", order: "adapter" }
    }
)
map ValueFields {
    key: NameKey
    value: Value
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "name"] }
    }
)
structure VariableValue {
    @required
    attributes: ValueAttributes

    @required
    name: Name
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "name"] }
    }
)
structure ReferenceValue {
    @required
    attributes: ValueAttributes

    @required
    name: FQName
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "subject", "fieldName"] }
    }
)
structure FieldValue {
    @required
    attributes: ValueAttributes

    @required
    subject: Value

    @required
    fieldName: Name
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "fieldName"] }
    }
)
structure FieldFunctionValue {
    @required
    attributes: ValueAttributes

    @required
    fieldName: Name
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "function", "argument"] }
    }
)
structure ApplyValue {
    @required
    attributes: ValueAttributes

    @required
    function: Value

    @required
    argument: Value
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "argumentPattern", "body"] }
    }
)
structure LambdaValue {
    @required
    attributes: ValueAttributes

    @required
    argumentPattern: Pattern

    @required
    body: Value
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "valueName", "valueDefinition", "inValue"] }
    }
)
structure LetDefinitionValue {
    @required
    attributes: ValueAttributes

    @required
    valueName: Name

    @required
    valueDefinition: ValueDefinition

    @required
    inValue: Value
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "valueDefinitions", "inValue"] }
    }
)
structure LetRecursionValue {
    @required
    attributes: ValueAttributes

    @required
    valueDefinitions: LetDefinitions

    @required
    inValue: Value
}

@jsonEncoding(
    base: {
        dictionary: { layout: "entries", key: "morphir.v3.name", order: "adapter" }
    }
)
map LetDefinitions {
    key: NameKey
    value: ValueDefinition
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "pattern", "valueToDestruct", "inValue"] }
    }
)
structure DestructureValue {
    @required
    attributes: ValueAttributes

    @required
    pattern: Pattern

    @required
    valueToDestruct: Value

    @required
    inValue: Value
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "condition", "thenBranch", "elseBranch"] }
    }
)
structure IfThenElseValue {
    @required
    attributes: ValueAttributes

    @required
    condition: Value

    @required
    thenBranch: Value

    @required
    elseBranch: Value
}

/// Cases are an ordered list of [pattern, body] pairs, not a dictionary.
@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "branchOutOn", "cases"] }
    }
)
structure PatternMatchValue {
    @required
    attributes: ValueAttributes

    @required
    branchOutOn: Value

    @required
    cases: Cases
}

list Cases {
    member: Case
}

@jsonEncoding(
    base: {
        tuple: { members: ["pattern", "body"] }
    }
)
structure Case {
    @required
    pattern: Pattern

    @required
    body: Value
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes", "valueToUpdate", "fieldsToUpdate"] }
    }
)
structure UpdateRecordValue {
    @required
    attributes: ValueAttributes

    @required
    valueToUpdate: Value

    @required
    fieldsToUpdate: ValueFields
}

@jsonEncoding(
    base: {
        tuple: { members: ["attributes"] }
    }
)
structure UnitValue {
    @required
    attributes: ValueAttributes
}

// ---- Value specifications and definitions (Value/Codec.elm:467-530) -------------------------------------

/// {"inputs": [[name, type], ...], "output": type}; inputs keep their order.
structure ValueSpecification {
    @required
    inputs: InputSpecifications

    @required
    output: Type
}

list InputSpecifications {
    member: InputSpecification
}

@jsonEncoding(
    base: {
        tuple: { members: ["name", "type"] }
    }
)
structure InputSpecification {
    @required
    name: Name

    @required
    type: Type
}

/// {"inputTypes": [[name, attributes, type], ...], "outputType", "body"}.
structure ValueDefinition {
    @required
    inputTypes: InputTypes

    @required
    outputType: Type

    @required
    body: Value
}

list InputTypes {
    member: InputType
}

@jsonEncoding(
    base: {
        tuple: { members: ["name", "attributes", "type"] }
    }
)
structure InputType {
    @required
    name: Name

    @required
    attributes: ValueAttributes

    @required
    type: Type
}
