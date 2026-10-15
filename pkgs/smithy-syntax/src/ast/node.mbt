///|
/// A leaf value with its span.
pub(all) struct Node[T] {
  value : T
  span : @span.Span
} derive(Eq, Debug)

///|
/// Pairs a value with the span it was parsed from.
pub fn[T] Node::new(value : T, span : @span.Span) -> Node[T] {
  { value, span, }
}

///|
/// A syntactic, unresolved shape ID: `namespace#name$member`. A relative
/// ID has no namespace; resolution against `use` statements and the
/// prelude is the loader's job.
pub(all) struct ShapeId {
  namespace : String?
  name : String
  member : String?
} derive(Eq, Debug, Hash)

///|
/// Builds a `ShapeId` from its parts.
pub fn ShapeId::new(
  name : String,
  namespace? : String,
  member? : String,
) -> ShapeId {
  { namespace, name, member, }
}

///|
/// Whether the ID carries a namespace.
pub fn ShapeId::is_absolute(self : ShapeId) -> Bool {
  self.namespace is Some(_)
}

///|
/// The ID as written: `ns#name$member`.
pub impl Show for ShapeId with fn output(self, logger) {
  match self.namespace {
    Some(ns) => {
      logger.write_string(ns)
      logger.write_string("#")
    }
    None => ()
  }
  logger.write_string(self.name)
  match self.member {
    Some(m) => {
      logger.write_string("$")
      logger.write_string(m)
    }
    None => ()
  }
}

///|
/// One `///` line, the slashes stripped, the line break not included.
pub(all) struct DocComment {
  text : String
  span : @span.Span
} derive(Eq, Debug)
