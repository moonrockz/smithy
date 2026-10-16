///|
/// An exact JSON number. Equality compares numeric values, not Double
/// approximations or token spellings. No exponent is expanded into zeros.
pub struct NodeNumber {
  text : String
  coefficient : BigInt
  exponent : BigInt
  approximate : Double
} derive(Debug)

///|
pub impl Eq for NodeNumber with fn equal(self, other) {
  self.coefficient == other.coefficient &&
  (self.coefficient == BigInt::from_int(0) || self.exponent == other.exponent)
}

///|
pub fn NodeNumber::parse(text : String) -> NodeNumber? {
  let value = @json.parse(text) catch { _ => return None }
  guard value is Number(approximate, ..) else { return None }
  // Reject surrounding whitespace so text is always exactly one token.
  guard text.trim().to_owned() == text else { return None }
  let parts = text.replace_all(old="E", new="e").split("e").to_array()
  let mantissa = parts[0].to_owned()
  let power = if parts.length() == 2 {
    parts[1].to_owned().trim_start(chars="+").to_owned()
  } else {
    "0"
  }
  let fractional = match mantissa.find(".") {
    Some(at) => mantissa.length() - at - 1
    None => 0
  }
  let digits = mantissa.replace_all(old=".", new="")
  let trimmed = digits.trim_end(chars="0").to_owned()
  let coefficient = if trimmed == "" || trimmed == "-" {
    BigInt::from_int(0)
  } else {
    BigInt::from_string(trimmed)
  }
  let exponent = BigInt::from_string(power) -
    BigInt::from_int(fractional) +
    BigInt::from_int(digits.length() - trimmed.length())
  Some({ text, coefficient, exponent, approximate, })
}

///|
pub impl @json.ToJson for NodeNumber with fn to_json(self) {
  Json::number(self.approximate, repr=self.text)
}

///|
pub(all) suberror NodeError {
  InvalidNode(String)
} derive(Eq, Debug)

///|
/// Source-independent values used for metadata and applied traits.
pub(all) enum NodeValue {
  Null
  Boolean(Bool)
  Number(NodeNumber)
  String(String)
  Array(Array[NodeValue])
  Object(Map[String, NodeValue])
} derive(Eq, Debug)

///|
pub fn NodeValue::from_json(value : Json) -> NodeValue raise NodeError {
  match value {
    Null => Null
    True => Boolean(true)
    False => Boolean(false)
    String(s) => String(s)
    Number(number, repr~) => {
      let text = repr.unwrap_or(number.to_string())
      match NodeNumber::parse(text) {
        Some(n) => Number(n)
        None =>
          raise InvalidNode(
            "I expected a finite JSON number or a valid numeric representation, but found \{text}.",
          )
      }
    }
    Array(values) => Array(values.map(NodeValue::from_json))
    Object(values) => {
      let out : Map[String, NodeValue] = Map([])
      for key, value in values {
        out[key] = NodeValue::from_json(value)
      }
      Object(out)
    }
  }
}

///|
pub impl @json.ToJson for NodeValue with fn to_json(self) {
  match self {
    Null => Json::null()
    Boolean(value) => Json::boolean(value)
    String(value) => Json::string(value)
    Number(value) => @json.to_json(value)
    Array(values) => Json::array(values.map(v => @json.to_json(v)))
    Object(values) => {
      let out : Map[String, Json] = Map([])
      for key, value in values {
        out[key] = @json.to_json(value)
      }
      Json::object(out)
    }
  }
}
