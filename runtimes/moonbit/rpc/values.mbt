// Values that the generated codecs use. A Decimal, a BigInteger and an Int64
// keep the exact text of the number, so that they never go through a Double.

///|
fn expected(path : String, what : String, json : Json) -> DecodeError {
  decode_error(path, "I expected \{what}, found \{json_kind(json)}.")
}

///|
/// The exact text of a JSON number. A number without a source text gives the
/// text of its Double.
fn number_text(json : Json) -> String? {
  match json {
    Number(d, repr~) =>
      match repr {
        Some(text) => Some(text)
        None =>
          if d.is_nan() || d.is_inf() {
            None
          } else {
            Some(double_text(d))
          }
      }
    _ => None
  }
}

///|
fn is_integer_text(text : String) -> Bool {
  scan_number(text, 0) == Some(text.length()) &&
  text.find(".") is None &&
  text.find("e") is None &&
  text.find("E") is None
}

///|
/// A decimal number with its exact text, such as `20.00`. Two values are
/// equal when their texts are equal.
pub struct Decimal {
  priv text : String
} derive(Eq, Hash, Debug)

///|
/// Gives a Decimal when `text` is a number of the JSON grammar.
pub fn Decimal::parse(text : String) -> Decimal? {
  if scan_number(text, 0) == Some(text.length()) {
    Some({ text, })
  } else {
    None
  }
}

///|
pub impl Show for Decimal with fn output(self, logger) {
  logger.write_string(self.text)
}

///|
pub fn Decimal::to_string(self : Decimal) -> String {
  self.text
}

///|
pub fn Decimal::to_json(self : Decimal) -> Json {
  Json::number(number_double(self.text), repr=self.text)
}

///|
pub fn Decimal::from_json(
  json : Json,
  path~ : String,
) -> Decimal raise DecodeError {
  guard number_text(json) is Some(text) && Decimal::parse(text) is Some(value) else {
    raise expected(path, "a decimal number", json)
  }
  value
}

///|
/// The sign, the digits and the exponent of a decimal: the value is
/// `sign * digits * 10^exponent`, with no leading or trailing zero digit.
fn Decimal::parts(self : Decimal) -> (Bool, String, Int32) {
  let text = self.text
  let negative = text.has_prefix("-")
  let body = if negative { text[1:].to_owned() } else { text }
  let (mantissa, exponent) = match body.find("e") {
    Some(i) => (body[:i].to_owned(), body[i + 1:].to_owned())
    None =>
      match body.find("E") {
        Some(i) => (body[:i].to_owned(), body[i + 1:].to_owned())
        None => (body, "0")
      }
  }
  let exponent = if exponent.has_prefix("+") {
    exponent[1:].to_owned()
  } else {
    exponent
  }
  let mut exp = @string.parse_int(exponent) catch { _ => 0 }
  let (whole, fraction) = match mantissa.find(".") {
    Some(i) => (mantissa[:i].to_owned(), mantissa[i + 1:].to_owned())
    None => (mantissa, "")
  }
  exp -= fraction.length()
  let digits = whole + fraction
  let mut start = 0
  while start < digits.length() && digits[start].to_int() == 0x30 {
    start += 1
  }
  let mut end = digits.length()
  while end > start && digits[end - 1].to_int() == 0x30 {
    end -= 1
    exp += 1
  }
  let digits = digits[start:end].to_owned()
  if digits == "" {
    (false, "", 0)
  } else {
    (negative, digits, exp)
  }
}

///|
/// Compares the numeric values of two decimals exactly: -1, 0 or 1. `2.50`
/// and `2.5` compare as 0, but they are not equal, because their texts differ.
pub fn Decimal::compare_value(self : Decimal, other : Decimal) -> Int32 {
  let (an, ad, ae) = self.parts()
  let (bn, bd, be) = other.parts()
  if ad == "" && bd == "" {
    return 0
  }
  if ad == "" {
    return if bn { 1 } else { -1 }
  }
  if bd == "" {
    return if an { -1 } else { 1 }
  }
  if an != bn {
    return if an { -1 } else { 1 }
  }
  // Compare the magnitudes: first the position of the leading digit, then
  // the digits.
  let a_top = ad.length() + ae
  let b_top = bd.length() + be
  let magnitude = if a_top != b_top {
    if a_top > b_top {
      1
    } else {
      -1
    }
  } else {
    let n = if ad.length() > bd.length() { ad.length() } else { bd.length() }
    let mut result = 0
    for i in 0..<n {
      let x = if i < ad.length() { ad[i].to_int() } else { 0x30 }
      let y = if i < bd.length() { bd[i].to_int() } else { 0x30 }
      if x != y {
        result = if x > y { 1 } else { -1 }
        break
      }
    }
    result
  }
  if an {
    -magnitude
  } else {
    magnitude
  }
}

