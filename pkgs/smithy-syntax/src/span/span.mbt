///|
/// A half-open range of a source text: `start` included, `length` units.
/// Built from a length, so the end never precedes the start.
pub(all) struct Span {
  start : Offset
  length : Length
} derive(Eq, Debug, Hash)

///|
/// The span of `length` units starting at `start`.
pub fn Span::new(start : Offset, length : Length) -> Span {
  { start, length, }
}

///|
/// The offset just past the last unit of the span.
pub fn Span::end(self : Span) -> Offset {
  self.start.advance(self.length)
}

///|
/// Whether `offset` lies inside the span (the end is excluded).
pub fn Span::contains(self : Span, offset : Offset) -> Bool {
  self.start <= offset && offset < self.end()
}

///|
/// Whether the span covers no units.
pub fn Span::is_empty(self : Span) -> Bool {
  self.length == Length::zero()
}

///|
/// The smallest span that covers both.
pub fn Span::join(self : Span, other : Span) -> Span {
  let start = if self.start < other.start { self.start } else { other.start }
  let end = if self.end() > other.end() { self.end() } else { other.end() }
  start.to(end)
}

///|
/// A 1-based line and column.
pub(all) struct Position {
  line : Line
  column : Column
} derive(Eq, Debug, Hash)

///|
/// The position at `line` and `column`.
pub fn Position::new(line : Line, column : Column) -> Position {
  { line, column, }
}
