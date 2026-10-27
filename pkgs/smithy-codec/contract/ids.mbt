///|
/// A refused boundary value: the constructor name and the reason.
pub(all) suberror IdentityError {
  InvalidIdentity(String, String)
} derive(Debug)

///|
fn identifier_text(text : String) -> Bool {
  if text.length() == 0 || text.length() > 64 {
    return false
  }
  let mut previous_separator = true
  let mut first = true
  for c in text.iter() {
    let lower = c >= 'a' && c <= 'z'
    let digit = c >= '0' && c <= '9'
    let separator = c == '.' || c == '-'
    if first && !lower {
      return false
    }
    if separator && previous_separator {
      return false
    }
    if !lower && !digit && !separator {
      return false
    }
    previous_separator = separator
    first = false
  }
  !previous_separator
}

///|
/// The identifier of a declared serialization profile, such as `morphir-v4`.
/// Lower-case letters and digits, separated by single `.` or `-`, at most 64 characters.
pub struct ProfileId {
  priv text : String
} derive(Eq, Hash, Compare, Debug)

///|
pub fn ProfileId::parse(text : String) -> ProfileId raise IdentityError {
  guard identifier_text(text) else {
    raise InvalidIdentity(
      "ProfileId",
      "I expected lower-case letters and digits separated by single '.' or '-', but found \{text.escape()}.",
    )
  }
  { text, }
}

///|
pub impl Show for ProfileId with fn output(self, logger) {
  logger.write_string(self.text)
}

///|
pub fn ProfileId::to_string(self : ProfileId) -> String {
  self.text
}

///|
/// The identifier of a host-registered scalar adapter, such as `morphir.v4.name`.
pub struct AdapterId {
  priv text : String
} derive(Eq, Hash, Compare, Debug)

///|
pub fn AdapterId::parse(text : String) -> AdapterId raise IdentityError {
  guard identifier_text(text) else {
    raise InvalidIdentity(
      "AdapterId",
      "I expected lower-case letters and digits separated by single '.' or '-', but found \{text.escape()}.",
    )
  }
  { text, }
}

///|
pub impl Show for AdapterId with fn output(self, logger) {
  logger.write_string(self.text)
}

///|
pub fn AdapterId::to_string(self : AdapterId) -> String {
  self.text
}

///|
/// The identifier of a versioned document bundle, such as `morphir`.
pub struct BundleId {
  priv text : String
} derive(Eq, Hash, Compare, Debug)

///|
pub fn BundleId::parse(text : String) -> BundleId raise IdentityError {
  guard identifier_text(text) else {
    raise InvalidIdentity(
      "BundleId",
      "I expected lower-case letters and digits separated by single '.' or '-', but found \{text.escape()}.",
    )
  }
  { text, }
}

///|
pub impl Show for BundleId with fn output(self, logger) {
  logger.write_string(self.text)
}

///|
pub fn BundleId::to_string(self : BundleId) -> String {
  self.text
}

///|
/// A JSON object member name or union tag on the wire. It is not empty and has no unpaired surrogate.
pub struct WireName {
  priv text : String
} derive(Eq, Hash, Compare, Debug)

///|
pub fn WireName::parse(text : String) -> WireName raise IdentityError {
  guard text.length() > 0 && text.length() <= 1024 else {
    raise InvalidIdentity(
      "WireName", "I expected a wire name of 1..1024 characters.",
    )
  }
  for i in 0..<text.length() {
    let c = text.code_unit_at(i).to_int()
    if c >= 0xD800 && c <= 0xDBFF {
      guard i + 1 < text.length() &&
        text.code_unit_at(i + 1).to_int() >= 0xDC00 &&
        text.code_unit_at(i + 1).to_int() <= 0xDFFF else {
        raise InvalidIdentity(
          "WireName", "I expected a wire name without an unpaired surrogate.",
        )
      }
    } else if c >= 0xDC00 && c <= 0xDFFF {
      guard i > 0 &&
        text.code_unit_at(i - 1).to_int() >= 0xD800 &&
        text.code_unit_at(i - 1).to_int() <= 0xDBFF else {
        raise InvalidIdentity(
          "WireName", "I expected a wire name without an unpaired surrogate.",
        )
      }
    }
  }
  { text, }
}

///|
pub impl Show for WireName with fn output(self, logger) {
  logger.write_string(self.text)
}

///|
pub fn WireName::to_string(self : WireName) -> String {
  self.text
}