///|
/// An integer with its exact text, such as `9007199254740993`.
pub struct BigInteger {
  priv text : String
} derive(Eq, Hash, Debug)

///|
/// Gives a BigInteger when `text` is an integer of the JSON grammar.
pub fn BigInteger::parse(text : String) -> BigInteger? {
  if is_integer_text(text) {
    Some({ text, })
  } else {
    None
  }
}

///|
pub impl Show for BigInteger with fn output(self, logger) {
  logger.write_string(self.text)
}

///|
pub fn BigInteger::to_string(self : BigInteger) -> String {
  self.text
}

///|
pub fn BigInteger::to_json(self : BigInteger) -> Json {
  Json::number(number_double(self.text), repr=self.text)
}

///|
pub fn BigInteger::from_json(
  json : Json,
  path~ : String,
) -> BigInteger raise DecodeError {
  guard number_text(json) is Some(text) &&
    BigInteger::parse(text) is Some(value) else {
    raise expected(path, "an integer", json)
  }
  value
}

///|
/// The JSON forms of a timestamp in Smithy.
pub(all) enum TimestampFormat {
  EpochSeconds
  DateTime
  HttpDate
} derive(Eq, Debug)

///|
/// A timestamp. It keeps the JSON value that it was read from, so that it
/// writes the same text again.
pub struct Timestamp {
  priv value : Json
} derive(Eq, Debug)

///|
pub impl Show for Timestamp with fn output(self, logger) {
  logger.write_string(write_json(self.value))
}

///|
/// A timestamp in epoch seconds, such as `1700000000` or `1700000000.5`.
pub fn Timestamp::epoch_seconds(seconds : Decimal) -> Timestamp {
  { value: seconds.to_json(), }
}

///|
/// A timestamp as a string, in the date-time or the http-date format.
pub fn Timestamp::text(text : String) -> Timestamp {
  { value: Json::string(text), }
}

///|
/// The JSON value of the timestamp.
pub fn Timestamp::to_json(self : Timestamp) -> Json {
  self.value
}

///|
fn is_date_time(text : String) -> Bool {
  // The RFC 3339 form that Smithy uses: 1985-04-12T23:20:50.52Z.
  let n = text.length()
  guard n >= 20 else { return false }
  let digit = (i : Int32) => is_digit(text[i].to_int())
  let char_at = (i : Int32, c : Int32) => text[i].to_int() == c
  for i in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18] {
    if !digit(i) {
      return false
    }
  }
  guard char_at(4, 0x2D) &&
    char_at(7, 0x2D) &&
    (char_at(10, 0x54) || char_at(10, 0x74)) &&
    char_at(13, 0x3A) &&
    char_at(16, 0x3A) else {
    return false
  }
  let mut i = 19
  if i < n && char_at(i, 0x2E) {
    i += 1
    guard i < n && digit(i) else { return false }
    while i < n && digit(i) {
      i += 1
    }
  }
  guard i < n else { return false }
  if char_at(i, 0x5A) || char_at(i, 0x7A) {
    return i + 1 == n
  }
  guard (char_at(i, 0x2B) || char_at(i, 0x2D)) && i + 6 == n else {
    return false
  }
  digit(i + 1) &&
  digit(i + 2) &&
  char_at(i + 3, 0x3A) &&
  digit(i + 4) &&
  digit(i + 5)
}

///|
pub fn Timestamp::from_json(
  json : Json,
  format~ : TimestampFormat,
  path~ : String,
) -> Timestamp raise DecodeError {
  match (format, json) {
    (EpochSeconds, Number(_, ..)) if number_text(json) is Some(_) =>
      { value: json, }
    (EpochSeconds, _) =>
      raise expected(path, "a timestamp in epoch seconds", json)
    (DateTime, String(text)) if is_date_time(text) => { value: json, }
    (DateTime, String(text)) =>
      raise decode_error(
        path,
        "I expected a date-time timestamp such as 1985-04-12T23:20:50.52Z, found '\{text}'.",
      )
    (DateTime, _) => raise expected(path, "a date-time timestamp string", json)
    (HttpDate, String(_)) => { value: json, }
    (HttpDate, _) => raise expected(path, "an http-date timestamp string", json)
  }
}

