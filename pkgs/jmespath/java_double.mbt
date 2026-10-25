///|
/// Read Double.parseDouble syntax after Smithy's '.', 'e' or 'E' dispatch.
/// Java trims only U+0000..U+0020 and accepts one floating type suffix.
fn java_double(text : String) -> Double? {
  let mut start = 0
  let mut end = text.length()
  while start < end && text.code_unit_at(start) <= 32 {
    start += 1
  }
  while end > start && text.code_unit_at(end - 1) <= 32 {
    end -= 1
  }
  guard start < end else { return None }
  let negative = text.code_unit_at(start) == '-'
  if negative || text.code_unit_at(start) == '+' {
    start += 1
  }
  guard start < end else { return None }
  let last = text.code_unit_at(end - 1)
  if last == 'd' || last == 'D' || last == 'f' || last == 'F' {
    end -= 1
  }
  guard start < end else { return None }
  let body = text[start:end].to_owned()
  if body.has_prefix("0x") || body.has_prefix("0X") {
    return java_hex_double(body, negative~)
  }
  let mut i = 0
  let mut digits = 0
  while i < body.length() &&
        body.code_unit_at(i) >= '0' &&
        body.code_unit_at(i) <= '9' {
    i += 1
    digits += 1
  }
  if i < body.length() && body.code_unit_at(i) == '.' {
    i += 1
    while i < body.length() &&
          body.code_unit_at(i) >= '0' &&
          body.code_unit_at(i) <= '9' {
      i += 1
      digits += 1
    }
  }
  guard digits > 0 else { return None }
  if i < body.length() &&
    (body.code_unit_at(i) == 'e' || body.code_unit_at(i) == 'E') {
    i += 1
    if i < body.length() &&
      (body.code_unit_at(i) == '+' || body.code_unit_at(i) == '-') {
      i += 1
    }
    let exponent_start = i
    while i < body.length() &&
          body.code_unit_at(i) >= '0' &&
          body.code_unit_at(i) <= '9' {
      i += 1
    }
    guard i > exponent_start else { return None }
  }
  guard i == body.length() else { return None }
  // The grammar is valid. Core raises on overflow; Java returns infinity.
  let value = @string.parse_double(body) catch {
    _ => 0x7ff0000000000000L.reinterpret_as_double()
  }
  Some(if negative { -value } else { value })
}

///|
fn hex_digit(c : UInt16) -> Int32? {
  if c >= '0' && c <= '9' {
    Some(c.to_int() - 48)
  } else if c >= 'a' && c <= 'f' {
    Some(c.to_int() - 87)
  } else if c >= 'A' && c <= 'F' {
    Some(c.to_int() - 55)
  } else {
    None
  }
}

///|
/// Keep 54 leading bits and a sticky bit, then round once to binary64,
/// ties to even. This also handles subnormals without double rounding.
fn java_hex_double(body : String, negative~ : Bool) -> Double? {
  let mut i = 2
  let mut point = false
  let mut digits = 0
  let mut fraction = 0L
  let mut bits = 0L
  let mut leading = 0L
  let mut sticky = false
  while i < body.length() {
    let c = body.code_unit_at(i)
    if c == '.' && !point {
      point = true
      i += 1
      continue
    }
    guard hex_digit(c) is Some(digit) else { break }
    digits += 1
    if point {
      fraction += 4L
    }
    for shift in [3, 2, 1, 0] {
      let bit = (digit >> shift) & 1
      if bits == 0L && bit == 0 {
        continue
      }
      if bits < 54L {
        leading = (leading << 1) | bit.to_int64()
      } else if bit != 0 {
        sticky = true
      }
      bits += 1L
    }
    i += 1
  }
  guard digits > 0 &&
    i < body.length() &&
    (body.code_unit_at(i) == 'p' || body.code_unit_at(i) == 'P') else {
    return None
  }
  i += 1
  let exponent_negative = i < body.length() && body.code_unit_at(i) == '-'
  if i < body.length() && (body.code_unit_at(i) == '+' || exponent_negative) {
    i += 1
  }
  let exponent_start = i
  let mut exponent = 0L
  while i < body.length() &&
        body.code_unit_at(i) >= '0' &&
        body.code_unit_at(i) <= '9' {
    // More than any addressable significand can offset, without integer overflow.
    exponent = (exponent * 10L + body.code_unit_at(i).to_int().to_int64() - 48L).min(
      1000000000000L,
    )
    i += 1
  }
  guard i > exponent_start && i == body.length() else { return None }
  if exponent_negative {
    exponent = -exponent
  }
  let highest = exponent - fraction + bits - 1L
  let sign = if negative { 0x8000000000000000L } else { 0L }
  if bits == 0L || highest < -1075L {
    return Some(sign.reinterpret_as_double())
  }
  if highest > 1023L {
    return Some((sign | 0x7ff0000000000000L).reinterpret_as_double())
  }
  let keep = if highest < -1022L { (highest + 1075L).to_int() } else { 53 }
  let cut = 54 - keep
  let padded = leading << (54 - bits.min(54L).to_int())
  let mut mantissa = padded >> cut
  let guard_bit = 1L << (cut - 1)
  if (padded & guard_bit) != 0L &&
    (sticky || (padded & (guard_bit - 1L)) != 0L || (mantissa & 1L) != 0L) {
    mantissa += 1L
  }
  let result = if highest < -1022L {
    mantissa
  } else {
    ((highest + 1023L) << 52) + mantissa - (1L << 52)
  }
  Some((sign | result).reinterpret_as_double())
}
