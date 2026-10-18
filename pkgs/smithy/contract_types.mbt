///|
/// Shape and literal types expand only one level, when an operation needs them.
/// In particular, recursive Smithy graphs never become recursive sample data.
priv enum ContractType {
  Unknown
  Null
  Boolean
  Number
  String
  Array(Array[ContractType], exact~ : Bool)
  Object(Map[String, ContractType], additional~ : ContractType?, truth~ : Bool?)
  Modeled(ShapeId)
  Constant(Json)
  Reference(@jmespath.Node)
}

///|
fn ContractType::resolve(self : ContractType, model : Model) -> ContractType {
  let mut current = self
  let seen : Set[ShapeId] = Set([])
  while true {
    match current {
      Modeled(id) => {
        if seen.contains(id) {
          return Unknown
        }
        seen.add(id)
        guard model.shapes.get(id) is Some(shape) else { return Unknown }
        match shape.body {
          Member(target~) => current = Modeled(target)
          Simple(Document) => return Unknown
          Simple(Boolean) => return Boolean
          Simple(String | Blob) | Enum(_) => return String
          Simple(_) | IntEnum(_) => return Number
          List(member_) => return Array([Modeled(member_)], exact=false)
          Map(value~, ..) =>
            return Object(Map([]), additional=Some(Modeled(value)), truth=None)
          Structure(members) | Union(members) => {
            let fields : Map[String, ContractType] = Map([])
            for member_ in members {
              if member_.member is Some(name) {
                fields[name] = Modeled(member_)
              }
            }
            return Object(fields, additional=None, truth=None)
          }
          _ => return Unknown
        }
      }
      Constant(value) =>
        return match value {
          Null => Null
          True | False => Boolean
          Number(_, ..) => Number
          String(_) => String
          Array(values) => Array(values.map(v => Constant(v)), exact=true)
          Object(values) => {
            let fields : Map[String, ContractType] = Map([])
            for name, value in values {
              fields[name] = Constant(value)
            }
            Object(fields, additional=None, truth=Some(!fields.is_empty()))
          }
        }
      _ => return current
    }
  } nobreak {
    Unknown
  }
}

///|
fn ContractType::name(self : ContractType, model : Model) -> String {
  match self.resolve(model) {
    Unknown => "unknown"
    Null => "null"
    Boolean => "boolean"
    Number => "number"
    String => "string"
    Array(_, ..) => "array"
    Object(_, ..) => "object"
    Reference(_) => "expression reference"
    Modeled(_) | Constant(_) => "unknown"
  }
}

///|
/// Preserve identical modeled types and common scalar types. Mixed values stay
/// unknown, rather than selecting one fabricated value and rejecting valid data.
fn contract_join(types : Array[ContractType], model : Model) -> ContractType {
  guard !types.is_empty() else { return Unknown }
  let mut result = types[0]
  for i in 1..<types.length() {
    let next = types[i]
    if result is Modeled(a) && next is Modeled(b) && a == b {
      continue
    }
    result = match (result.resolve(model), next.resolve(model)) {
      (Boolean, Boolean) => Boolean
      (Number, Number) => Number
      (String, String) => String
      (Null, Null) => Null
      (Array(a, ..), Array(b, ..)) => Array(a + b, exact=false)
      _ => Unknown
    }
  }
  result
}

///|
fn ContractType::truth(self : ContractType, model : Model) -> Bool? {
  if self is Constant(value) {
    return Some(
      match value {
        Null | False => false
        String(s) => !s.is_empty()
        Array(xs) => !xs.is_empty()
        Object(fields) => !fields.is_empty()
        _ => true
      },
    )
  }
  match self.resolve(model) {
    Null => Some(false)
    Number => Some(true)
    Array(types, exact=true) => Some(!types.is_empty())
    Object(_, truth~, ..) => truth
    _ => None
  }
}

///|
priv enum ContractArgument {
  Value
  Numeric
  Text
  List
  Record
  TextOrList
  Sized
  Numbers
  Strings
  Ordered
  Expression
}

///|
fn ContractArgument::description(self : ContractArgument) -> String {
  match self {
    Value => "a JSON value"
    Numeric => "a number"
    Text => "a string"
    List => "an array"
    Record => "an object"
    TextOrList => "a string or array"
    Sized => "a string, array or object"
    Numbers => "an array of numbers"
    Strings => "an array of strings"
    Ordered => "an array of uniformly numbers or strings"
    Expression => "an expression reference"
  }
}

///|
fn ContractArgument::accepts(
  self : ContractArgument,
  type_ : ContractType,
  model : Model,
) -> Bool {
  let type_ = type_.resolve(model)
  if self is Expression {
    return type_ is Reference(_)
  }
  if type_ is Unknown {
    return true
  }
  match (self, type_) {
    (Expression, Reference(_)) => true
    (_, Reference(_)) | (Expression, _) => false
    (Value, _) => true
    (Numeric, Number)
    | (Text, String)
    | (List, Array(_, ..))
    | (Record, Object(_, ..)) => true
    (TextOrList, String | Array(_, ..))
    | (Sized, String | Array(_, ..) | Object(_, ..)) => true
    (Numbers | Strings | Ordered, Array(types, ..)) => {
      let mut known = ""
      for type_ in types {
        let kind = type_.name(model)
        if kind == "unknown" {
          continue
        }
        if self is Numbers && kind != "number" {
          return false
        }
        if self is Strings && kind != "string" {
          return false
        }
        if self is Ordered {
          if (kind != "number" && kind != "string") ||
            (known != "" && known != kind) {
            return false
          }
          known = kind
        }
      }
      true
    }
    _ => false
  }
}

///|
fn contract_signature(name : String) -> Array[ContractArgument]? {
  match name {
    "abs" | "ceil" | "floor" => Some([Numeric])
    "avg" | "sum" => Some([Numbers])
    "contains" => Some([TextOrList, Value])
    "starts_with" | "ends_with" => Some([Text, Text])
    "join" => Some([Text, Strings])
    "keys" | "values" | "merge" => Some([Record])
    "length" => Some([Sized])
    "map" => Some([Expression, List])
    "max" | "min" | "sort" => Some([Ordered])
    "max_by" | "min_by" | "sort_by" => Some([List, Expression])
    "reverse" => Some([TextOrList])
    "not_null" | "to_array" | "to_number" | "to_string" | "type" =>
      Some([Value])
    _ => None
  }
}