///|
pub fn decode_string(json : Json, path~ : String) -> String raise DecodeError {
  guard json is String(text) else { raise expected(path, "a string", json) }
  text
}

///|
pub fn decode_bool(json : Json, path~ : String) -> Bool raise DecodeError {
  match json {
    True => true
    False => false
    _ => raise expected(path, "a boolean", json)
  }
}

///|
fn decode_int_range(
  json : Json,
  path : String,
  what : String,
  low : Int64,
  high : Int64,
) -> Int64 raise DecodeError {
  guard number_text(json) is Some(text) && is_integer_text(text) else {
    raise expected(path, what, json)
  }
  let value = @string.parse_int64(text) catch {
    _ =>
      raise decode_error(
        path,
        "I expected \{what}, found \{text}, which is out of range.",
      )
  }
  guard value >= low && value <= high else {
    raise decode_error(
      path,
      "I expected \{what}, found \{text}, which is out of range.",
    )
  }
  value
}

///|
/// Decodes a Smithy `byte`.
pub fn decode_byte(json : Json, path~ : String) -> Int32 raise DecodeError {
  decode_int_range(json, path, "a byte integer", -128L, 127L).to_int()
}

///|
/// Decodes a Smithy `short`.
pub fn decode_short(json : Json, path~ : String) -> Int32 raise DecodeError {
  decode_int_range(json, path, "a short integer", -32768L, 32767L).to_int()
}

///|
/// Decodes a Smithy `integer`.
pub fn decode_int(json : Json, path~ : String) -> Int32 raise DecodeError {
  decode_int_range(json, path, "a 32-bit integer", -2147483648L, 2147483647L).to_int()
}

///|
/// Decodes a Smithy `long` from the exact text of the number.
pub fn decode_int64(json : Json, path~ : String) -> Int64 raise DecodeError {
  decode_int_range(
    json,
    path,
    "a 64-bit integer",
    -9223372036854775807L - 1L,
    9223372036854775807L,
  )
}

///|
/// Decodes a Smithy `double`. The strings `NaN`, `Infinity` and `-Infinity`
/// give the special values.
pub fn decode_double(json : Json, path~ : String) -> Double raise DecodeError {
  match json {
    Number(d, ..) => d
    String("NaN") => @double.not_a_number
    String("Infinity") => @double.infinity
    String("-Infinity") => @double.neg_infinity
    _ => raise expected(path, "a number", json)
  }
}

///|
/// Decodes a Smithy `float`.
pub fn decode_float(json : Json, path~ : String) -> Float raise DecodeError {
  Float::from_double(decode_double(json, path~))
}

///|
/// Decodes a Smithy `blob` from base64 text.
pub fn decode_blob(json : Json, path~ : String) -> Bytes raise DecodeError {
  guard json is String(text) else {
    raise expected(path, "a base64 string", json)
  }
  @base64.decode(text) catch {
    _ => raise decode_error(path, "I expected base64 text, found '\{text}'.")
  }
}

///|
pub fn encode_blob(bytes : Bytes) -> Json {
  Json::string(@base64.encode(bytes))
}

///|
/// Encodes an Int64 with its exact text.
pub fn encode_int64(value : Int64) -> Json {
  let text = value.to_string()
  Json::number(value.to_double(), repr=text)
}

///|
pub fn encode_int(value : Int32) -> Json {
  Json::number(value.to_double())
}

///|
/// Encodes a Double. NaN and the infinities give the strings that Smithy uses.
pub fn encode_double(value : Double) -> Json {
  if value.is_nan() {
    Json::string("NaN")
  } else if value.is_pos_inf() {
    Json::string("Infinity")
  } else if value.is_neg_inf() {
    Json::string("-Infinity")
  } else {
    Json::number(value)
  }
}

///|
pub fn encode_float(value : Float) -> Json {
  encode_double(value.to_double())
}

///|
pub fn object_of(
  json : Json,
  path~ : String,
) -> Map[String, Json] raise DecodeError {
  guard json is Object(fields) else { raise expected(path, "an object", json) }
  fields
}

///|
pub fn array_of(json : Json, path~ : String) -> Array[Json] raise DecodeError {
  guard json is Array(items) else { raise expected(path, "an array", json) }
  items
}

