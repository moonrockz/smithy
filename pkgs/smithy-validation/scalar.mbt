///|
fn number(text : String) -> @smithy.NodeNumber {
  @smithy.NodeNumber::parse(text).unwrap()
}

///|
fn integer_bounds(kind : @smithy.SimpleType) -> (String, String)? {
  match kind {
    Byte => Some(("-128", "127"))
    Short => Some(("-32768", "32767"))
    Integer => Some(("-2147483648", "2147483647"))
    Long => Some(("-9223372036854775808", "9223372036854775807"))
    _ => None
  }
}

///|
fn numeric_bounds(
  kind : @smithy.SimpleType,
  value : @smithy.NodeNumber,
) -> Bool {
  if integer_bounds(kind) is Some((min, max)) {
    return value.is_integer() &&
      value.numeric_compare(number(min)) >= 0 &&
      value.numeric_compare(number(max)) <= 0
  }
  if kind == BigInteger {
    return value.is_integer()
  }
  let bound = match kind {
    Float => Some("340282346638528859811704183484516925440")
    Double =>
      Some(
        "179769313486231570814527423731704356798070567525844996598917476803157260780028538760589558632766878171540458953514382464234321326889464182768467546703537516986049910576551282076245490090389328944075868508455133942304583236903222948165808559332123348274797826204144723168738177180919299881250404026184124858368",
      )
    _ => None
  }
  match bound {
    None => true
    Some(max) =>
      value.numeric_compare(number("-" + max)) >= 0 &&
      value.numeric_compare(number(max)) <= 0
  }
}

///|
fn strict_blob_length(text : String) -> Int32? {
  let bytes = @base64.decode(text, ignore_whitespace=false) catch {
    _ => return None
  }
  if @base64.encode(bytes, padding=true) != text {
    return None
  }
  Some(bytes.length())
}

///|
/// Positive UTC insertion dates from IERS Leap_Second.dat, Bulletin 72
/// (July 2026): https://hpiers.obspm.fr/iers/bul/bulc/Leap_Second.dat.
/// The initial 1972-01-01 offset is a baseline, not an inserted second.
/// Update this table when IERS announces another insertion. No negative
/// leap seconds are recorded; ordinary seconds 00..59 remain accepted.
fn positive_leap_second(year : Int32, month : Int32, day : Int32) -> Bool {
  match (year, month, day) {
    (1972, 6, 30)
    | (1972, 12, 31)
    | (1973, 12, 31)
    | (1974, 12, 31)
    | (1975, 12, 31)
    | (1976, 12, 31)
    | (1977, 12, 31)
    | (1978, 12, 31)
    | (1979, 12, 31)
    | (1981, 6, 30)
    | (1982, 6, 30)
    | (1983, 6, 30)
    | (1985, 6, 30)
    | (1987, 12, 31)
    | (1989, 12, 31)
    | (1990, 12, 31)
    | (1992, 6, 30)
    | (1993, 6, 30)
    | (1994, 6, 30)
    | (1995, 12, 31)
    | (1997, 6, 30)
    | (1998, 12, 31)
    | (2005, 12, 31)
    | (2008, 12, 31)
    | (2012, 6, 30)
    | (2015, 6, 30)
    | (2016, 12, 31) => true
    _ => false
  }
}

///|
fn leap_second_minute(
  year : Int32,
  month : Int32,
  day : Int32,
  hour : Int32,
  minute : Int32,
  offset_minutes : Int32,
) -> Bool {
  // RFC 3339 offsets are local minus UTC. With offsets below 24 hours,
  // the insertion minute can be 23:59 on this UTC day or the previous day.
  let utc_minute = hour * 60 + minute - offset_minutes
  if utc_minute == 1439 {
    return positive_leap_second(year, month, day)
  }
  guard utc_minute == -1 else { return false }
  if day > 1 {
    return positive_leap_second(year, month, day - 1)
  }
  let (previous_year, previous_month) = if month == 1 {
    (year - 1, 12)
  } else {
    (year, month - 1)
  }
  let mut previous_day = 31
  while previous_day > 28 &&
        !calendar_day(previous_year, previous_month, previous_day) {
    previous_day -= 1
  }
  positive_leap_second(previous_year, previous_month, previous_day)
}

///|
fn date_time(text : String) -> Bool {
  let mut i = 0
  let digits = fn(start : Int32, count : Int32) -> Int32? {
    if start + count > text.length() {
      return None
    }
    let mut value = 0
    for offset in 0..<count {
      let c = text.code_unit_at(start + offset).to_int()
      if c < 48 || c > 57 {
        return None
      }
      value = value * 10 + c - 48
    }
    Some(value)
  }
  guard text.length() >= 20 &&
    text.code_unit_at(4) == 45 &&
    text.code_unit_at(7) == 45 &&
    (text.code_unit_at(10) == 84 || text.code_unit_at(10) == 116) &&
    text.code_unit_at(13) == 58 &&
    text.code_unit_at(16) == 58 else {
    return false
  }
  guard digits(0, 4) is Some(year) &&
    digits(5, 2) is Some(month) &&
    digits(8, 2) is Some(day) &&
    calendar_day(year, month, day) &&
    digits(11, 2) is Some(hour) &&
    hour < 24 &&
    digits(14, 2) is Some(minute) &&
    minute < 60 &&
    digits(17, 2) is Some(second) &&
    second <= 60 else {
    return false
  }
  i = 19
  if text.code_unit_at(i) == 46 {
    i += 1
    let start = i
    while i < text.length() &&
          text.code_unit_at(i) >= 48 &&
          text.code_unit_at(i) <= 57 {
      i += 1
    }
    if i == start {
      return false
    }
  }
  guard i < text.length() else { return false }
  let zone = text.code_unit_at(i)
  if zone == 90 || zone == 122 {
    return i + 1 == text.length() &&
      (second < 60 || leap_second_minute(year, month, day, hour, minute, 0))
  }
  guard (zone == 43 || zone == 45) &&
    i + 6 == text.length() &&
    text.code_unit_at(i + 3) == 58 &&
    digits(i + 1, 2) is Some(hours) &&
    hours < 24 &&
    digits(i + 4, 2) is Some(minutes) &&
    minutes < 60 else {
    return false
  }
  let offset = (hours * 60 + minutes) * (if zone == 43 { 1 } else { -1 })
  second < 60 || leap_second_minute(year, month, day, hour, minute, offset)
}
