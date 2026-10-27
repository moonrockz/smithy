$version: "2"

/// Morphir IR version 4: wrapper objects with compact forms.
///
/// Authority: finos/morphir at 5c5307d8. The Morphir Compatibility Kit cases (spec/ir/mck/*.md) win over the
/// JSON Schema (website/static/schemas/morphir-ir-v4.yaml) and the prose pages (spec/ir/mck/README.md). "D<n>"
/// refers to the decisions table in examples/morphir-codecs/COVERAGE.md.
///
/// Readers accept the canonical, compact, expanded and documented legacy spellings; the morphir-v4 writer
/// emits the canonical spelling, and morphir-v4-expanded writes every node in its expanded object form.
/// Legacy spellings that MCK accepts with warning=legacy_spelling are reader aliases and are never written.
/// Empty `attributes` equal absent attributes (emptyAsAbsent), so compact and expanded spellings decode to
/// the same value. Maps keep their member order (D6): MCK compares canonical output byte for byte.
namespace morphir.ir.v4

use smithy.serialization#emptyAsAbsent
use smithy.serialization#jsonEncoding
use smithy.serialization#jsonProfiles
use smithy.serialization#untagged

/// A v4 single-file artifact. Readers accept formatVersion before or after distribution; writers put it first.
@jsonProfiles([
    {
        id: "morphir-v4"
        documentation: "Morphir IR v4 JSON profile: compact canonical writer."
    }
    {
        id: "morphir-v4-expanded"
        documentation: "Morphir IR v4 JSON profile with the expanded writer: no compact forms are written."
        ruleSet: "morphir-v4"
        writer: "expanded"
    }
])
structure IRFile {
    @required
    formatVersion: FormatVersion

    @required
    distribution: Distribution
}

/// Releases 4.0.x. Integer 4 and "4.0.0" are the same release; the writer emits integer 4 for it and the exact
/// string for a later patch (MCK distributions-0001, distributions-0008).
@jsonEncoding(base: { adapter: "morphir.format-version" })
@pattern("^4\\.0\\.(0|[1-9][0-9]*)$")
string FormatVersion

/// {"Library": ...}, {"Specs": ...} or {"Application": ...}. A v3 tagged array is refused
/// (MCK distributions-0003).
union Distribution {
    Library: Library
    Specs: Specs
    Application: Application
}

/// The schema lets a reader omit `dependencies` and `def`; this model requires them, because the canonical
/// writer emits them even when empty (MCK distributions-0002, distributions-0006).
structure Library {
    @required
    packageName: Path

    @required
    dependencies: Dependencies

    @required
    def: PackageDefinition
}

/// A package's public face: `spec`, never `def` (MCK distributions-0006).
structure Specs {
    @required
    packageName: Path

    @required
    dependencies: Dependencies

    @required
    spec: PackageSpecification
}

/// An executable package whose dependencies are package definitions (MCK distributions-0007, 0010).
structure Application {
    @required
    packageName: Path

    @required
    dependencies: ApplicationDependencies

    @required
    def: PackageDefinition

    @required
    entryPoints: EntryPoints
}

@jsonEncoding(
    base: {
        dictionary: { layout: "object", key: "morphir.v4.path", order: "preserve" }
    }
)
map Dependencies {
    key: PathKey
    value: PackageSpecification
}

@jsonEncoding(
    base: {
        dictionary: { layout: "object", key: "morphir.v4.path", order: "preserve" }
    }
)
map ApplicationDependencies {
    key: PathKey
    value: PackageDefinition
}

/// Entry point names are chosen by the author and are not Morphir names.
@jsonEncoding(
    base: {
        dictionary: { layout: "object", order: "preserve" }
    }
)
map EntryPoints {
    key: String
    value: EntryPoint
}

structure EntryPoint {
    @required
    target: FQName

    @required
    kind: EntryPointKind

    doc: String
}

enum EntryPointKind {
    main = "main"
    command = "command"
    handler = "handler"
    job = "job"
    policy = "policy"
}

// ---- Names ----------------------------------------------------------------------------------------------

/// "value-in-USD"; a legacy word array is accepted and normalized (decision 0001).
@jsonEncoding(base: { adapter: "morphir.v4.name" })
string Name

