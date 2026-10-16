///|
/// A validated absolute semantic shape ID. Relative IDs belong to the IDL
/// representation and are resolved before they enter the model.
pub struct ShapeId {
  namespace : String
  name : String
  member : String?
} derive(Eq, Debug, Hash)

///|
fn identifier(text : String) -> Bool {
  let mut first = true
  let mut has_alnum = false
  for c in text.iter() {
    let alpha = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    let digit = c >= '0' && c <= '9'
    if !alpha && !digit && c != '_' {
      return false
    }
    if first && digit {
      return false
    }
    has_alnum = has_alnum || alpha || digit
    first = false
  }
  has_alnum
}

///|
pub fn ShapeId::parse(text : String) -> ShapeId? {
  let parts = text.split("#").to_array()
  guard parts.length() == 2 else { return None }
  let namespace = parts[0].to_owned()
  guard namespace.split(".").all(p => identifier(p.to_owned())) else {
    return None
  }
  let names = parts[1].split("$").to_array()
  guard names.length() <= 2 && names.iter().all(p => identifier(p.to_owned())) else {
    return None
  }
  Some({
    namespace,
    name: names[0].to_owned(),
    member: if names.length() == 2 {
      Some(names[1].to_owned())
    } else {
      None
    },
  })
}

///|
pub fn ShapeId::with_member(self : ShapeId, name : String) -> ShapeId? {
  if identifier(name) {
    Some({ ..self, member: Some(name), })
  } else {
    None
  }
}

///|
pub fn ShapeId::root(self : ShapeId) -> ShapeId {
  { ..self, member: None, }
}

///|
pub fn ShapeId::to_string(self : ShapeId) -> String {
  Show::to_string(self)
}

///|
pub impl Show for ShapeId with fn output(self, logger) {
  logger.write_string(self.namespace)
  logger.write_string("#")
  logger.write_string(self.name)
  if self.member is Some(name) {
    logger.write_string("$")
    logger.write_string(name)
  }
}