///|
/// An exact release `major.minor.patch`. Comparison is numeric, component by component.
pub struct Release {
  major : Int32
  minor : Int32
  patch : Int32
} derive(Eq, Hash, Compare, Debug)

///|
pub fn Release::new(
  major : Int32,
  minor : Int32,
  patch : Int32,
) -> Release raise IdentityError {
  guard major >= 0 && minor >= 0 && patch >= 0 else {
    raise InvalidIdentity(
      "Release", "I expected nonnegative release components.",
    )
  }
  { major, minor, patch, }
}

///|
/// Parse a strict `X.Y.Z` release: three decimal components without signs or leading zeros.
pub fn Release::parse(text : String) -> Release raise IdentityError {
  let parts = text.split(".").map(p => p.to_owned()).to_array()
  guard parts.length() == 3 else {
    raise InvalidIdentity(
      "Release",
      "I expected a release of three components X.Y.Z, but found \{text.escape()}.",
    )
  }
  let values : Array[Int32] = []
  for part in parts {
    guard part.length() > 0 &&
      part.length() <= 9 &&
      (part.length() == 1 || part.code_unit_at(0) != '0') &&
      part.iter().all(c => c >= '0' && c <= '9') else {
      raise InvalidIdentity(
        "Release",
        "I expected decimal release components without leading zeros, but found \{text.escape()}.",
      )
    }
    let mut value = 0
    for c in part.iter() {
      value = value * 10 + (c.to_int() - '0'.to_int())
    }
    values.push(value)
  }
  { major: values[0], minor: values[1], patch: values[2], }
}

///|
pub fn Release::major(self : Release) -> Int32 {
  self.major
}

///|
pub fn Release::minor(self : Release) -> Int32 {
  self.minor
}

///|
pub fn Release::patch(self : Release) -> Int32 {
  self.patch
}

///|
pub impl Show for Release with fn output(self, logger) {
  logger.write_string("\{self.major}.\{self.minor}.\{self.patch}")
}

///|
pub fn Release::to_string(self : Release) -> String {
  "\{self.major}.\{self.minor}.\{self.patch}"
}

///|
/// A half-open release interval `[since, until)`.
pub struct ReleaseInterval {
  since : Release
  until : Release
} derive(Eq, Debug)

///|
pub fn ReleaseInterval::new(
  since : Release,
  until : Release,
) -> ReleaseInterval raise IdentityError {
  guard since < until else {
    raise InvalidIdentity(
      "ReleaseInterval",
      "I expected the interval start \{since} to precede its end \{until}.",
    )
  }
  { since, until, }
}

///|
pub fn ReleaseInterval::since(self : ReleaseInterval) -> Release {
  self.since
}

///|
pub fn ReleaseInterval::until(self : ReleaseInterval) -> Release {
  self.until
}

///|
pub fn ReleaseInterval::contains(
  self : ReleaseInterval,
  release : Release,
) -> Bool {
  self.since <= release && release < self.until
}

///|
pub fn ReleaseInterval::overlaps(
  self : ReleaseInterval,
  other : ReleaseInterval,
) -> Bool {
  self.since < other.until && other.since < self.until
}

///|
pub impl Show for ReleaseInterval with fn output(self, logger) {
  logger.write_string("[\{self.since}, \{self.until})")
}

///|
/// The kind of one JSON value.
pub(all) enum JsonKind {
  NullKind
  BooleanKind
  NumberKind
  StringKind
  ArrayKind
  ObjectKind
} derive(Eq, Hash, Compare, Debug)

///|
pub fn JsonKind::parse(text : String) -> JsonKind? {
  match text {
    "null" => Some(NullKind)
    "boolean" => Some(BooleanKind)
    "number" => Some(NumberKind)
    "string" => Some(StringKind)
    "array" => Some(ArrayKind)
    "object" => Some(ObjectKind)
    _ => None
  }
}

///|
pub fn JsonKind::name(self : JsonKind) -> String {
  match self {
    NullKind => "null"
    BooleanKind => "boolean"
    NumberKind => "number"
    StringKind => "string"
    ArrayKind => "array"
    ObjectKind => "object"
  }
}

///|
pub impl Show for JsonKind with fn output(self, logger) {
  logger.write_string(self.name())
}

///|
pub fn JsonKind::of(value : Json) -> JsonKind {
  match value {
    Null => NullKind
    True | False => BooleanKind
    Number(_, ..) => NumberKind
    String(_) => StringKind
    Array(_) => ArrayKind
    Object(_) => ObjectKind
  }
}
