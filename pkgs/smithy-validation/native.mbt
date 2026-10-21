///|
pub(all) enum NativeOffset {
  KnownOffsetMinutes(Int32)
  UnknownOffset
} derive(Eq, Debug)

///|
/// A native timestamp's precision and offset, independent of any format library.
pub struct NativeTimestamp {
  year : Int32
  month : Int32?
  day : Int32?
  hour : Int32?
  minute : Int32?
  second : Int32?
  fraction : @smithy.NodeNumber?
  offset : NativeOffset
} derive(Debug)

///|
fn calendar_day(year : Int32, month : Int32, day : Int32) -> Bool {
  if year < 1 || year > 9999 || month < 1 || month > 12 || day < 1 {
    return false
  }
  let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
  let days = match month {
    2 => if leap { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
  day <= days
}

///|
/// Construct a neutral timestamp with seconds 0..59. Leap-second notation
/// is supported by the RFC 3339 string validator, not this native value type.
pub fn NativeTimestamp::new(
  year : Int32,
  month~ : Int32? = None,
  day~ : Int32? = None,
  hour~ : Int32? = None,
  minute~ : Int32? = None,
  second~ : Int32? = None,
  fraction~ : @smithy.NodeNumber? = None,
  offset~ : NativeOffset = UnknownOffset,
) -> NativeTimestamp raise ConfigurationError {
  let bad = fn() {
    ConfigurationError(
      "I expected consistent timestamp precision, a valid calendar date and a valid offset.",
    )
  }
  guard year >= 1 && year <= 9999 else { raise bad() }
  if month is Some(m) && (m < 1 || m > 12) {
    raise bad()
  }
  if day is Some(d) {
    guard month is Some(m) && calendar_day(year, m, d) else { raise bad() }
  }
  if hour is Some(h) {
    guard day is Some(_) && h >= 0 && h < 24 && minute is Some(_) else {
      raise bad()
    }
  }
  if minute is Some(m) {
    guard hour is Some(_) && m >= 0 && m < 60 else { raise bad() }
  }
  if second is Some(s) {
    guard minute is Some(_) && s >= 0 && s < 60 else { raise bad() }
  }
  if fraction is Some(f) {
    guard second is Some(_) &&
      f.numeric_compare(@smithy.NodeNumber::parse("0").unwrap()) >= 0 &&
      f.numeric_compare(@smithy.NodeNumber::parse("1").unwrap()) < 0 else {
      raise bad()
    }
  }
  if offset is KnownOffsetMinutes(m) &&
    (minute is None || m <= -1440 || m >= 1440) {
    raise bad()
  }
  { year, month, day, hour, minute, second, fraction, offset, }
}

///|
pub fn NativeTimestamp::year(self : NativeTimestamp) -> Int32 {
  self.year
}

///|
pub fn NativeTimestamp::month(self : NativeTimestamp) -> Int32? {
  self.month
}

///|
pub fn NativeTimestamp::day(self : NativeTimestamp) -> Int32? {
  self.day
}

///|
pub fn NativeTimestamp::hour(self : NativeTimestamp) -> Int32? {
  self.hour
}

///|
pub fn NativeTimestamp::minute(self : NativeTimestamp) -> Int32? {
  self.minute
}

///|
pub fn NativeTimestamp::second(self : NativeTimestamp) -> Int32? {
  self.second
}

///|
pub fn NativeTimestamp::fraction(self : NativeTimestamp) -> @smithy.NodeNumber? {
  self.fraction
}

///|
pub fn NativeTimestamp::offset(self : NativeTimestamp) -> NativeOffset {
  self.offset
}