/// "morphir/SDK"; a legacy array of names is accepted.
@jsonEncoding(base: { adapter: "morphir.v4.path" })
string Path

/// "package:module#name"; a legacy [package, module, name] array is accepted (D9).
@jsonEncoding(base: { adapter: "morphir.v4.fqname" })
string FQName

/// The logical key of a Name-keyed object; the dictionary rule validates it with the name adapter.
string NameKey

/// The logical key of a Path-keyed object.
string PathKey

list Names {
    member: Name
}

// ---- Packages and modules -------------------------------------------------------------------------------

structure PackageSpecification {
    @required
    modules: ModuleSpecifications
}

structure PackageDefinition {
    @required
    modules: ModuleDefinitions
}

@jsonEncoding(
    base: {
        dictionary: { layout: "object", key: "morphir.v4.path", order: "preserve" }
    }
)
map ModuleSpecifications {
    key: PathKey
    value: ModuleSpecification
}

@jsonEncoding(
    base: {
        dictionary: { layout: "object", key: "morphir.v4.path", order: "preserve" }
    }
)
map ModuleDefinitions {
    key: PathKey
    value: AccessControlledModuleDefinition
}

/// Canonical {"Public": module}. Also read: the flattened {"access": "Public", "types": ...} and the legacy
/// {"access": "Public", "value": module}, with the access spellings public, pub and private.
@jsonEncoding(
    base: {
        union: {
            style: "external"
            accept: [
                { style: "internal", tag: "access" }
                { style: "adjacent", tag: "access", content: "value" }
            ]
        }
    }
)
union AccessControlledModuleDefinition {
    @jsonEncoding(base: { aliases: ["public", "pub"] })
    Public: ModuleDefinition

    @jsonEncoding(base: { aliases: ["private"] })
    Private: ModuleDefinition
}

/// The schema lets a reader omit `types` and `values`; the canonical writer emits them, so they are required.
/// A module's `doc` is written last (D4, MCK distributions-0004).
structure ModuleDefinition {
    @required
    types: TypeDefinitions

    @required
    values: ValueDefinitions

    doc: String
}

/// `annotations` first, `doc` last (MCK definitions-0022).
structure ModuleSpecification {
    @emptyAsAbsent
    annotations: Annotations

    @required
    types: TypeSpecifications

    @required
    values: ValueSpecifications

    doc: String
}

@jsonEncoding(
    base: {
        dictionary: { layout: "object", key: "morphir.v4.name", order: "preserve" }
    }
)
map TypeDefinitions {
    key: NameKey
    value: AccessControlledTypeDefinition
}

@jsonEncoding(
    base: {
        dictionary: { layout: "object", key: "morphir.v4.name", order: "preserve" }
    }
)
map ValueDefinitions {
    key: NameKey
    value: AccessControlledValueDefinition
}

@jsonEncoding(
    base: {
        dictionary: { layout: "object", key: "morphir.v4.name", order: "preserve" }
    }
)
map TypeSpecifications {
    key: NameKey
    value: DocumentedTypeSpecification
}

@jsonEncoding(
    base: {
        dictionary: { layout: "object", key: "morphir.v4.name", order: "preserve" }
    }
)
map ValueSpecifications {
    key: NameKey
    value: ValueSpecification
}

// ---- Access control and documentation (MCK definitions-0001, 0006, 0017-0019, 0031) ---------------------

/// Canonical {"Public": {"doc": "...", "TypeAliasDefinition": {...}}}. Also read: the flattened
/// {"access": "Public", "doc": ..., "TypeAliasDefinition": ...}, the legacy {"access": "Public", "value": ...}
/// and the access spellings public, pub and private. `priv` is refused (definitions-0031).
@jsonEncoding(
    base: {
        union: {
            style: "external"
            accept: [
                { style: "internal", tag: "access" }
                { style: "adjacent", tag: "access", content: "value" }
            ]
        }
    }
)
union AccessControlledTypeDefinition {
    @jsonEncoding(base: { aliases: ["public", "pub"] })
    Public: DocumentedTypeDefinition

    @jsonEncoding(base: { aliases: ["private"] })
    Private: DocumentedTypeDefinition
}

