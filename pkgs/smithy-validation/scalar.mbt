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
    second < 60 else {
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
    return i + 1 == text.length()
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
  true
}
