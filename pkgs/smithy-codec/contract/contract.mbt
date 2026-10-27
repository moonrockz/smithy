///|
/// A preparation refusal. Each case names the shape whose declaration is refused.
pub(all) suberror ContractError {
  UnknownProfile(ProfileId)
  UnknownBundle(BundleId)
  InvalidTarget(@smithy.ShapeId, String)
  InvalidDeclaration(@smithy.ShapeId, String)
  UnsupportedDeclaration(@smithy.ShapeId, String)
  ConflictingDeclaration(@smithy.ShapeId, String)
  MissingAdapter(@smithy.ShapeId, AdapterId)
  PreparationLimit(@smithy.ShapeId, String)
} derive(Debug)

///|
pub fn ContractError::message(self : ContractError) -> String {
  match self {
    UnknownProfile(id) =>
      "I expected a declared serialization profile, but found no profile \{id}."
    UnknownBundle(id) =>
      "I expected a declared document bundle, but found no bundle \{id}."
    InvalidTarget(id, message)
    | InvalidDeclaration(id, message)
    | UnsupportedDeclaration(id, message)
    | ConflictingDeclaration(id, message)
    | PreparationLimit(id, message) => id.to_string() + ": " + message
    MissingAdapter(id, adapter) =>
      id.to_string() +
      ": I expected the host to register scalar adapter \{adapter}, but it is not registered."
  }
}

///|
/// The code of a refusal, used in structured diagnostics.
pub fn ContractError::code(self : ContractError) -> String {
  match self {
    UnknownProfile(_) => "UnknownProfile"
    UnknownBundle(_) => "UnknownBundle"
    InvalidTarget(_, _) => "InvalidTarget"
    InvalidDeclaration(_, _) => "InvalidDeclaration"
    UnsupportedDeclaration(_, _) => "UnsupportedDeclaration"
    ConflictingDeclaration(_, _) => "ConflictingDeclaration"
    MissingAdapter(_, _) => "MissingAdapter"
    PreparationLimit(_, _) => "PreparationLimit"
  }
}

///|
/// What a host adapter declares: the JSON kinds that it reads, the logical scalar kind that it produces
/// and whether it orders dictionary keys.
pub struct AdapterSignature {
  id : AdapterId
  inputs : Array[JsonKind]
  output : JsonKind
  orders_keys : Bool
} derive(Eq, Debug)

///|
pub fn AdapterSignature::new(
  id : AdapterId,
  inputs~ : Array[JsonKind],
  output~ : JsonKind,
  orders_keys~ : Bool = false,
) -> AdapterSignature raise IdentityError {
  guard !inputs.is_empty() else {
    raise InvalidIdentity(
      "AdapterSignature", "I expected at least one input JSON kind.",
    )
  }
  guard output is (StringKind | NumberKind | BooleanKind) else {
    raise InvalidIdentity(
      "AdapterSignature", "I expected a string, number or boolean output kind.",
    )
  }
  { id, inputs: inputs.copy(), output, orders_keys, }
}

///|
pub(all) enum WriterMode {
  Canonical
  Expanded
} derive(Eq, Debug)

///|
pub(all) enum UnknownMemberPolicy {
  RejectUnknown
  IgnoreUnknown
} derive(Eq, Debug)

///|
pub(all) enum OptionalTail {
  OmitTail
  NullTail
} derive(Eq, Debug)

///|
/// One member of a structure, union, list or map, with its effective wire decisions.
pub struct MemberContract {
  /// The Smithy member name: the logical identity.
  name : String
  member_id : @smithy.ShapeId
  target : @smithy.ShapeId
  required : Bool
  /// The field name in object layouts.
  wire : WireName
  /// Reader-only field names.
  aliases : Array[WireName]
  /// The tag of a union member.
  tag : WireName
  adapter : AdapterId?
  empty_as_absent : Bool
  /// Written as null when absent; a null input means absent.
  null_when_absent : Bool
  /// The member's external union is read from the fields that no other member claims.
  flatten : Bool
} derive(Debug)

///|
pub(all) enum UnionLayout {
  External
  Internal(tag~ : WireName)
  Adjacent(tag~ : WireName, content~ : WireName)
  TagArray(tag_only_unit~ : Bool)
  /// The member index selected by each accepted JSON kind.
  Untagged(Array[(JsonKind, Int32)])
} derive(Debug)

///|
/// Fixed member positions and an optional final rest list, as member indexes.
pub struct TupleLayout {
  fixed : Array[Int32]
  rest : Int32?
  optional : OptionalTail?
} derive(Debug)

///|
pub(all) enum KeyOrder {
  LexicalKeys
  AdapterKeys
  PreservedKeys
} derive(Eq, Debug)

///|
pub struct DictionaryLayout {
  entries : Bool
  /// Readers also accept the other layout.
  accept_other : Bool
  key_adapter : AdapterId?
  order : KeyOrder
} derive(Debug)

///|
pub(all) enum FormBinding {
  /// The whole JSON value is the given member. -1 means the payload itself.
  Whole(Int32)
  Positional(fixed~ : Array[Int32], rest~ : Int32?)
} derive(Debug)

///|
pub struct ReaderGuard {
  kind : JsonKind
  adapter : AdapterId?
  field : WireName?
  absent : WireName?
} derive(Debug)

///|
/// A writer uses the form when every `empty` member is absent or empty and every `present` member is
/// present and not empty.
pub struct WriterGuard {
  empty : Array[Int32]
  present : Array[Int32]
} derive(Debug)

///|
/// A compact form. A union form selects `member` and binds fields of its payload; a structure form binds
/// fields of the structure itself.
pub struct Form {
  union_member : Int32?
  reader : ReaderGuard
  binding : FormBinding
  writer : WriterGuard?
} derive(Debug)

///|
pub(all) enum ShapeLayout {
  ObjectStructure
  TupleStructure(TupleLayout)
  UnionShape(UnionLayout)
  ListShape
  Dictionary(DictionaryLayout)
  Scalar(AdapterId?)
} derive(Debug)

///|
pub(all) enum ShapeKind {
  StructureKind
  UnionKind
  ListKind
  MapKind
  SimpleKind(@smithy.SimpleType)
  EnumKind
  IntEnumKind
} derive(Eq, Debug)

///|
pub struct ShapeContract {
  id : @smithy.ShapeId
  kind : ShapeKind
  /// Structure and union members in declaration order; the member of a list; the key and value of a map.
  members : Array[MemberContract]
  layout : ShapeLayout
  /// Reader-only alternative union layouts.
  accepts : Array[UnionLayout]
  /// A sparse list or map: a null element or value is kept as null.
  sparse : Bool
  forms : Array[Form]
} derive(Debug)

///|
pub fn ShapeContract::member_index(
  self : ShapeContract,
  name : String,
) -> Int32? {
  for i, m in self.members {
    if m.name == name {
      return Some(i)
    }
  }
  None
}

///|
/// The detached wire contract of one root under one profile. It holds no reference to the source model.
pub struct WireContract {
  root : @smithy.ShapeId
  profile : ProfileId?
  writer : WriterMode
  unknown_members : UnknownMemberPolicy
  /// The identity of the logical contract. Profiles of one model and root share it.
  fingerprint : String
  shapes : Map[@smithy.ShapeId, ShapeContract]
} derive(Debug)

///|
pub fn WireContract::shape(
  self : WireContract,
  id : @smithy.ShapeId,
) -> ShapeContract? {
  self.shapes.get(id)
}