@jsonEncoding(
    base: {
        union: {
            style: "external"
            accept: [
                { style: "internal", tag: "access" }
                { style: "adjacent", tag: "access", content: "value" }
            ]
        }
    }
)
union AccessControlledValueDefinition {
    @jsonEncoding(base: { aliases: ["public", "pub"] })
    Public: DocumentedValueDefinition

    @jsonEncoding(base: { aliases: ["private"] })
    Private: DocumentedValueDefinition
}

/// `doc` first, beside the definition variant (decision 0010). The nested legacy {"doc", "value"} wrapper is
/// not read (COVERAGE.md gap G3).
structure DocumentedTypeDefinition {
    doc: Doc

    @required
    @jsonEncoding(base: { flatten: true })
    definition: TypeDefinition
}

structure DocumentedValueDefinition {
    doc: Doc

    @required
    @jsonEncoding(base: { flatten: true })
    definition: ValueDefinition
}

structure DocumentedTypeSpecification {
    doc: Doc

    @required
    @jsonEncoding(base: { flatten: true })
    specification: TypeSpecification
}

/// Documentation is one string wherever a node carries it (definitions-0028).
string Doc

// ---- Annotations (MCK definitions-0020 to 0023) ---------------------------------------------------------

list Annotations {
    member: Annotation
}

/// "pkg:mod#local" or "pkg:mod#local:free text", or {"name", "arguments"}.
@untagged
union Annotation {
    compact: AnnotationText
    structured: StructuredAnnotation
}

@pattern("^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*:([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*#([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(:.+)?$")
string AnnotationText

/// `arguments` is omitted when empty.
structure StructuredAnnotation {
    @required
    name: FQName

    @emptyAsAbsent
    arguments: AnnotationArguments
}

list AnnotationArguments {
    member: AnnotationArgument
}

/// A named argument {"name", "value"} or a positional value expression. No value expression is an object with a
/// "name" member, so the field marker tells them apart.
@jsonEncoding(
    base: {
        forms: [
            {
                member: "named"
                read: { kind: "object", field: "name" }
                write: {}
            }
            {
                member: "positional"
                read: { kind: "object", absent: "name" }
                write: {}
            }
            {
                member: "positional"
                read: { kind: "string" }
            }
            {
                member: "positional"
                read: { kind: "number" }
            }
            {
                member: "positional"
                read: { kind: "boolean" }
            }
            {
                member: "positional"
                read: { kind: "array" }
            }
        ]
    }
)
union AnnotationArgument {
    positional: Value
    named: NamedArgument
}

structure NamedArgument {
    @required
    name: Name

    @required
    value: Value
}

// ---- Attributes (decision 0005, MCK types-0009/0010/0012) -----------------------------------------------

structure TypeAttributes {
    source: SourceLocation
    constraints: ExtensionMap
    extensions: ExtensionMap
}

structure ValueAttributes {
    source: SourceLocation
    inferredType: Type
    extensions: ExtensionMap
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

/// Open extension data (`constraints` and `extensions` are JSON objects; types-0012 refuses a number).
@jsonEncoding(
    base: {
        dictionary: { layout: "object", order: "preserve" }
    }
)
map ExtensionMap {
    key: String
    value: Document
}

// ---- Type expressions (MCK types.md) --------------------------------------------------------------------

/// Bare Name -> Variable; bare FQName -> Reference without arguments; bare array -> Tuple. The Name and FQName
/// grammars are disjoint, so the adapter guards decide a bare string (D1, types-0001 to 0004). A parameterized
/// reference keeps its wrapper: a bare ["fq", "a"] is a Tuple (types-0003).
@jsonEncoding(
    base: {
        forms: [
            {
                member: "Variable"
                read: { kind: "string", adapter: "morphir.v4.name" }
                bind: "name"
                write: { empty: ["attributes"] }
            }
            {
                member: "Reference"
                read: { kind: "string", adapter: "morphir.v4.fqname" }
                bind: "fqname"
                write: { empty: ["attributes", "args"] }
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
    ExtensibleRecord: ExtensibleRecordType
    Function: FunctionType
    Unit: UnitType
}

list Types {
    member: Type
}

/// {"Variable": "a"} (schema) or {"Variable": {"attributes", "name"}}.
@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "string" }
                bind: "name"
            }
        ]
    }
)
structure VariableType {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: TypeAttributes

    @required
    name: Name
}

