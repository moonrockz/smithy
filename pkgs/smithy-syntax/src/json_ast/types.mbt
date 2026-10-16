///|
/// A Smithy JSON AST document. Optional fields distinguish absence from an
/// explicitly empty object. Metadata and trait values retain core JSON number
/// representations, including integers beyond Double's exact range.
pub(all) struct JsonAst {
  smithy : String
  metadata : Map[String, Json]?
  shapes : Map[String, JsonShape]?
} derive(Eq, Debug)

///|
/// An absolute shape reference. Reference existence and target kinds are
/// checked by the semantic loader, not by the JSON codec.
pub(all) struct JsonReference {
  target : String
} derive(Eq, Debug)

///|
/// A member definition with an absolute target and optional applied traits.
pub(all) struct JsonMember {
  target : String
  traits : Map[String, Json]?
} derive(Eq, Debug)

///|
/// A shape definition, or an `apply` entry. `Apply` permits traits only;
/// decoding rejects a mixins property on an apply entry.
pub(all) struct JsonShape {
  kind : JsonShapeKind
  traits : Map[String, Json]?
  mixins : Array[JsonReference]?
} derive(Eq, Debug)

///|
/// Shape-specific JSON fields. Collections and named-member shapes can omit
/// members that a mixin supplies. Required members, nonempty unions/enums and
/// other model constraints are the semantic loader's responsibility.
pub(all) enum JsonShapeKind {
  Simple(@ast.SimpleType)
  List(JsonMember?)
  Set(JsonMember?)
  Map(key~ : JsonMember?, value~ : JsonMember?)
  Structure(Map[String, JsonMember]?)
  Union(Map[String, JsonMember]?)
  Enum(Map[String, JsonMember]?)
  IntEnum(Map[String, JsonMember]?)
  Operation(JsonOperation)
  Service(JsonService)
  Resource(JsonResource)
  Apply
} derive(Eq, Debug)

///|
/// An operation's references. Mixins and traits live on the containing shape.
pub(all) struct JsonOperation {
  input : JsonReference?
  output : JsonReference?
  errors : Array[JsonReference]?
} derive(Eq, Debug)

///|
/// A service's properties. A version can be inherited from a mixin.
pub(all) struct JsonService {
  version : String?
  operations : Array[JsonReference]?
  resources : Array[JsonReference]?
  errors : Array[JsonReference]?
  rename : Map[String, String]?
} derive(Eq, Debug)

///|
/// A resource's properties. Field spelling follows the Smithy JSON AST.
pub(all) struct JsonResource {
  identifiers : Map[String, JsonReference]?
  properties : Map[String, JsonReference]?
  create : JsonReference?
  put : JsonReference?
  read : JsonReference?
  update : JsonReference?
  delete : JsonReference?
  list : JsonReference?
  operations : Array[JsonReference]?
  collectionOperations : Array[JsonReference]?
  resources : Array[JsonReference]?
} derive(Eq, Debug)

///|
/// The Smithy JSON AST type discriminator.
pub fn JsonShapeKind::keyword(self : JsonShapeKind) -> String {
  match self {
    Simple(t) => t.keyword()
    List(_) => "list"
    Set(_) => "set"
    Map(..) => "map"
    Structure(_) => "structure"
    Union(_) => "union"
    Enum(_) => "enum"
    IntEnum(_) => "intEnum"
    Operation(_) => "operation"
    Service(_) => "service"
    Resource(_) => "resource"
    Apply => "apply"
  }
}
