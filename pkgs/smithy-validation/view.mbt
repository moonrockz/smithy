///|
/// Read one value without copying or converting its descendants.
pub(open) trait ValueView {
  fn inspect(Self) -> ValueNode[Self]
  /// Non-allocating count of immediate wrappers or annotations inspect may expand.
  /// Adapters that allocate per child override this before exposing wide values.
  fn expansion_size(Self) -> Int32 = _
  /// The value's own source path relative to the validation base path. A projected view returns the
  /// original location of a synthetic node, such as a tuple position; the default derives it from the parent.
  fn source(Self) -> InstancePath? = _
}

///|
impl ValueView with fn expansion_size(_self) {
  0
}

///|
impl ValueView with fn source(_self) {
  None
}

///|
pub(all) enum NativeKind {
  NullKind
  BoolKind
  IntKind
  FloatKind
  DecimalKind
  TimestampKind
  SymbolKind
  StringKind
  BlobKind
  ClobKind
  StructKind
  ListKind
  SexpKind
} derive(Eq, Debug)

///|
pub(all) enum NativeScalar {
  TypedNull(NativeKind)
  Float(Double)
  Decimal(@smithy.NodeNumber)
  Timestamp(NativeTimestamp)
  InvalidTimestamp
  Symbol(String?)
  Blob(Bytes)
  Clob(Bytes)
} derive(Debug)

///|
pub struct LocatedField[V] {
  name : String
  value : V
  source : InstancePath
}

///|
pub fn[V] LocatedField::new(
  name : String,
  value : V,
  source : InstancePath,
) -> LocatedField[V] {
  { name, value, source, }
}

///|
pub(all) enum ValueNode[V] {
  Null
  Boolean(Bool)
  Number(@smithy.NodeNumber)
  InvalidNumber
  String(String)
  Array(Array[V])
  Object(Array[(String, V)])
  NativeObject(Array[(String?, V)])
  LocatedObject(Array[LocatedField[V]])
  Native(NativeScalar)
  Sexp(Array[V])
  Annotated(Array[String?], V)
}

///|
pub impl ValueView for Json with fn inspect(self) {
  match self {
    Null => Null
    True => Boolean(true)
    False => Boolean(false)
    String(s) => String(s)
    Number(n, repr~) =>
      match @smithy.NodeNumber::parse(repr.unwrap_or(n.to_string())) {
        Some(number) => Number(number)
        None => InvalidNumber
      }
    Array(values) => Array(values)
    Object(fields) => {
      let names = fields.keys().to_array()
      names.sort_by((a, b) => a.lexical_compare(b))
      Object(names.map(name => (name, fields.get(name).unwrap())))
    }
  }
}

///|
pub impl ValueView for @smithy.NodeValue with fn inspect(self) {
  match self {
    Null => Null
    Boolean(b) => Boolean(b)
    Number(n) => Number(n)
    String(s) => String(s)
    Array(values) => Array(values)
    Object(fields) => {
      let names = fields.keys().to_array()
      names.sort_by((a, b) => a.lexical_compare(b))
      Object(names.map(name => (name, fields.get(name).unwrap())))
    }
  }
}
