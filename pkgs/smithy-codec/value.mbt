///|
/// A model-aware value, independent of its JSON spelling. Structures hold their present members by Smithy
/// member name, a union names its selected member, and maps hold logical keys. `Object` is a document
/// object, which has no modeled members.
pub(all) enum LogicalValue {
  Null
  Boolean(Bool)
  Number(@smithy.NodeNumber)
  String(String)
  List(Array[LogicalValue])
  Structure(Array[(String, LogicalValue)])
  Union(String, LogicalValue)
  Map(Array[(String, LogicalValue)])
  Object(Array[(String, LogicalValue)])
} derive(Debug)

///|
/// A number from its exact JSON text, such as `12345678901234567890.25`.
pub fn LogicalValue::number(
  text : String,
) -> LogicalValue raise @validation.ConfigurationError {
  match @smithy.NodeNumber::parse(text) {
    Some(n) => Number(n)
    None =>
      raise @validation.ConfigurationError(
        "I expected one exact JSON number token, but found \{text.escape()}.",
      )
  }
}

///|
/// The present member `name` of a structure, the entry `name` of a map or document object.
pub fn LogicalValue::get(self : LogicalValue, name : String) -> LogicalValue? {
  match self {
    Structure(fields) | Map(fields) | Object(fields) => {
      for entry in fields {
        if entry.0 == name {
          return Some(entry.1)
        }
      }
      None
    }
    _ => None
  }
}

///|
/// The selected member of a union value.
pub fn LogicalValue::selected(self : LogicalValue) -> (String, LogicalValue)? {
  match self {
    Union(name, payload) => Some((name, payload))
    _ => None
  }
}

///|
fn sorted_entries(
  fields : Array[(String, LogicalValue)],
) -> Array[(String, LogicalValue)] {
  let out = fields.copy()
  out.sort_by((a, b) => a.0.compare(b.0))
  out
}

///|
/// Semantic equality: numbers compare by exact value; structure members, map entries and document
/// fields compare without regard to order. It uses an explicit stack, not recursion.
pub impl Eq for LogicalValue with fn equal(self, other) {
  let stack : Array[(LogicalValue, LogicalValue)] = [(self, other)]
  while stack.pop() is Some((a, b)) {
    match (a, b) {
      (Null, Null) => ()
      (Boolean(x), Boolean(y)) => if x != y { return false }
      (Number(x), Number(y)) => if x != y { return false }
      (String(x), String(y)) => if x != y { return false }
      (List(xs), List(ys)) => {
        if xs.length() != ys.length() {
          return false
        }
        for i in 0..<xs.length() {
          stack.push((xs[i], ys[i]))
        }
      }
      (Union(m, x), Union(n, y)) => {
        if m != n {
          return false
        }
        stack.push((x, y))
      }
      (Structure(xs), Structure(ys))
      | (Map(xs), Map(ys))
      | (Object(xs), Object(ys)) => {
        if xs.length() != ys.length() {
          return false
        }
        let xs = sorted_entries(xs)
        let ys = sorted_entries(ys)
        for i in 0..<xs.length() {
          if xs[i].0 != ys[i].0 {
            return false
          }
          stack.push((xs[i].1, ys[i].1))
        }
      }
      _ => return false
    }
  }
  true
}

///|
/// The identity of a logical contract: a root shape and the fingerprint of the contract reachable from it.
/// Profiles of one model and root share it; another root or another modeled version does not.
pub struct SemanticRoot {
  shape : @smithy.ShapeId
  fingerprint : String
} derive(Eq, Debug)

///|
pub impl Show for SemanticRoot with fn output(self, logger) {
  logger.write_string(self.shape.to_string() + "@" + self.fingerprint)
}

///|
/// A logical value that a codec has checked against its semantic root. Only decoding and
/// `PreparedCodec::value` create one.
pub struct CodecValue {
  priv root : SemanticRoot
  priv value : LogicalValue
} derive(Debug)

///|
pub fn CodecValue::root(self : CodecValue) -> SemanticRoot {
  self.root
}

///|
pub fn CodecValue::logical(self : CodecValue) -> LogicalValue {
  self.value
}

///|
pub impl Eq for CodecValue with fn equal(self, other) {
  self.root == other.root && self.value == other.value
}
