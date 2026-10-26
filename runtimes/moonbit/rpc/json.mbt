// Lossless JSON. The parser keeps the exact source text of each number in
// `Json::Number(_, repr=Some(text))`, and the writer writes that text again.
// Neither the parser nor the writer recurses: each keeps its own stack.

///|
/// A value that does not have the expected form. `path` is a JSON Pointer to
/// the value. The dispatcher answers a DecodeError with the code -32602.
pub(all) suberror DecodeError {
  DecodeError(path~ : String, message~ : String)
} derive(Debug)

///|
pub impl Show for DecodeError with fn output(self, logger) {
  let DecodeError(path~, message~) = self
  if path == "" {
    logger.write_string(message)
  } else {
    logger.write_string("at \{path}: \{message}")
  }
}

///|
fn decode_error(path : String, message : String) -> DecodeError {
  DecodeError(path~, message~)
}

///|
priv struct ObjectFrame {
  fields : Map[String, Json]
  mut key : String
}

///|
priv enum ParseFrame {
  InArray(Array[Json])
  InObject(ObjectFrame)
}

///|
priv struct JsonParser {
  text : String
  mut pos : Int32
}

///|
fn JsonParser::at_end(self : JsonParser) -> Bool {
  self.pos >= self.text.length()
}

///|
fn JsonParser::peek(self : JsonParser) -> Int32 {
  if self.at_end() {
    -1
  } else {
    self.text[self.pos].to_int()
  }
}

///|
fn JsonParser::skip_space(self : JsonParser) -> Unit {
  while !self.at_end() {
    match self.text[self.pos].to_int() {
      0x20 | 0x09 | 0x0A | 0x0D => self.pos += 1
      _ => break
    }
  }
}

///|
/// The text of the code unit at the position, for error messages.
fn JsonParser::found(self : JsonParser) -> String {
  if self.at_end() {
    "the end of the input"
  } else {
    let c = self.text[self.pos].to_int()
    if c >= 0x20 && c < 0x7F {
      "'" + Int32::unsafe_to_char(c).to_string() + "'"
    } else {
      "the code unit " + hex4(c)
    }
  }
}

///|
fn JsonParser::fail(self : JsonParser, expected : String) -> DecodeError {
  decode_error(
    "",
    "I expected \{expected} at offset \{self.pos} of the JSON text, found \{self.found()}.",
  )
}

///|
fn JsonParser::expect_literal(
  self : JsonParser,
  word : String,
  value : Json,
) -> Json raise DecodeError {
  let end = self.pos + word.length()
  if end <= self.text.length() &&
    self.text.view(start_offset=self.pos, end_offset=end) == word.view() {
    self.pos = end
    value
  } else {
    raise self.fail("the literal \{word}")
  }
}

///|
fn is_digit(c : Int32) -> Bool {
  c >= 0x30 && c <= 0x39
}

///|
/// Scans a JSON number at `start` in `text`. It gives the end offset, or None
/// when the text at `start` is not a number of the JSON grammar.
fn scan_number(text : String, start : Int32) -> Int32? {
  let n = text.length()
  let mut i = start
  let at = (k : Int32) => if k < n { text[k].to_int() } else { -1 }
  if at(i) == 0x2D {
    i += 1
  }
  if at(i) == 0x30 {
    i += 1
  } else if at(i) >= 0x31 && at(i) <= 0x39 {
    while is_digit(at(i)) {
      i += 1
    }
  } else {
    return None
  }
  if at(i) == 0x2E {
    i += 1
    guard is_digit(at(i)) else { return None }
    while is_digit(at(i)) {
      i += 1
    }
  }
  if at(i) == 0x65 || at(i) == 0x45 {
    i += 1
    if at(i) == 0x2B || at(i) == 0x2D {
      i += 1
    }
    guard is_digit(at(i)) else { return None }
    while is_digit(at(i)) {
      i += 1
    }
  }
  Some(i)
}

