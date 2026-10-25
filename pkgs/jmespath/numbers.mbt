///|
/// The number classes of the JMESPath runtime of the Smithy reference. A
/// number token without `.`, `e` or `E` is a `Long`, or a `BigInteger` when
/// 64 bits do not hold it. A decimal token is a `Double` when a double holds
/// its exact value, and a `BigDecimal` otherwise.
priv enum NumberClass {
  Long
  BigInteger
  Double
  BigDecimal
}

///|
/// An exact decimal value: `coefficient` times ten to the power `exponent`.
/// The coefficient has no trailing zeros, and `digits` is its number of
/// decimal digits (zero for the value zero).
priv struct Decimal {
  coefficient : BigInt
  exponent : BigInt
  digits : Int32
}

///|
/// Parse a JSON number token, or the text of `Double::to_string`, into its
/// exact decimal value.
fn Decimal::parse(text : String) -> Decimal? {
  let digits = StringBuilder()
  let mut negative = false
  let mut fraction = 0
  let mut in_fraction = false
  let mut exponent = BigInt::from_int(0)
  let mut seen_digit = false
  let mut i = 0
  if i < text.length() &&
    (text.code_unit_at(i) == '-' || text.code_unit_at(i) == '+') {
    negative = text.code_unit_at(i) == '-'
    i += 1
  }
  while i < text.length() {
    let c = text.code_unit_at(i)
    if c >= '0' && c <= '9' {
      seen_digit = true
      digits.write_char(c.to_int().unsafe_to_char())
      if in_fraction {
        fraction += 1
      }
    } else if c == '.' && !in_fraction {
      in_fraction = true
    } else if c == 'e' || c == 'E' {
      let rest = text[i + 1:].to_owned()
      let rest = if rest.has_prefix("+") { rest[1:].to_owned() } else { rest }
      if rest.is_empty() || rest == "-" {
        return None
      }
      for d in (if rest.has_prefix("-") { rest[1:] } else { rest[:] }) {
        if d < '0' || d > '9' {
          return None
        }
      }
      exponent = BigInt::from_string(rest)
      break
    } else {
      return None
    }
    i += 1
  }
  guard seen_digit else { return None }
  let mut text = digits.to_string()
  let mut start = 0
  while start < text.length() && text.code_unit_at(start) == '0' {
    start += 1
  }
  text = text[start:].to_owned()
  let mut end = text.length()
  while end > 0 && text.code_unit_at(end - 1) == '0' {
    end -= 1
  }
  let trailing = text.length() - end
  text = text[:end].to_owned()
  if text.is_empty() {
    return Some({ coefficient: 0N, exponent: 0N, digits: 0, })
  }
  let coefficient = BigInt::from_string(text)
  Some({
    coefficient: if negative {
      -coefficient
    } else {
      coefficient
    },
    exponent: exponent - BigInt::from_int(fraction) + BigInt::from_int(trailing),
    digits: text.length(),
  })
}

///|
/// Compare two exact decimal values.
fn Decimal::compare(self : Decimal, other : Decimal) -> Int32 {
  let sign = self.coefficient.compare_int(0)
  let other_sign = other.coefficient.compare_int(0)
  if sign != other_sign || sign == 0 {
    return sign.compare(other_sign)
  }
  // The position of the most significant digit decides when it differs, so
  // a large exponent never needs a large power of ten.
  let magnitude = self.exponent + BigInt::from_int(self.digits)
  let other_magnitude = other.exponent + BigInt::from_int(other.digits)
  let order = magnitude.compare(other_magnitude)
  if order != 0 {
    return if sign > 0 { order } else { -order }
  }
  // The same magnitude bounds the exponent difference by the digit counts.
  let shift = (self.exponent - other.exponent).to_int()
  let ten = BigInt::from_int(10)
  if shift >= 0 {
    (self.coefficient * ten.pow(BigInt::from_int(shift))).compare(
      other.coefficient,
    )
  } else {
    self.coefficient.compare(
      other.coefficient * ten.pow(BigInt::from_int(-shift)),
    )
  }
}

///|
let long_min : BigInt = BigInt::from_string("-9223372036854775808")

///|
let long_max : BigInt = BigInt::from_string("9223372036854775807")