/// {"Reference": "fq"}, {"Reference": ["fq", arg, ...]} (canonical with arguments) or
/// {"Reference": {"attributes", "fqname", "args"}}.
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
                write: { empty: ["attributes"], present: ["args"] }
            }
        ]
    }
)
structure ReferenceType {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: TypeAttributes

    @required
    fqname: FQName

    @emptyAsAbsent
    args: Types
}

@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "array" }
                positions: []
                rest: "elements"
                write: { empty: ["attributes"] }
            }
        ]
    }
)
structure TupleType {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: TypeAttributes

    @required
    elements: Types
}

/// Fields live under `fields` (decision 0004). The direct field map is a legacy reader form (types-0005).
@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "object", absent: "fields" }
                bind: "fields"
            }
        ]
    }
)
structure RecordType {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: TypeAttributes

    @required
    fields: FieldTypes
}

structure ExtensibleRecordType {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: TypeAttributes

    @required
    variable: Name

    @required
    fields: FieldTypes
}

@jsonEncoding(
    base: {
        dictionary: { layout: "object", key: "morphir.v4.name", order: "preserve" }
    }
)
map FieldTypes {
    key: NameKey
    value: Type
}

/// `parameterType` (decision 0007); `argumentType` and `arg`/`result` are legacy reader names (types-0007).
structure FunctionType {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: TypeAttributes

    @required
    @jsonEncoding(base: { aliases: ["argumentType", "arg"] })
    parameterType: Type

    @required
    @jsonEncoding(base: { aliases: ["result"] })
    returnType: Type
}

structure UnitType {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: TypeAttributes
}

// ---- Type specifications and definitions (MCK definitions.md) -------------------------------------------

union TypeSpecification {
    TypeAliasSpecification: TypeAliasSpecification
    OpaqueTypeSpecification: OpaqueTypeSpecification
    CustomTypeSpecification: CustomTypeSpecification
    DerivedTypeSpecification: DerivedTypeSpecification
}

structure TypeAliasSpecification {
    @emptyAsAbsent
    annotations: Annotations

    @required
    typeParams: Names

    @required
    typeExp: Type
}

/// {"OpaqueTypeSpecification": {}} when it has no parameters (definitions-0002).
structure OpaqueTypeSpecification {
    @emptyAsAbsent
    annotations: Annotations

    @emptyAsAbsent
    typeParams: Names
}

/// No `access`: the whole specification is the public face (definitions-0012).
structure CustomTypeSpecification {
    @emptyAsAbsent
    annotations: Annotations

    @required
    typeParams: Names

    @required
    constructors: Constructors
}

structure DerivedTypeSpecification {
    @emptyAsAbsent
    annotations: Annotations

    @required
    typeParams: Names

    @required
    baseType: Type

    @required
    fromBaseType: FQName

    @required
    toBaseType: FQName
}

/// A definition carries no annotations (definitions-0023).
union TypeDefinition {
    TypeAliasDefinition: TypeAliasDefinition
    CustomTypeDefinition: CustomTypeDefinition
    IncompleteTypeDefinition: IncompleteTypeDefinition
}

structure TypeAliasDefinition {
    @required
    typeParams: Names

    @required
    typeExp: Type
}

/// `access` is the visibility of the constructors (definitions-0003).
structure CustomTypeDefinition {
    @required
    typeParams: Names

    access: Access

    @required
    constructors: Constructors
}

enum Access {
    Public
    Private
}

structure IncompleteTypeDefinition {
    @required
    typeParams: Names

    @required
    incompleteness: Incompleteness

    partialTypeExp: Type
}