///|
/// The nearest Double of a JSON number text. A value out of range gives an
/// infinity of the same sign.
fn number_double(text : String) -> Double {
  @string.parse_double(text) catch {
    _ =>
      if text.has_prefix("-") {
        @double.neg_infinity
      } else {
        @double.infinity
      }
  }
}

///|
fn JsonParser::parse_number(self : JsonParser) -> Json raise DecodeError {
  guard scan_number(self.text, self.pos) is Some(end) else {
    raise self.fail("a JSON number")
  }
  let repr = self.text.view(start_offset=self.pos, end_offset=end).to_owned()
  self.pos = end
  Json::number(number_double(repr), repr~)
}

///|
fn hex_value(c : Int32) -> Int32 {
  if c >= 0x30 && c <= 0x39 {
    c - 0x30
  } else if c >= 0x61 && c <= 0x66 {
    c - 0x61 + 10
  } else if c >= 0x41 && c <= 0x46 {
    c - 0x41 + 10
  } else {
    -1
  }
}

///|
fn JsonParser::parse_hex4(self : JsonParser) -> Int32 raise DecodeError {
  let mut value = 0
  for _ in 0..<4 {
    let digit = hex_value(self.peek())
    if digit < 0 {
      raise self.fail("a hexadecimal digit of a \\u escape")
    }
    value = value * 16 + digit
    self.pos += 1
  }
  value
}

///|
fn JsonParser::parse_string(self : JsonParser) -> String raise DecodeError {
  // The caller checked the opening quote.
  self.pos += 1
  let out = StringBuilder()
  let mut run = self.pos
  while true {
    if self.at_end() {
      raise self.fail("a closing quote of the string")
    }
    let c = self.text[self.pos].to_int()
    if c == 0x22 {
      out.write_view(self.text.view(start_offset=run, end_offset=self.pos))
      self.pos += 1
      break
    } else if c == 0x5C {
      out.write_view(self.text.view(start_offset=run, end_offset=self.pos))
      self.pos += 1
      let e = self.peek()
      self.pos += 1
      match e {
        0x22 => out.write_char('"')
        0x5C => out.write_char('\\')
        0x2F => out.write_char('/')
        0x62 => out.write_char('\b')
        0x66 => out.write_char('\u{0C}')
        0x6E => out.write_char('\n')
        0x72 => out.write_char('\r')
        0x74 => out.write_char('\t')
        0x75 => {
          let unit = self.parse_hex4()
          if unit >= 0xD800 &&
            unit <= 0xDBFF &&
            self.peek() == 0x5C &&
            self.pos + 1 < self.text.length() &&
            self.text[self.pos + 1].to_int() == 0x75 {
            let save = self.pos
            self.pos += 2
            let low = self.parse_hex4()
            if low >= 0xDC00 && low <= 0xDFFF {
              let code = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
              out.write_char(Int32::unsafe_to_char(code))
            } else {
              out.write_char('\u{FFFD}')
              self.pos = save
            }
          } else if unit >= 0xD800 && unit <= 0xDFFF {
            // A lone surrogate has no scalar value.
            out.write_char('\u{FFFD}')
          } else {
            out.write_char(Int32::unsafe_to_char(unit))
          }
        }
        _ => {
          self.pos -= 1
          raise self.fail("an escape character after a backslash")
        }
      }
      run = self.pos
    } else if c < 0x20 {
      raise self.fail("an escaped control character in the string")
    } else {
      self.pos += 1
    }
  }
  out.to_string()
}

///|
/// Reads the key and the colon of an object member.
fn JsonParser::parse_key(self : JsonParser) -> String raise DecodeError {
  if self.peek() != 0x22 {
    raise self.fail("a quoted member name")
  }
  let key = self.parse_string()
  self.skip_space()
  if self.peek() != 0x3A {
    raise self.fail("':' after the member name")
  }
  self.pos += 1
  self.skip_space()
  key
}