///|
/// The value of a required member. An absent member and a null member are
/// errors.
pub fn required(
  obj : Map[String, Json],
  name : String,
  path~ : String,
) -> Json raise DecodeError {
  match obj.get(name) {
    Some(Null) | None =>
      raise decode_error(
        child_path(path, name),
        "I expected the required member \{name}, found nothing.",
      )
    Some(value) => value
  }
}

///|
/// The value of an optional member. A null member counts as absent.
pub fn optional(obj : Map[String, Json], name : String) -> Json? {
  match obj.get(name) {
    Some(Null) | None => None
    value => value
  }
}

///|
/// Decodes a list. `f` gets each item and its path.
pub fn[T] decode_array(
  json : Json,
  path~ : String,
  f : (Json, String) -> T raise DecodeError,
) -> Array[T] raise DecodeError {
  let items = array_of(json, path~)
  let out = []
  for index, item in items {
    out.push(f(item, index_path(path, index)))
  }
  out
}

///|
/// Decodes a map. It keeps the key order of the input. `f` gets each value
/// and its path.
pub fn[T] decode_map(
  json : Json,
  path~ : String,
  f : (Json, String) -> T raise DecodeError,
) -> Map[String, T] raise DecodeError {
  let fields = object_of(json, path~)
  let out = Map([])
  for key, value in fields {
    out[key] = f(value, child_path(path, key))
  }
  out
}

///|
pub fn[T] encode_array(items : Array[T], f : (T) -> Json) -> Json {
  Json::array(items.map(f))
}

///|
pub fn[T] encode_map(items : Map[String, T], f : (T) -> Json) -> Json {
  let out = Map([])
  for key, value in items {
    out[key] = f(value)
  }
  Json::object(out)
}

///|
/// The one member of a union object whose value is not null: its name and
/// its value.
pub fn union_member(
  json : Json,
  path~ : String,
) -> (String, Json) raise DecodeError {
  let fields = object_of(json, path~)
  let set = []
  for key, value in fields {
    if !(value is Null) {
      set.push((key, value))
    }
  }
  match set {
    [one] => one
    [] =>
      raise decode_error(
        path, "I expected one union member that is not null, found none.",
      )
    _ => {
      let names = set.map(m => m.0)
      raise decode_error(
        path,
        "I expected one union member that is not null, found \{names.length()}: \{names.join(", ")}.",
      )
    }
  }
}

///|
/// Rejects a member that the structure does not declare. Use it only for a
/// structure whose unknown member policy is reject.
pub fn reject_unknown(
  obj : Map[String, Json],
  known : Array[String],
  path~ : String,
) -> Unit raise DecodeError {
  for key, _ in obj {
    if !known.contains(key) {
      raise decode_error(
        child_path(path, key),
        "I expected only declared members, found the unknown member \{key}.",
      )
    }
  }
}

///|
/// The params of a method with named params: absent params give `{}`.
pub fn named_params(params : Json?, path~ : String) -> Json raise DecodeError {
  match params {
    None => Json::object(Map([]))
    Some(Object(_) as value) => value
    Some(value) => raise expected(path, "named params (an object)", value)
  }
}

///|
/// The params of a method with positional params, as an object keyed by
/// `names`. When `either` is true, named params (an object) are also
/// accepted.
pub fn positional_params(
  params : Json?,
  names : Array[String],
  either~ : Bool,
  path~ : String,
) -> Json raise DecodeError {
  match params {
    None => Json::object(Map([]))
    Some(Array(items)) => {
      if items.length() > names.length() {
        raise decode_error(
          index_path(path, names.length()),
          "I expected at most \{names.length()} positional params, found \{items.length()}.",
        )
      }
      let out = Map([])
      for index, item in items {
        out[names[index]] = item
      }
      Json::object(out)
    }
    Some(Object(_) as value) if either => value
    Some(value) =>
      raise expected(
        path,
        if either {
          "params as an array or an object"
        } else {
          "positional params (an array)"
        },
        value,
      )
  }
}

///|
/// Writes an object as positional params in the order of `names`. A
/// trailing absent member is dropped; an inner absent member gives null.
pub fn to_positional(json : Json, names : Array[String]) -> Json {
  guard json is Object(fields) else { return json }
  let mut last = -1
  for index, name in names {
    if fields.get(name) is Some(_) {
      last = index
    }
  }
  let out = []
  for index in 0..<=last {
    out.push(fields.get(names[index]).unwrap_or(Json::null()))
  }
  Json::array(out)
}
