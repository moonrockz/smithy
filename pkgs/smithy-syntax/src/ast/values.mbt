///|
/// The exact value of a number literal.
#derive(Eq, Debug)
pub(all) enum NumberValue {
  Integer(BigInt)
  Decimal(@decimal.Decimal)
}

///|
/// A number literal: the lexeme as written and its exact value.
#derive(Eq, Debug)
pub(all) struct NumberLiteral {
  text : String
  value : NumberValue
}

///|
/// The value as an `Int64` when it is an integer that fits.
pub fn NumberLiteral::as_int64(self : NumberLiteral) -> Int64? {
  match self.value {
    Integer(b) =>
      if b >= BigInt::from_int64(-9223372036854775807L - 1L) &&
        b <= BigInt::from_int64(9223372036854775807L) {
        Some(b.to_int64())
      } else {
        None
      }
    Decimal(_) => None
  }
}

///|
/// The value as a `Double` (lossy for large integers and long decimals).
pub fn NumberLiteral::as_double(self : NumberLiteral) -> Double {
  let text = match self.value {
    Integer(b) => b.to_string()
    Decimal(d) => d.to_string()
  }
  // core reports floating-point overflow as a parse error. Our exact value
  // has valid numeric syntax, so overflow converts to signed infinity.
  @string.parse_double(text[:]) catch {
    _ => if text.has_prefix("-") { -1.0 / 0.0 } else { 1.0 / 0.0 }
  }
}

///|
/// The Smithy node keywords: `true`, `false` and `null`.
#derive(Eq, Debug, Hash)
pub(all) enum Keyword {
  True
  False
  Null
}

///|
/// `NodeObjectKvp`: a key (an identifier or a quoted string) and a value.
#derive(Eq, Debug)
pub(all) struct NodeKvp {
  key : Node[String]
  value : NodeValue
  span : @span.Span
}

///|
/// `NodeValue`. Strings hold their decoded value; `ShapeId` is a bare
/// identifier or shape ID in value position (`@foo(bar)`).
#derive(Eq, Debug)
pub(all) enum NodeValue {
  Array(ArrayView[NodeValue], @span.Span)
  Object(ArrayView[NodeKvp], @span.Span)
  Number(NumberLiteral, @span.Span)
  Keyword(Keyword, @span.Span)
  String(String, @span.Span)
  TextBlock(String, @span.Span)
  ShapeId(ShapeId, @span.Span)
}

///|
/// The span of the value, whatever its shape.
pub fn NodeValue::span(self : NodeValue) -> @span.Span {
  match self {
    Array(_, s) | Object(_, s) | Number(_, s) | Keyword(_, s) => s
    String(_, s) | TextBlock(_, s) | ShapeId(_, s) => s
  }
}

///|
/// The string value of a `String` or `TextBlock`, else `None`.
pub fn NodeValue::as_string(self : NodeValue) -> String? {
  match self {
    String(s, _) | TextBlock(s, _) => Some(s)
    _ => None
  }
}

///|
/// The value of `key` in an object, else `None`.
pub fn NodeValue::get(self : NodeValue, key : String) -> NodeValue? {
  guard self is Object(kvps, _) else { return None }
  for kvp in kvps {
    if kvp.key.value == key {
      return Some(kvp.value)
    }
  }
  None
}