///|
/// Parses JSON text. Every number keeps its exact source text as its `repr`.
/// A duplicate member name keeps the last value.
pub fn parse_json(text : String) -> Json raise DecodeError {
  let p = JsonParser::{ text, pos: 0, }
  let stack : Array[ParseFrame] = []
  p.skip_space()
  while true {
    // Read the start of one value.
    let mut value = match p.peek() {
      0x7B => {
        p.pos += 1
        p.skip_space()
        if p.peek() == 0x7D {
          p.pos += 1
          Json::object(Map([]))
        } else {
          let key = p.parse_key()
          stack.push(InObject({ fields: Map([]), key, }))
          continue
        }
      }
      0x5B => {
        p.pos += 1
        p.skip_space()
        if p.peek() == 0x5D {
          p.pos += 1
          Json::array([])
        } else {
          stack.push(InArray([]))
          continue
        }
      }
      0x22 => Json::string(p.parse_string())
      0x74 => p.expect_literal("true", Json::boolean(true))
      0x66 => p.expect_literal("false", Json::boolean(false))
      0x6E => p.expect_literal("null", Json::null())
      c if c == 0x2D || is_digit(c) => p.parse_number()
      _ => raise p.fail("a JSON value")
    }
    // Attach the complete value to its container, and close each container
    // that ends here.
    let mut need_value = false
    while !need_value {
      match stack.last() {
        None => {
          p.skip_space()
          if !p.at_end() {
            raise p.fail("the end of the input after the JSON value")
          }
          return value
        }
        Some(InArray(items)) => {
          items.push(value)
          p.skip_space()
          match p.peek() {
            0x2C => {
              p.pos += 1
              p.skip_space()
              need_value = true
            }
            0x5D => {
              p.pos += 1
              stack.pop() |> ignore
              value = Json::array(items)
            }
            _ => raise p.fail("',' or ']' after an array element")
          }
        }
        Some(InObject(frame)) => {
          frame.fields[frame.key] = value
          p.skip_space()
          match p.peek() {
            0x2C => {
              p.pos += 1
              p.skip_space()
              frame.key = p.parse_key()
              need_value = true
            }
            0x7D => {
              p.pos += 1
              stack.pop() |> ignore
              value = Json::object(frame.fields)
            }
            _ => raise p.fail("',' or '}' after an object member")
          }
        }
      }
    }
  }
  panic()
}

///|
fn hex4(n : Int32) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  for shift in [12, 8, 4, 0] {
    out.write_char(Int32::unsafe_to_char(digits[(n >> shift) & 0xF].to_int()))
  }
  out.to_string()
}

///|
fn write_escaped(out : StringBuilder, s : String) -> Unit {
  out.write_char('"')
  let n = s.length()
  let mut run = 0
  let mut i = 0
  while i < n {
    let c = s[i].to_int()
    let escape : String? = match c {
      0x22 => Some("\\\"")
      0x5C => Some("\\\\")
      0x0A => Some("\\n")
      0x0D => Some("\\r")
      0x09 => Some("\\t")
      0x08 => Some("\\b")
      0x0C => Some("\\f")
      c if c < 0x20 => Some("\\u" + hex4(c))
      c if c >= 0xD800 && c <= 0xDBFF =>
        if i + 1 < n &&
          s[i + 1].to_int() >= 0xDC00 &&
          s[i + 1].to_int() <= 0xDFFF {
          i += 1
          None
        } else {
          Some("\\u" + hex4(c))
        }
      c if c >= 0xDC00 && c <= 0xDFFF => Some("\\u" + hex4(c))
      _ => None
    }
    if escape is Some(text) {
      out.write_view(s.view(start_offset=run, end_offset=i))
      out.write_string(text)
      run = i + 1
    }
    i += 1
  }
  out.write_view(s.view(start_offset=run, end_offset=n))
  out.write_char('"')
}

