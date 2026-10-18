///|
pub using @syntax {type SimpleType}

///|
/// A shape's source in the assembled input. JSON paths use JSON Pointer;
/// IDL locations retain the parser's UTF-16 span.
pub(all) struct SourceLocation {
  file : String
  path : String
  span : @syntax.Span?
} derive(Eq, Debug)

///|
/// An assembly error. Syntax diagnostics retain their original code and span.
pub(all) struct ModelDiagnostic {
  code : String
  severity : @syntax.Severity
  message : String
  source : SourceLocation
  shape : ShapeId?
} derive(Eq, Debug)

///|
/// A shape, including first-class member shapes.
pub(all) struct Shape {
  id : ShapeId
  body : ShapeBody
  traits : Map[ShapeId, NodeValue]
  mixins : Array[ShapeId]
  source : SourceLocation
} derive(Eq, Debug)

///|
pub(all) enum ShapeBody {
  Simple(SimpleType)
  List(ShapeId)
  Map(key~ : ShapeId, value~ : ShapeId)
  Structure(Array[ShapeId])
  Union(Array[ShapeId])
  Enum(Array[ShapeId])
  IntEnum(Array[ShapeId])
  Member(target~ : ShapeId)
  Operation(input~ : ShapeId, output~ : ShapeId, errors~ : Array[ShapeId])
  Service(
    version~ : String,
    operations~ : Array[ShapeId],
    resources~ : Array[ShapeId],
    errors~ : Array[ShapeId],
    rename~ : Map[ShapeId, String]
  )
  Resource(
    identifiers~ : Map[String, ShapeId],
    properties~ : Map[String, ShapeId],
    create~ : ShapeId?,
    put~ : ShapeId?,
    read~ : ShapeId?,
    update~ : ShapeId?,
    delete~ : ShapeId?,
    list~ : ShapeId?,
    operations~ : Array[ShapeId],
    collectionOperations~ : Array[ShapeId],
    resources~ : Array[ShapeId]
  )
} derive(Eq, Debug)

///|
pub fn ShapeBody::keyword(self : ShapeBody) -> String {
  match self {
    Simple(t) => t.keyword()
    List(_) => "list"
    Map(..) => "map"
    Structure(_) => "structure"
    Union(_) => "union"
    Enum(_) => "enum"
    IntEnum(_) => "intEnum"
    Member(..) => "member"
    Operation(..) => "operation"
    Service(..) => "service"
    Resource(..) => "resource"
  }
}

///|
/// A graph of semantic shapes and metadata. Assembly includes built-in prelude
/// and contract definitions; serialization omits them unless explicitly requested.
pub(all) struct Model {
  shapes : Map[ShapeId, Shape]
  metadata : Map[String, NodeValue]
} derive(Eq, Debug)

///|
pub fn Model::get(self : Model, id : String) -> Shape? {
  ShapeId::parse(id).bind(id => self.shapes.get(id))
}

///|
pub fn Shape::trait_value(self : Shape, id : String) -> NodeValue? {
  ShapeId::parse(id).bind(id => self.traits.get(id))
}

///|
/// Failed assembly never returns a partially validated model.
pub(all) struct LoadResult {
  model : Model?
  diagnostics : Array[ModelDiagnostic]
} derive(Debug)

///|
pub fn LoadResult::has_errors(self : LoadResult) -> Bool {
  self.diagnostics.iter().any(d => d.severity == Error)
}