/// {"just": [["value", "a"]], "nothing": []}; the legacy array of [name, arguments] entries is also read.
@jsonEncoding(
    base: {
        dictionary: { layout: "object", key: "morphir.v4.name", order: "preserve", accept: ["entries"] }
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

/// A Hole says why under `reason` and may keep a partial type (definitions-0014, 0024); Draft has no reason.
union Incompleteness {
    Hole: HoleIncompleteness
    Draft: Empty
}

structure HoleIncompleteness {
    @required
    reason: HoleReason

    partialBody: Type
}

/// A reason is a wrapper object; a bare string is refused (definitions-0026, D15).
union HoleReason {
    UnresolvedReference: UnresolvedReference
    DeletedDuringRefactor: DeletedDuringRefactor
    TypeMismatch: TypeMismatch
}

structure UnresolvedReference {
    @required
    target: FQName
}

structure DeletedDuringRefactor {
    @required
    @jsonName("tx-id")
    txId: String
}

structure TypeMismatch {
    @required
    expected: String

    @required
    found: String
}

structure Empty {}

// ---- Value specifications and definitions ---------------------------------------------------------------

/// `annotations` first, then `doc`, `inputs` (omitted when empty, definitions-0029) and `output`.
structure ValueSpecification {
    @emptyAsAbsent
    annotations: Annotations

    doc: Doc

    @emptyAsAbsent
    inputs: InputTypes

    @required
    output: Type
}

/// Parameters by name in their declared order; the legacy [[name, type], ...] spelling is also read
/// (definitions-0004).
@jsonEncoding(
    base: {
        dictionary: { layout: "object", key: "morphir.v4.name", order: "preserve", accept: ["entries"] }
    }
)
map InputTypes {
    key: NameKey
    value: Type
}

/// The four definition bodies (decision 0008). Native and external operations are bodies, not values.
union ValueDefinition {
    ExpressionBody: ExpressionBody
    NativeBody: NativeBody
    ExternalBody: ExternalBody
    IncompleteBody: IncompleteBody
}

structure ExpressionBody {
    @required
    inputTypes: InputTypes

    @required
    outputType: Type

    @required
    body: Value
}

structure NativeBody {
    @required
    inputTypes: InputTypes

    @required
    outputType: Type

    @required
    nativeInfo: NativeInfo
}

structure NativeInfo {
    @required
    hint: NativeHint

    description: String
}

union NativeHint {
    Arithmetic: Empty
    Comparison: Empty
    StringOp: Empty
    CollectionOp: Empty
    PlatformSpecific: PlatformSpecificHint
}

structure PlatformSpecificHint {
    @required
    platform: String
}

/// `externals` lists one binding per target platform; the platforms must be distinct (definitions-0008),
/// which this model does not check (COVERAGE.md gap G6).
structure ExternalBody {
    @required
    inputTypes: InputTypes

    @required
    outputType: Type

    @required
    externals: ExternalBindings

    body: Value
}

list ExternalBindings {
    member: ExternalBinding
}

structure ExternalBinding {
    @required
    targetPlatform: String

    @required
    externalName: String
}

/// `outputType` is optional; `partialBody` is a value expression (definitions-0016, 0025).
structure IncompleteBody {
    @required
    inputTypes: InputTypes

    outputType: Type

    @required
    incompleteness: Incompleteness

    partialBody: Value
}

// ---- Patterns and literals (MCK patterns-and-literals.md) -----------------------------------------------

/// A bare array is a TuplePattern.
@jsonEncoding(
    base: {
        forms: [
            {
                member: "TuplePattern"
                read: { kind: "array" }
                bind: "patterns"
            }
        ]
    }
)
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

structure WildcardPattern {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes
}

structure AsPattern {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    pattern: Pattern

    @required
    name: Name
}

@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "array" }
                positions: []
                rest: "patterns"
                write: { empty: ["attributes"] }
            }
        ]
    }
)
structure TuplePattern {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    patterns: Patterns
}

structure ConstructorPattern {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    fqname: FQName

    @required
    patterns: Patterns
}

structure EmptyListPattern {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes
}

structure HeadTailPattern {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    head: Pattern

    @required
    tail: Pattern
}

/// {"LiteralPattern": {"IntegerLiteral": 42}}, {"LiteralPattern": 42} or the expanded {"attributes", "literal"}.
/// A document literal cannot be matched (patterns-and-literals-0007).
@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "object", absent: "literal" }
                bind: "literal"
                write: { empty: ["attributes"] }
            }
            {
                read: { kind: "number" }
                bind: "literal"
            }
            {
                read: { kind: "boolean" }
                bind: "literal"
            }
        ]
    }
)
structure LiteralPattern {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    literal: PatternLiteral
}

structure UnitPattern {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes
}

