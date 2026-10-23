///|
pub using @syntax {type SimpleType}

///|
/// A shape's source in the assembled input. JSON paths use JSON Pointer;
/// IDL locations retain the parser's UTF-16 span.
/// The kind tells whether the source holds built-in definitions.
pub(all) struct SourceLocation {
  file : String
  path : String
  span : @syntax.Span?
  kind : SourceKind
} derive(Eq, Debug)

///|
/// Where the definitions of a source come from.
pub(all) enum SourceKind {
  /// A model input that the caller supplies, or a provider default.
  User
  /// Definitions that the loader bundles: the prelude, the contracts, the
  /// protocol test traits and the sources added with Loader::add_builtin_idl.
  BuiltIn
} derive(Eq, Debug)

///|
/// Create a source location. The kind is User unless the caller gives it.
pub fn SourceLocation::new(
  file : String,
  path~ : String = "",
  span? : @syntax.Span,
  kind~ : SourceKind = User,
) -> SourceLocation {
  { file, path, span, kind, }
}

///|
/// Tell whether the location is in a source of built-in definitions. Exports
/// omit the shapes of such a source, and other sources cannot change them.
pub fn SourceLocation::is_builtin(self : SourceLocation) -> Bool {
  self.kind is BuiltIn
}

///|
/// An assembly error. Syntax diagnostics retain their original code and span.
pub(all) struct ModelDiagnostic {
  code : String
  event_id : String
  severity : @syntax.Severity
  message : String
  source : SourceLocation
  shape : ShapeId?
} derive(Eq, Debug)

///|
/// Source declarations and the inherited baseline of an assembled shape.
/// Effective traits and members stay on Shape; provenance distinguishes local
/// overrides, including overrides equal to the inherited value.
pub(all) struct ShapeProvenance {
  introduced_traits : Map[ShapeId, NodeValue]
  inherited_traits : Map[ShapeId, NodeValue]
  introduced_fields : Map[String, NodeValue]
  inherited_fields : Map[String, NodeValue]
  legacy_set : Bool
} derive(Eq, Debug)

///|
/// A shape, including first-class member shapes.
pub(all) struct Shape {
  id : ShapeId
  body : ShapeBody
  traits : Map[ShapeId, NodeValue]
  mixins : Array[ShapeId]
  provenance : ShapeProvenance?
  source : SourceLocation
} derive(Eq, Debug)

///|
/// Traits introduced by this shape, including changes made after assembly.
pub fn Shape::introduced_traits(self : Shape) -> Map[ShapeId, NodeValue] {
  guard self.provenance is Some(origin) && !self.mixins.is_empty() else {
    return self.traits
  }
  let out : Map[ShapeId, NodeValue] = Map([])
  for id, value in self.traits {
    if origin.introduced_traits.contains(id) ||
      origin.inherited_traits.get(id) != Some(value) {
      out[id] = value
    }
  }
  out
}

///|
/// Whether this collection retains the identity of a Smithy 1.0 set.
pub fn Shape::is_legacy_set(self : Shape) -> Bool {
  self.provenance.map(origin => origin.legacy_set).unwrap_or(false)
}

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
  validation_findings : Array[ValidationEvent]
} derive(Debug)

///|
pub fn LoadResult::has_errors(self : LoadResult) -> Bool {
  self.diagnostics.iter().any(d => d.severity == Error)
}
