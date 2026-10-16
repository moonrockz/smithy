///|
/// Construct a document, defaulting to Smithy 2.0. Omitted maps stay absent.
pub fn JsonAst::new(
  smithy~ : String = "2.0",
  metadata? : Map[String, Json],
  shapes? : Map[String, JsonShape],
) -> JsonAst {
  { smithy, metadata, shapes, }
}

///|
/// Construct a reference. The decoder checks absolute ID syntax; the encoder
/// trusts caller-built records and does not validate a semantic model.
pub fn JsonReference::new(target : String) -> JsonReference {
  { target, }
}

///|
/// Construct a member with optional applied traits.
pub fn JsonMember::new(
  target : String,
  traits? : Map[String, Json],
) -> JsonMember {
  { target, traits, }
}

///|
/// Construct a shape. An `Apply` entry must leave `mixins` absent.
pub fn JsonShape::new(
  kind : JsonShapeKind,
  traits? : Map[String, Json],
  mixins? : Array[JsonReference],
) -> JsonShape {
  { kind, traits, mixins, }
}

///|
/// Construct operation properties with absent references by default.
pub fn JsonOperation::new(
  input? : JsonReference,
  output? : JsonReference,
  errors? : Array[JsonReference],
) -> JsonOperation {
  { input, output, errors, }
}

///|
/// Construct service properties with absent fields by default.
pub fn JsonService::new(
  version? : String,
  operations? : Array[JsonReference],
  resources? : Array[JsonReference],
  errors? : Array[JsonReference],
  rename? : Map[String, String],
) -> JsonService {
  { version, operations, resources, errors, rename, }
}

///|
/// Construct resource properties with absent fields by default.
pub fn JsonResource::new(
  identifiers? : Map[String, JsonReference],
  properties? : Map[String, JsonReference],
  create? : JsonReference,
  put? : JsonReference,
  read? : JsonReference,
  update? : JsonReference,
  delete? : JsonReference,
  list? : JsonReference,
  operations? : Array[JsonReference],
  collectionOperations? : Array[JsonReference],
  resources? : Array[JsonReference],
) -> JsonResource {
  {
    identifiers,
    properties,
    create,
    put,
    read,
    update,
    delete,
    list,
    operations,
    collectionOperations,
    resources,
  }
}