/// The seven literals. A bare boolean is a BoolLiteral; a bare number is an IntegerLiteral when its token is an
/// integer and a FloatLiteral otherwise (decision 0009, D18). WholeNumberLiteral is the v3 name of
/// IntegerLiteral: read, never written.
@jsonEncoding(
    base: {
        forms: [
            {
                member: "BoolLiteral"
                read: { kind: "boolean" }
                bind: "value"
            }
            {
                member: "IntegerLiteral"
                read: { kind: "number", adapter: "morphir.v4.integer-token" }
                bind: "value"
            }
            {
                member: "FloatLiteral"
                read: { kind: "number", adapter: "morphir.v4.float-token" }
                bind: "value"
            }
        ]
    }
)
union Literal {
    BoolLiteral: BoolLiteral
    CharLiteral: CharLiteral
    StringLiteral: StringLiteral

    @jsonEncoding(base: { aliases: ["WholeNumberLiteral"] })
    IntegerLiteral: IntegerLiteral

    FloatLiteral: FloatLiteral
    DecimalLiteral: DecimalLiteral

    /// A schema-less JSON tree kept verbatim, number tokens included (decision 0013).
    DocumentLiteral: Document
}

/// Literal without DocumentLiteral, for patterns.
@jsonEncoding(
    base: {
        forms: [
            {
                member: "BoolLiteral"
                read: { kind: "boolean" }
                bind: "value"
            }
            {
                member: "IntegerLiteral"
                read: { kind: "number", adapter: "morphir.v4.integer-token" }
                bind: "value"
            }
            {
                member: "FloatLiteral"
                read: { kind: "number", adapter: "morphir.v4.float-token" }
                bind: "value"
            }
        ]
    }
)
union PatternLiteral {
    BoolLiteral: BoolLiteral
    CharLiteral: CharLiteral
    StringLiteral: StringLiteral

    @jsonEncoding(base: { aliases: ["WholeNumberLiteral"] })
    IntegerLiteral: IntegerLiteral

    FloatLiteral: FloatLiteral
    DecimalLiteral: DecimalLiteral
}

@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "boolean" }
                bind: "value"
                write: {}
            }
        ]
    }
)
structure BoolLiteral {
    @required
    value: Boolean
}

/// One character, that is one code point (patterns-and-literals-0013).
@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "string" }
                bind: "value"
                write: {}
            }
        ]
    }
)
structure CharLiteral {
    @required
    value: CharText
}

@length(min: 1, max: 1)
string CharText

@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "string" }
                bind: "value"
                write: {}
            }
        ]
    }
)
structure StringLiteral {
    @required
    value: String
}

/// An integer token of any size, written back unchanged (patterns-and-literals-0019, 0020).
@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "number" }
                bind: "value"
                write: {}
            }
        ]
    }
)
structure IntegerLiteral {
    @required
    @jsonEncoding(base: { adapter: "morphir.v4.integer-token" })
    value: BigInteger
}

@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "number" }
                bind: "value"
                write: {}
            }
        ]
    }
)
structure FloatLiteral {
    @required
    value: Double
}

/// A decimal lexeme kept as written (patterns-and-literals-0002, 0016-0018).
@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "string" }
                bind: "value"
                write: {}
            }
        ]
    }
)
structure DecimalLiteral {
    @required
    value: DecimalText
}

@pattern("^[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?$")
string DecimalText

// ---- Value expressions (MCK values.md) ------------------------------------------------------------------

/// Bare Name -> Variable; bare FQName -> Reference; bare boolean or number -> Literal; bare array -> List. A
/// Tuple always keeps its wrapper and a bare string is never a StringLiteral (decision 0009). Writers keep
/// the wrapped forms.
@jsonEncoding(
    base: {
        forms: [
            {
                member: "Variable"
                read: { kind: "string", adapter: "morphir.v4.name" }
                bind: "name"
            }
            {
                member: "Reference"
                read: { kind: "string", adapter: "morphir.v4.fqname" }
                bind: "fqname"
            }
            {
                member: "Literal"
                read: { kind: "boolean" }
                bind: "literal"
            }
            {
                member: "Literal"
                read: { kind: "number" }
                bind: "literal"
            }
            {
                member: "List"
                read: { kind: "array" }
                bind: "items"
            }
        ]
    }
)
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
    Hole: HoleValue
}

list Values {
    member: Value
}

