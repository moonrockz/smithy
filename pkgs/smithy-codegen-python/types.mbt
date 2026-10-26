///|
/// The module of the embedded runtime, relative to the generated package.
let runtime_module : String = "._runtime"

///|
/// The module of the generated data types.
let models_module : String = ".models"

///|
/// The module of the generated modeled errors.
let errors_module : String = ".errors"

///|
/// The Python type of a shape value, as a Pydantic field annotation.
priv enum Ty {
  Str
  Boolean
  Integer
  Floating
  BigDec
  Blob
  Doc
  Time(String)
  /// A generated class or type alias, and its module.
  Named(String, String)
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
/// The module and the name that a leaf type imports, if any.
fn Ty::leaf_import(self : Ty) -> (String, String)? {
  match self {
    Str => None
    Boolean => Some(("pydantic", "StrictBool"))
    Integer => Some((runtime_module, "BigInteger"))
    Floating => Some((runtime_module, "Double"))
    BigDec => Some((runtime_module, "BigDecimal"))
    Blob => Some((runtime_module, "Blob"))
    Doc => Some((runtime_module, "Document"))
    Time(name) => Some((runtime_module, name))
    Named(name, module_) => Some((module_, name))
    UnitT => Some((runtime_module, "Unit"))
    ListOf(_) | MapOf(_) | Opt(_) => None
  }
}

///|
fn Ty::leaf_text(self : Ty) -> String {
  match self {
    Str => "str"
    ListOf(_) | MapOf(_) | Opt(_) => ""
    leaf =>
      match leaf.leaf_import() {
        Some((_, name)) => name
        None => ""
      }
  }
}

///|
/// The annotation text of the type.
fn Ty::text(self : Ty) -> String {
  let (wrappers, leaf) = self.layers()
  let mut text = leaf.leaf_text()
  for index = wrappers.length() - 1; index >= 0; index = index - 1 {
    text = match wrappers[index] {
      ListOf(_) => "list[\{text}]"
      MapOf(_) => "dict[str, \{text}]"
      _ => "\{text} | None"
    }
  }
  text
}

///|
/// The import that the annotation of the type needs, if any.
fn Ty::import_of(self : Ty) -> (String, String)? {
  let (_, leaf) = self.layers()
  leaf.leaf_import()
}

///|
let unit_id : @smithy.ShapeId = @smithy.ShapeId::parse("smithy.api#Unit").unwrap()

///|
/// The timestamp annotation of each format.
fn timestamp_name(format : String) -> String {
  match format {
    "date-time" => "DateTimeTimestamp"
    "http-date" => "HttpDateTimestamp"
    _ => "EpochSecondsTimestamp"
  }
}

///|
fn prelude_ty(name : String, format : String) -> Ty? {
  match name {
    "String" => Some(Str)
    "Boolean" | "PrimitiveBoolean" => Some(Boolean)
    "Byte"
    | "PrimitiveByte"
    | "Short"
    | "PrimitiveShort"
    | "Integer"
    | "PrimitiveInteger"
    | "Long"
    | "PrimitiveLong"
    | "BigInteger" => Some(Integer)
    "Float" | "PrimitiveFloat" | "Double" | "PrimitiveDouble" => Some(Floating)
    "BigDecimal" => Some(BigDec)
    "Blob" => Some(Blob)
    "Document" => Some(Doc)
    "Timestamp" => Some(Time(timestamp_name(format)))
    "Unit" => Some(UnitT)
    _ => None
  }
}

///|
fn simple_ty(simple : @smithy.SimpleType, format : String) -> Ty {
  match simple {
    String => Str
    Boolean => Boolean
    Byte | Short | Integer | Long | BigInteger => Integer
    Float | Double => Floating
    BigDecimal => BigDec
    Blob => Blob
    Document => Doc
    Timestamp => Time(timestamp_name(format))
  }
}
