///|
/// A simple (unparameterized) shape type.
pub(all) enum SimpleType {
  Blob
  Boolean
  Document
  String
  Byte
  Short
  Integer
  Long
  Float
  Double
  BigInteger
  BigDecimal
  Timestamp
} derive(Eq, Debug, Hash)

///|
/// The simple type named by a keyword, or `None`.
pub fn SimpleType::of(word : String) -> SimpleType? {
  match word {
    "blob" => Some(Blob)
    "boolean" => Some(Boolean)
    "document" => Some(Document)
    "string" => Some(String)
    "byte" => Some(Byte)
    "short" => Some(Short)
    "integer" => Some(Integer)
    "long" => Some(Long)
    "float" => Some(Float)
    "double" => Some(Double)
    "bigInteger" => Some(BigInteger)
    "bigDecimal" => Some(BigDecimal)
    "timestamp" => Some(Timestamp)
    _ => None
  }
}

///|
/// The keyword that spells this simple type.
pub fn SimpleType::keyword(self : SimpleType) -> String {
  match self {
    Blob => "blob"
    Boolean => "boolean"
    Document => "document"
    String => "string"
    Byte => "byte"
    Short => "short"
    Integer => "integer"
    Long => "long"
    Float => "float"
    Double => "double"
    BigInteger => "bigInteger"
    BigDecimal => "bigDecimal"
    Timestamp => "timestamp"
  }
}

///|
/// `enum` or `intEnum`.
pub(all) enum EnumType {
  Enum
  IntEnum
} derive(Eq, Debug, Hash)

///|
/// `Set` is Smithy 1.0 syntax. The parser reports it in a 2.0 file.
pub(all) enum AggregateType {
  List
  Map
  Union
  Structure
  Set
} derive(Eq, Debug, Hash)

///|
/// `service` or `resource`.
pub(all) enum EntityType {
  Service
  Resource
} derive(Eq, Debug, Hash)

///|
/// Every shape keyword, for recovery and for `ShapeKind` in the CST.
pub(all) enum ShapeKind {
  Simple(SimpleType)
  Enum(EnumType)
  Aggregate(AggregateType)
  Entity(EntityType)
  Operation
} derive(Eq, Debug, Hash)

///|
/// The IDL keyword, for messages and CST names.
pub impl Show for ShapeKind with fn output(self, logger) {
  logger.write_string(self.keyword())
}

///|
/// The keyword that spells this aggregate type.
pub fn AggregateType::keyword(self : AggregateType) -> String {
  match self {
    List => "list"
    Map => "map"
    Union => "union"
    Structure => "structure"
    Set => "set"
  }
}

///|
/// The shape kind a keyword starts, or `None`.
pub fn ShapeKind::of(word : String) -> ShapeKind? {
  match word {
    "enum" => Some(Enum(Enum))
    "intEnum" => Some(Enum(IntEnum))
    "list" => Some(Aggregate(List))
    "map" => Some(Aggregate(Map))
    "union" => Some(Aggregate(Union))
    "structure" => Some(Aggregate(Structure))
    "set" => Some(Aggregate(Set))
    "service" => Some(Entity(Service))
    "resource" => Some(Entity(Resource))
    "operation" => Some(Operation)
    _ => SimpleType::of(word).map(t => Simple(t))
  }
}

///|
/// `with [A, B]`.
pub(all) struct Mixins {
  ids : ArrayView[Node[ShapeId]]
  span : @span.Span
} derive(Eq, Debug)

///|
/// `@id`, `@id(value)` or `@id(key: value, ...)`. `@id()` is
/// `Structure([])`.
pub(all) enum TraitBody {
  Structure(ArrayView[NodeKvp])
  Node(NodeValue)
} derive(Eq, Debug)

///|
/// A single applied trait: `@id` with an optional body.
pub(all) struct Trait {
  id : Node[ShapeId]
  body : TraitBody?
  span : @span.Span
} derive(Eq, Debug)

///|
/// `name: Target` or the elided `$name`.
pub(all) enum MemberTarget {
  Explicit(Node[ShapeId])
  Elided
} derive(Eq, Debug)

///|
/// A member of a structure, union, list or map.
pub(all) struct Member {
  docs : ArrayView[DocComment]
  traits : ArrayView[Trait]
  name : Node[String]
  target : MemberTarget
  default : NodeValue?
  span : @span.Span
} derive(Eq, Debug)

///|
/// A member of an `enum` or `intEnum`.
pub(all) struct EnumMember {
  docs : ArrayView[DocComment]
  traits : ArrayView[Trait]
  name : Node[String]
  value : NodeValue?
  span : @span.Span
} derive(Eq, Debug)

///|
/// `:= { ... }` with its own traits, `for` and mixins.
pub(all) struct InlineShape {
  docs : ArrayView[DocComment]
  traits : ArrayView[Trait]
  for_resource : Node[ShapeId]?
  mixins : Mixins?
  members : ArrayView[Member]
  span : @span.Span
} derive(Eq, Debug)

///|
/// The target of an operation's `input` or `output`: a reference to a
/// shape, or an inline shape defined on the spot.
pub(all) enum OperationTarget {
  Reference(Node[ShapeId])
  Inline(InlineShape)
} derive(Eq, Debug)

///|
/// One property of an `operation` shape: `input`, `output` or `errors`.
pub(all) enum OperationProperty {
  Input(OperationTarget, @span.Span)
  Output(OperationTarget, @span.Span)
  Errors(ArrayView[Node[ShapeId]], @span.Span)
} derive(Eq, Debug)

///|
/// `Shape`, one case per grammar production. `name` is the identifier
/// after the keyword. Member names are unique only when the parse result
/// has no errors; duplicate members survive in a partial AST.
pub(all) enum Shape {
  Simple(kind~ : SimpleType, name~ : Node[String], mixins~ : Mixins?)
  Enum(
    kind~ : EnumType,
    name~ : Node[String],
    mixins~ : Mixins?,
    members~ : ArrayView[EnumMember]
  )
  Aggregate(
    kind~ : AggregateType,
    name~ : Node[String],
    for_resource~ : Node[ShapeId]?,
    mixins~ : Mixins?,
    members~ : ArrayView[Member]
  )
  Entity(
    kind~ : EntityType,
    name~ : Node[String],
    mixins~ : Mixins?,
    body~ : NodeValue
  )
  Operation(
    name~ : Node[String],
    mixins~ : Mixins?,
    properties~ : ArrayView[OperationProperty]
  )
} derive(Eq, Debug)

///|
/// The shape's name.
pub fn Shape::name(self : Shape) -> Node[String] {
  match self {
    Simple(name~, ..) | Enum(name~, ..) | Aggregate(name~, ..) => name
    Entity(name~, ..) | Operation(name~, ..) => name
  }
}

///|
/// The shape's kind.
pub fn Shape::kind(self : Shape) -> ShapeKind {
  match self {
    Simple(kind~, ..) => Simple(kind)
    Enum(kind~, ..) => Enum(kind)
    Aggregate(kind~, ..) => Aggregate(kind)
    Entity(kind~, ..) => Entity(kind)
    Operation(..) => Operation
  }
}

///|
/// The IDL keyword for any shape kind, suitable for printing source.
pub fn ShapeKind::keyword(self : ShapeKind) -> String {
  match self {
    Simple(t) => t.keyword()
    Enum(Enum) => "enum"
    Enum(IntEnum) => "intEnum"
    Aggregate(t) => t.keyword()
    Entity(Service) => "service"
    Entity(Resource) => "resource"
    Operation => "operation"
  }
}