///|
/// The JSON text of a Double without a source text. A value that JSON cannot
/// hold (NaN or an infinity) gives null.
fn double_text(d : Double) -> String {
  if d.is_nan() || d.is_inf() {
    "null"
  } else if d == d.floor() && d.abs() < 9007199254740992.0 {
    d.to_int64().to_string()
  } else {
    d.to_string()
  }
}

///|
priv enum WriteFrame {
  WArray(Array[Json], Ref[Int32])
  WObject(Array[(String, Json)], Ref[Int32])
}

///|
/// Writes compact JSON text. A number with a `repr` gives that text exactly.
pub fn write_json(json : Json) -> String {
  let out = StringBuilder()
  let stack : Array[WriteFrame] = []
  let open = (value : Json) => {
    match value {
      Null => out.write_string("null")
      True => out.write_string("true")
      False => out.write_string("false")
      Number(d, repr~) =>
        match repr {
          Some(text) => out.write_string(text)
          None => out.write_string(double_text(d))
        }
      String(s) => write_escaped(out, s)
      Array(items) =>
        if items.is_empty() {
          out.write_string("[]")
        } else {
          out.write_char('[')
          stack.push(WArray(items, Ref(0)))
        }
      Object(fields) =>
        if fields.is_empty() {
          out.write_string("{}")
        } else {
          out.write_char('{')
          stack.push(WObject(fields.to_array(), Ref(0)))
        }
    }
  }
  open(json)
  while stack.last() is Some(frame) {
    match frame {
      WArray(items, index) =>
        if index.val < items.length() {
          if index.val > 0 {
            out.write_char(',')
          }
          let item = items[index.val]
          index.val += 1
          open(item)
        } else {
          out.write_char(']')
          stack.pop() |> ignore
        }
      WObject(members, index) =>
        if index.val < members.length() {
          if index.val > 0 {
            out.write_char(',')
          }
          let (key, item) = members[index.val]
          index.val += 1
          write_escaped(out, key)
          out.write_char(':')
          open(item)
        } else {
          out.write_char('}')
          stack.pop() |> ignore
        }
    }
  }
  out.to_string()
}

///|
/// The kind of a JSON value, for error messages.
pub fn json_kind(json : Json) -> String {
  match json {
    Null => "null"
    True | False => "a boolean"
    Number(_, repr~) =>
      match repr {
        Some(text) => "the number \{text}"
        None => "a number"
      }
    String(_) => "a string"
    Array(_) => "an array"
    Object(_) => "an object"
  }
}

///|
/// The JSON Pointer of the member `name` under `path`.
pub fn child_path(path : String, name : String) -> String {
  path +
  "/" +
  name.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
/// The JSON Pointer of the item `index` under `path`.
pub fn index_path(path : String, index : Int32) -> String {
  path + "/" + index.to_string()
}

///|
/// Resolves a JSON Pointer (RFC 6901) in `json`. An invalid pointer or a
/// missing value gives None.
pub fn resolve_pointer(json : Json, pointer : String) -> Json? {
  if pointer == "" {
    return Some(json)
  }
  guard pointer.has_prefix("/") else { return None }
  let mut current = json
  for raw in pointer[1:].split("/") {
    let token = raw
      .to_owned()
      .replace_all(old="~1", new="/")
      .replace_all(old="~0", new="~")
    match current {
      Object(fields) =>
        match fields.get(token) {
          Some(next) => current = next
          None => return None
        }
      Array(items) => {
        guard scan_number(token, 0) == Some(token.length()) &&
          token.find(".") is None &&
          token.find("e") is None &&
          token.find("E") is None &&
          !token.has_prefix("-") else {
          return None
        }
        let index = @string.parse_int(token) catch { _ => return None }
        guard index < items.length() else { return None }
        current = items[index]
      }
      _ => return None
    }
  }
  Some(current)
}
