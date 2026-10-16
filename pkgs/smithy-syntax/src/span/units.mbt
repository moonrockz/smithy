///|
/// A UTF-16 unit index into a source text. Never negative: `Offset::new`
/// is the only way in from an `Int`.
pub struct Offset(Int32) derive(Eq, Compare, Hash, Debug)

///|
/// The offset `n`, or `None` when `n` is negative.
pub fn Offset::new(n : Int32) -> Offset? {
  if n < 0 {
    None
  } else {
    Some(Offset(n))
  }
}

///|
/// The offset of the first unit of a text.
pub fn Offset::zero() -> Offset {
  Offset(0)
}

///|
/// `Add` is homogeneous in MoonBit, so stepping an offset by a length is a
/// named method.
pub fn Offset::advance(self : Offset, by : Length) -> Offset {
  Offset(self.0 + by.0)
}

///|
/// The offset one unit after `self`.
pub fn Offset::next(self : Offset) -> Offset {
  Offset(self.0 + 1)
}

///|
/// The number of units between two offsets, in either order.
pub fn Offset::distance(self : Offset, other : Offset) -> Length {
  if other.0 >= self.0 {
    Length(other.0 - self.0)
  } else {
    Length(self.0 - other.0)
  }
}

///|
/// The span from `self` to `end`, ordered either way.
pub fn Offset::to(self : Offset, end : Offset) -> Span {
  if end.0 >= self.0 {
    { start: self, length: Length(end.0 - self.0), }
  } else {
    { start: end, length: Length(self.0 - end.0), }
  }
}

///|
/// A count of UTF-16 units. Never negative.
pub struct Length(Int32) derive(Eq, Compare, Hash, Debug)

///|
/// The length `n`, or `None` when `n` is negative.
pub fn Length::new(n : Int32) -> Length? {
  if n < 0 {
    None
  } else {
    Some(Length(n))
  }
}

///|
/// The length of an empty range.
pub fn Length::zero() -> Length {
  Length(0)
}

///|
/// The length of a single unit.
pub fn Length::one() -> Length {
  Length(1)
}

///|
/// The length of a string in UTF-16 units.
pub fn Length::of_string(s : String) -> Length {
  Length(s.length())
}

///|
/// The sum of two lengths.
pub impl Add for Length with fn add(a, b) {
  Length(a.0 + b.0)
}

///|
/// A 1-based line number.
pub struct Line(Int32) derive(Eq, Compare, Hash, Debug)

///|
/// The line `n`, or `None` when `n` is less than 1.
pub fn Line::new(n : Int32) -> Line? {
  if n < 1 {
    None
  } else {
    Some(Line(n))
  }
}

///|
/// The first line of a text, line 1.
pub fn Line::first() -> Line {
  Line(1)
}

///|
/// The line after `self`.
pub fn Line::next(self : Line) -> Line {
  Line(self.0 + 1)
}

///|
/// A 1-based column, counting UTF-16 units as the Java reference does.
pub struct Column(Int32) derive(Eq, Compare, Hash, Debug)

///|
/// The column `n`, or `None` when `n` is less than 1.
pub fn Column::new(n : Int32) -> Column? {
  if n < 1 {
    None
  } else {
    Some(Column(n))
  }
}

///|
/// The first column of a line, column 1.
pub fn Column::first() -> Column {
  Column(1)
}

///|
/// The column after `self`.
pub fn Column::next(self : Column) -> Column {
  Column(self.0 + 1)
}