///|
fn is_decimal_token(text : String) -> Bool {
  text.contains(".") || text.contains("e") || text.contains("E")
}

///|
/// The class of a number. A number with its source token takes the class of
/// the token. A number without its token (a computed number, or a JSON value
/// that a double holds exactly) is a `Long` when it is a whole number in the
/// 64-bit range, and a `Double` otherwise.
fn number_class(value : Double, repr : String?) -> NumberClass {
  match repr {
    Some(text) if is_decimal_token(text) => {
      if value.is_nan() || value.is_inf() {
        return BigDecimal
      }
      match (Decimal::parse(text), Decimal::parse(value.to_string())) {
        (Some(exact), Some(held)) if exact.compare(held) == 0 => Double
        _ => BigDecimal
      }
    }
    Some(text) => {
      let digits = if text.has_prefix("-") || text.has_prefix("+") {
        text[1:].to_owned()
      } else {
        text
      }
      guard !digits.is_empty() && digits.iter().all(c => c >= '0' && c <= '9') else {
        return BigInteger
      }
      let whole = BigInt::from_string(digits)
      let whole = if text.has_prefix("-") { -whole } else { whole }
      if whole >= long_min && whole <= long_max {
        Long
      } else {
        BigInteger
      }
    }
    None =>
      if value.is_nan() ||
        value.is_inf() ||
        value != value.floor() ||
        // A 64-bit integer has no negative zero.
        (value == 0.0 && value.reinterpret_as_int64() != 0L) ||
        value < -9223372036854775808.0 ||
        value >= 9223372036854775808.0 {
        Double
      } else {
        Long
      }
  }
}

///|
/// The exact value of a number: its source token, or the shortest decimal of
/// its double, as Java's `BigDecimal.valueOf(double)` gives.
fn exact_value(value : Double, repr : String?) -> Decimal? {
  match repr {
    Some(text) => Decimal::parse(text)
    None =>
      if value.is_nan() || value.is_inf() {
        None
      } else {
        Decimal::parse(value.to_string())
      }
  }
}

///|
/// Order two doubles as Java's `Double.compare`: -0.0 is less than 0.0, and
/// NaN is greater than every other value.
fn double_order(a : Double, b : Double) -> Int32 {
  if a < b {
    return -1
  }
  if a > b {
    return 1
  }
  let bits = fn(d : Double) {
    if d.is_nan() {
      0x7ff8000000000000L
    } else {
      d.reinterpret_as_int64()
    }
  }
  bits(a).compare(bits(b))
}

///|
/// Order two JSON numbers as the Smithy reference does. When one side is a
/// `BigInteger` or a `BigDecimal`, or both are `Long`, the exact values
/// decide. When one side is a `Double`, the doubles decide.
fn number_order(
  a : Double,
  a_repr : String?,
  b : Double,
  b_repr : String?,
) -> Int32 {
  let a_class = number_class(a, a_repr)
  let b_class = number_class(b, b_repr)
  let big = a_class is (BigInteger | BigDecimal) ||
    b_class is (BigInteger | BigDecimal)
  if !big && (a_class is Double || b_class is Double) {
    return double_order(a, b)
  }
  match (exact_value(a, a_repr), exact_value(b, b_repr)) {
    (Some(x), Some(y)) => x.compare(y)
    _ => double_order(a, b)
  }
}

///|
/// Tell whether two JSON values are equal as JMESPath values: numbers by
/// `number_order`, arrays by element, objects by key. The walk keeps its own
/// stack, so deep values do not recurse.
fn json_equal(a : Json, b : Json) -> Bool {
  let pending = [(a, b)]
  while pending.pop() is Some((a, b)) {
    match (a, b) {
      (Number(x, repr=x_repr), Number(y, repr=y_repr)) =>
        if number_order(x, x_repr, y, y_repr) != 0 {
          return false
        }
      (Array(xs), Array(ys)) => {
        if xs.length() != ys.length() {
          return false
        }
        for i, x in xs {
          pending.push((x, ys[i]))
        }
      }
      (Object(xs), Object(ys)) => {
        if xs.length() != ys.length() {
          return false
        }
        for key, x in xs {
          guard ys.get(key) is Some(y) else { return false }
          pending.push((x, y))
        }
      }
      _ => if a != b { return false }
    }
  }
  true
}