/// {"Literal": {"IntegerLiteral": 42}} (canonical), {"Literal": 42}, or {"Literal": {"attributes", "literal"}}.
/// D3: the canonical writer keeps the typed literal, not the most compact spelling.
@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "object", absent: "literal" }
                bind: "literal"
                write: { empty: ["attributes"] }
            }
            {
                read: { kind: "number" }
                bind: "literal"
            }
            {
                read: { kind: "boolean" }
                bind: "literal"
            }
        ]
    }
)
structure LiteralValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    literal: Literal
}

@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "string" }
                bind: "fqname"
                write: { empty: ["attributes"] }
            }
        ]
    }
)
structure ConstructorValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    fqname: FQName
}

@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "array" }
                positions: []
                rest: "elements"
                write: { empty: ["attributes"] }
            }
        ]
    }
)
structure TupleValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    elements: Values
}

@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "array" }
                positions: []
                rest: "items"
                write: { empty: ["attributes"] }
            }
        ]
    }
)
structure ListValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    items: Values
}

@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "object", absent: "fields" }
                bind: "fields"
            }
        ]
    }
)
structure RecordValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    fields: ValueFields
}

@jsonEncoding(
    base: {
        dictionary: { layout: "object", key: "morphir.v4.name", order: "preserve" }
    }
)
map ValueFields {
    key: NameKey
    value: Value
}

@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "string" }
                bind: "name"
                write: { empty: ["attributes"] }
            }
        ]
    }
)
structure VariableValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    name: Name
}

@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "string" }
                bind: "fqname"
                write: { empty: ["attributes"] }
            }
        ]
    }
)
structure ReferenceValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    fqname: FQName
}

/// `target` and `name`; `subject` and `fieldName` are legacy reader names (values-0006).
structure FieldValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    @jsonEncoding(base: { aliases: ["subject"] })
    target: Value

    @required
    @jsonEncoding(base: { aliases: ["fieldName"] })
    name: Name
}

@jsonEncoding(
    base: {
        forms: [
            {
                read: { kind: "string" }
                bind: "name"
                write: { empty: ["attributes"] }
            }
        ]
    }
)
structure FieldFunctionValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    name: Name
}

structure ApplyValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    function: Value

    @required
    argument: Value
}

structure LambdaValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    pattern: Pattern

    @required
    body: Value
}

/// `name`, `definition` and `in`; `valueName`, `valueDefinition` and `inValue` are legacy reader names
/// (values-0017).
structure LetDefinitionValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    @jsonEncoding(base: { aliases: ["valueName"] })
    name: Name

    @required
    @jsonEncoding(base: { aliases: ["valueDefinition"] })
    definition: ValueDefinition

    @required
    @jsonEncoding(base: { name: "in", aliases: ["inValue"] })
    inValue: Value
}

structure LetRecursionValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    definitions: LetDefinitions

    @required
    @jsonEncoding(base: { name: "in" })
    inValue: Value
}

@jsonEncoding(
    base: {
        dictionary: { layout: "object", key: "morphir.v4.name", order: "preserve" }
    }
)
map LetDefinitions {
    key: NameKey
    value: ValueDefinition
}

structure DestructureValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    pattern: Pattern

    @required
    value: Value

    @required
    @jsonEncoding(base: { name: "in" })
    inValue: Value
}

/// `then` and `else`; `thenBranch` and `elseBranch` are legacy reader names (values-0005).
structure IfThenElseValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    condition: Value

    @required
    @jsonEncoding(base: { name: "then", aliases: ["thenBranch"] })
    thenBranch: Value

    @required
    @jsonEncoding(base: { name: "else", aliases: ["elseBranch"] })
    elseBranch: Value
}

structure PatternMatchValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    value: Value

    @required
    cases: Cases
}

list Cases {
    member: Case
}

structure Case {
    @required
    pattern: Pattern

    @required
    body: Value
}

structure UpdateRecordValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    target: Value

    @required
    fields: ValueFields
}

structure UnitValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes
}

/// A missing expression with its reason and an optional expected type (decision 0008).
structure HoleValue {
    @emptyAsAbsent
    @jsonEncoding(base: { aliases: ["attrs"] })
    attributes: ValueAttributes

    @required
    reason: HoleReason

    expectedType: Type
}
