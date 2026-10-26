///|
/// The MoonBit type of a shape value, and how the generated code encodes and
/// decodes it.
priv enum Ty {
  Str
  Boolean
  ByteT
  ShortT
  IntT
  Int64T
  FloatT
  DoubleT
  BigDec
  BigInt
  Blob
  Doc
  Time(String)
  Named(String)
  ListOf(Ty)
  MapOf(Ty)
  Opt(Ty)
  UnitT
} derive(Eq, Debug)

///|
/// The wrappers of a type, outer first, and the leaf type inside them. The
/// walk keeps its own state, so a deep type does not recurse.
fn Ty::layers(self : Ty) -> (Array[Ty], Ty) {
  let wrappers : Array[Ty] = []
  let mut ty = self
  for ;; {
    match ty {
      ListOf(inner) | MapOf(inner) | Opt(inner) => {
        wrappers.push(ty)
        ty = inner
      }
      leaf => break (wrappers, leaf)
    }
  }
}

///|
fn Ty::text(self : Ty) -> String {
  let (wrappers, leaf) = self.layers()
  let mut text = leaf.leaf_text()
  for index = wrappers.length() - 1; index >= 0; index = index - 1 {
    text = match wrappers[index] {
      ListOf(_) => "Array[\{text}]"
      MapOf(_) => "Map[String, \{text}]"
      _ => "\{text}?"
    }
  }
  text
}

///|
fn Ty::leaf_text(self : Ty) -> String {
  match self {
    Str => "String"
    Boolean => "Bool"
    ByteT | ShortT | IntT => "Int"
    Int64T => "Int64"
    FloatT => "Float"
    DoubleT => "Double"
    BigDec => "@rpc.Decimal"
    BigInt => "@rpc.BigInteger"
    Blob => "Bytes"
    Doc => "Json"
    Time(_) => "@rpc.Timestamp"
    Named(name) => name
    UnitT => "Unit"
    ListOf(_) | MapOf(_) | Opt(_) => ""
  }
}

///|
fn Ty::leaf_encode(self : Ty, expr : String) -> String {
  match self {
    Str => "Json::string(\{expr})"
    Boolean => "Json::boolean(\{expr})"
    ByteT | ShortT | IntT => "Json::number(\{expr}.to_double())"
    Int64T => "@rpc.encode_int64(\{expr})"
    FloatT => "@rpc.encode_float(\{expr})"
    DoubleT => "@rpc.encode_double(\{expr})"
    BigDec | BigInt | Time(_) | Named(_) => "\{expr}.to_json()"
    Blob => "@rpc.encode_blob(\{expr})"
    Doc => expr
    UnitT => "Json::empty_object()"
    ListOf(_) | MapOf(_) | Opt(_) => expr
  }
}

///|
/// The expression that encodes `expr` as a `Json` value. Each inner layer
/// names its value `item`.
fn Ty::encode(self : Ty, expr : String) -> String {
  let (wrappers, leaf) = self.layers()
  if wrappers.is_empty() {
    return leaf.leaf_encode(expr)
  }
  let mut text = leaf.leaf_encode("item")
  for index = wrappers.length() - 1; index >= 0; index = index - 1 {
    let value = if index == 0 { expr } else { "item" }
    text = match wrappers[index] {
      ListOf(_) => "@rpc.encode_array(\{value}, item => \{text})"
      MapOf(_) => "@rpc.encode_map(\{value}, item => \{text})"
      _ => "match \{value} { Some(item) => \{text}; None => Json::null() }"
    }
  }
  text
}

///|
fn Ty::leaf_decode(self : Ty, json : String, path : String) -> String {
  match self {
    Str => "@rpc.decode_string(\{json}, path=\{path})"
    Boolean => "@rpc.decode_bool(\{json}, path=\{path})"
    ByteT => "@rpc.decode_byte(\{json}, path=\{path})"
    ShortT => "@rpc.decode_short(\{json}, path=\{path})"
    IntT => "@rpc.decode_int(\{json}, path=\{path})"
    FloatT => "@rpc.decode_float(\{json}, path=\{path})"
    Int64T => "@rpc.decode_int64(\{json}, path=\{path})"
    DoubleT => "@rpc.decode_double(\{json}, path=\{path})"
    BigDec => "@rpc.Decimal::from_json(\{json}, path=\{path})"
    BigInt => "@rpc.BigInteger::from_json(\{json}, path=\{path})"
    Time(format) =>
      "@rpc.Timestamp::from_json(\{json}, format=@rpc.\{format}, path=\{path})"
    Blob => "@rpc.decode_blob(\{json}, path=\{path})"
    Doc => json
    UnitT => "()"
    Named(name) => "\{name}::from_json(\{json}, path=\{path})"
    ListOf(_) | MapOf(_) | Opt(_) => json
  }
}

///|
/// The expression that decodes `json` at the JSON Pointer expression `path`.
/// A list or map layer names its item `item` and the item path `path`.
fn Ty::decode(self : Ty, json : String, path : String) -> String {
  let (wrappers, leaf) = self.layers()
  // The value and the path expression of each layer; the leaf is the last.
  let values = [json]
  let paths = [path]
  for index, wrapper in wrappers {
    values.push("item")
    paths.push(if wrapper is Opt(_) { paths[index] } else { "path" })
  }
  let depth = wrappers.length()
  let mut text = leaf.leaf_decode(values[depth], paths[depth])
  for index = depth - 1; index >= 0; index = index - 1 {
    let label = if text.contains("path") { "path" } else { "_path" }
    text = match wrappers[index] {
      ListOf(_) =>
        "@rpc.decode_array(\{values[index]}, path=\{paths[index]}, (item, \{label}) => \{text})"
      MapOf(_) =>
        "@rpc.decode_map(\{values[index]}, path=\{paths[index]}, (item, \{label}) => \{text})"
      _ => "match \{values[index]} { Null => None; item => Some(\{text}) }"
    }
  }
  text
}

///|
let unit_id : @smithy.ShapeId = @smithy.ShapeId::parse("smithy.api#Unit").unwrap()

///|
fn prelude_ty(name : String, format : String) -> Ty? {
  match name {
    "String" => Some(Str)
    "Boolean" | "PrimitiveBoolean" => Some(Boolean)
    "Byte" | "PrimitiveByte" => Some(ByteT)
    "Short" | "PrimitiveShort" => Some(ShortT)
    "Integer" | "PrimitiveInteger" => Some(IntT)
    "Long" | "PrimitiveLong" => Some(Int64T)
    "Float" | "PrimitiveFloat" => Some(FloatT)
    "Double" | "PrimitiveDouble" => Some(DoubleT)
    "BigInteger" => Some(BigInt)
    "BigDecimal" => Some(BigDec)
    "Blob" => Some(Blob)
    "Document" => Some(Doc)
    "Timestamp" => Some(Time(format))
    "Unit" => Some(UnitT)
    _ => None
  }
}

///|
fn simple_ty(simple : @smithy.SimpleType, format : String) -> Ty {
  match simple {
    String => Str
    Boolean => Boolean
    Byte => ByteT
    Short => ShortT
    Integer => IntT
    Long => Int64T
    Float => FloatT
    Double => DoubleT
    BigInteger => BigInt
    BigDecimal => BigDec
    Blob => Blob
    Document => Doc
    Timestamp => Time(format)
  }
}
