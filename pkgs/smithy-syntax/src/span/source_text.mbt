///|
/// A source text with its line table. The table is built once; every
/// lookup is a pure function of it.
pub struct SourceText {
  priv text : String
  priv name : String?
  /// The offset of the first unit of each line; `line_starts[0] == 0`.
  priv line_starts : Array[Int32]
} derive(Eq, Debug)

///|
/// LF and CRLF end a line; a lone CR does not.
pub fn SourceText::new(text : String, name? : String) -> SourceText {
  let line_starts = [0]
  for i in 0..<text.length() {
    if text.code_unit_at(i).to_int() == '\n'.to_int() {
      line_starts.push(i + 1)
    }
  }
  { text, name, line_starts, }
}

///|
/// The whole source text.
pub fn SourceText::text(self : SourceText) -> String {
  self.text
}

///|
/// The name given at construction (a file name), if any.
pub fn SourceText::name(self : SourceText) -> String? {
  self.name
}

///|
/// The offset just past the last unit.
pub fn SourceText::end(self : SourceText) -> Offset {
  Offset(self.text.length())
}

///|
/// One more than the number of line breaks.
pub fn SourceText::line_count(self : SourceText) -> Int32 {
  self.line_starts.length()
}

///|
/// The 0-based index of the line that holds `unit` (clamped to the text).
fn SourceText::line_index(self : SourceText, unit : Int32) -> Int32 {
  let mut lo = 0
  let mut hi = self.line_starts.length() - 1
  while lo < hi {
    let mid = lo + (hi - lo + 1) / 2
    if self.line_starts[mid] <= unit {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  lo
}

///|
/// The line and column of `offset`. An offset past the end is the position
/// just after the last unit.
pub fn SourceText::position(self : SourceText, offset : Offset) -> Position {
  let unit = if offset.0 > self.text.length() {
    self.text.length()
  } else {
    offset.0
  }
  let line = self.line_index(unit)
  Position::new(Line(line + 1), Column(unit - self.line_starts[line] + 1))
}

///|
/// The span of a line without its line break; `None` past the last line.
pub fn SourceText::line_span(self : SourceText, line : Line) -> Span? {
  guard line.0 <= self.line_starts.length() else { return None }
  let start = self.line_starts[line.0 - 1]
  let mut end = if line.0 < self.line_starts.length() {
    self.line_starts[line.0]
  } else {
    self.text.length()
  }
  if end > start && self.text.code_unit_at(end - 1).to_int() == '\n'.to_int() {
    end -= 1
    if end > start && self.text.code_unit_at(end - 1).to_int() == '\r'.to_int() {
      end -= 1
    }
  }
  Some(Offset(start).to(Offset(end)))
}

///|
/// The text of a line, without its line break.
pub fn SourceText::line_text(self : SourceText, line : Line) -> String? {
  self.line_span(line).map(s => self.slice(s))
}

///|
/// The text of `span`, clamped to the text.
pub fn SourceText::slice(self : SourceText, span : Span) -> String {
  let n = self.text.length()
  let a = if span.start.0 > n { n } else { span.start.0 }
  let b = if span.end().0 > n { n } else { span.end().0 }
  self.text.unsafe_substring(start=a, end=b)
}
