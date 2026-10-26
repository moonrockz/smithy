///|
/// The source files of the MoonBit JSON-RPC runtime, from `runtimes/moonbit/rpc`.
/// `mise run runtime:embed` writes this file; do not edit it.
let runtime_files : Array[(String, String)] = [
  (
    "connection.mbt",
    (
      #|///|
      #|/// A transport of JSON-RPC messages, one JSON text for each message.
      #|///
      #|/// - `receive` gives the next message, or None when the remote peer closed
      #|///   the connection.
      #|/// - `send` sends one message. `related` is the ID of the incoming call that
      #|///   the message belongs to, when there is one: its response, or a
      #|///   notification or request that its handler sends. A transport that has
      #|///   one stream per call (HTTP) uses it; other transports ignore it.
      #|/// - `close` closes the connection.
      #|pub(open) trait Connection {
      #|  async fn receive(Self) -> String?
      #|  async fn send(Self, String, related~ : RequestId?) -> Unit
      #|  fn close(Self) -> Unit
      #|}
      #|
      #|///|
      #|/// One end of an in-memory connection pair.
      #|struct MemoryConnection {
      #|  inbox : @aqueue.Queue[String]
      #|  outbox : @aqueue.Queue[String]
      #|}
      #|
      #|///|
      #|/// Two connected ends: a message sent on one end is received on the other.
      #|pub fn memory_pair() -> (MemoryConnection, MemoryConnection) {
      #|  let a = @aqueue.Queue(kind=Unbounded)
      #|  let b = @aqueue.Queue(kind=Unbounded)
      #|  ({ inbox: a, outbox: b, }, { inbox: b, outbox: a, })
      #|}
      #|
      #|///|
      #|pub impl Connection for MemoryConnection with fn receive(self) {
      #|  let text = self.inbox.get() catch {
      #|    @aqueue.QueueAlreadyClosed => return None
      #|    err => raise err
      #|  }
      #|  Some(text)
      #|}
      #|
      #|///|
      #|pub impl Connection for MemoryConnection with fn send(self, text, related~) {
      #|  ignore(related)
      #|  self.outbox.put(text) catch {
      #|    @aqueue.QueueAlreadyClosed =>
      #|      raise TransportError(
      #|        "I could not send the message: the connection is closed.",
      #|      )
      #|    err => raise err
      #|  }
      #|}
      #|
      #|///|
      #|pub impl Connection for MemoryConnection with fn close(self) {
      #|  self.outbox.close()
      #|  self.inbox.close()
      #|}
      #|
    ),
  ),
  (
    "errors.mbt",
    (
      #|///|
      #|/// A JSON-RPC error. A handler raises it to answer with this code, message
      #|/// and data. `Peer::request` raises it for an error response and for a call
      #|/// that the session refuses before it is sent.
      #|pub(all) suberror RpcError {
      #|  RpcError(code~ : Int32, message~ : String, data~ : Json?)
      #|} derive(Debug)
      #|
      #|///|
      #|pub impl Show for RpcError with fn output(self, logger) {
      #|  let RpcError(code~, message~, ..) = self
      #|  logger.write_string("error \{code}: \{message}")
      #|}
      #|
      #|///|
      #|/// A failure of the connection: the remote peer closed it, or a frame on the
      #|/// wire is not valid.
      #|pub(all) suberror TransportError {
      #|  TransportError(String)
      #|} derive(Debug)
      #|
      #|///|
      #|pub impl Show for TransportError with fn output(self, logger) {
      #|  let TransportError(message) = self
      #|  logger.write_string(message)
      #|}
      #|
      #|///|
      #|/// Invalid JSON was received.
      #|pub let parse_error_code : Int32 = -32700
      #|
      #|///|
      #|/// The JSON is not a valid request object.
      #|pub let invalid_request_code : Int32 = -32600
      #|
      #|///|
      #|/// The method does not exist.
      #|pub let method_not_found_code : Int32 = -32601
      #|
      #|///|
      #|/// The params are not valid.
      #|pub let invalid_params_code : Int32 = -32602
      #|
      #|///|
      #|/// An internal error of the handler.
      #|pub let internal_error_code : Int32 = -32603
      #|
      #|///|
      #|/// The default code of a cancelled call.
      #|pub let request_cancelled_code : Int32 = -32800
      #|
      #|///|
      #|/// The ID of a JSON-RPC request: an integer or a string. An integer keeps its
      #|/// exact text, so that an ID beyond the Int64 range is echoed unchanged.
      #|pub(all) enum RequestId {
      #|  Number(String)
      #|  Text(String)
      #|} derive(Eq, Hash, Debug)
      #|
      #|///|
      #|pub impl Show for RequestId with fn output(self, logger) {
      #|  match self {
      #|    Number(text) => logger.write_string(text)
      #|    Text(text) => logger.write_string(write_json(Json::string(text)))
      #|  }
      #|}
      #|
      #|///|
      #|pub fn RequestId::to_json(self : RequestId) -> Json {
      #|  match self {
      #|    Number(text) => Json::number(number_double(text), repr=text)
      #|    Text(text) => Json::string(text)
      #|  }
      #|}
      #|
      #|///|
      #|/// Gives the ID for a JSON string or a JSON integer, and None for any other
      #|/// value.
      #|pub fn RequestId::from_json(json : Json) -> RequestId? {
      #|  match json {
      #|    String(text) => Some(Text(text))
      #|    Number(_, ..) =>
      #|      match number_text(json) {
      #|        Some(text) if is_integer_text(text) => Some(Number(text))
      #|        _ => None
      #|      }
      #|    _ => None
      #|  }
      #|}
      #|
    ),
  ),
  (
    "json.mbt",
    (
      #|// Lossless JSON. The parser keeps the exact source text of each number in
      #|// `Json::Number(_, repr=Some(text))`, and the writer writes that text again.
      #|// Neither the parser nor the writer recurses: each keeps its own stack.
      #|
      #|///|
      #|/// A value that does not have the expected form. `path` is a JSON Pointer to
      #|/// the value. The dispatcher answers a DecodeError with the code -32602.
      #|pub(all) suberror DecodeError {
      #|  DecodeError(path~ : String, message~ : String)
      #|} derive(Debug)
      #|
      #|///|
      #|pub impl Show for DecodeError with fn output(self, logger) {
      #|  let DecodeError(path~, message~) = self
      #|  if path == "" {
      #|    logger.write_string(message)
      #|  } else {
      #|    logger.write_string("at \{path}: \{message}")
      #|  }
      #|}
      #|
      #|///|
      #|fn decode_error(path : String, message : String) -> DecodeError {
      #|  DecodeError(path~, message~)
      #|}
      #|
      #|///|
      #|priv struct ObjectFrame {
      #|  fields : Map[String, Json]
      #|  mut key : String
      #|}
      #|
      #|///|
      #|priv enum ParseFrame {
      #|  InArray(Array[Json])
      #|  InObject(ObjectFrame)
      #|}
      #|
      #|///|
      #|priv struct JsonParser {
      #|  text : String
      #|  mut pos : Int32
      #|}
      #|
      #|///|
      #|fn JsonParser::at_end(self : JsonParser) -> Bool {
      #|  self.pos >= self.text.length()
      #|}
      #|
      #|///|
      #|fn JsonParser::peek(self : JsonParser) -> Int32 {
      #|  if self.at_end() {
      #|    -1
      #|  } else {
      #|    self.text[self.pos].to_int()
      #|  }
      #|}
      #|
      #|///|
      #|fn JsonParser::skip_space(self : JsonParser) -> Unit {
      #|  while !self.at_end() {
      #|    match self.text[self.pos].to_int() {
      #|      0x20 | 0x09 | 0x0A | 0x0D => self.pos += 1
      #|      _ => break
      #|    }
      #|  }
      #|}
      #|
      #|///|
      #|/// The text of the code unit at the position, for error messages.
      #|fn JsonParser::found(self : JsonParser) -> String {
      #|  if self.at_end() {
      #|    "the end of the input"
      #|  } else {
      #|    let c = self.text[self.pos].to_int()
      #|    if c >= 0x20 && c < 0x7F {
      #|      "'" + Int32::unsafe_to_char(c).to_string() + "'"
      #|    } else {
      #|      "the code unit " + hex4(c)
      #|    }
      #|  }
      #|}
      #|
      #|///|
      #|fn JsonParser::fail(self : JsonParser, expected : String) -> DecodeError {
      #|  decode_error(
      #|    "",
      #|    "I expected \{expected} at offset \{self.pos} of the JSON text, found \{self.found()}.",
      #|  )
      #|}
      #|
      #|///|
      #|fn JsonParser::expect_literal(
      #|  self : JsonParser,
      #|  word : String,
      #|  value : Json,
      #|) -> Json raise DecodeError {
      #|  let end = self.pos + word.length()
      #|  if end <= self.text.length() &&
      #|    self.text.view(start_offset=self.pos, end_offset=end) == word.view() {
      #|    self.pos = end
      #|    value
      #|  } else {
      #|    raise self.fail("the literal \{word}")
      #|  }
      #|}
      #|
      #|///|
      #|fn is_digit(c : Int32) -> Bool {
      #|  c >= 0x30 && c <= 0x39
      #|}
      #|
      #|///|
      #|/// Scans a JSON number at `start` in `text`. It gives the end offset, or None
      #|/// when the text at `start` is not a number of the JSON grammar.
      #|fn scan_number(text : String, start : Int32) -> Int32? {
      #|  let n = text.length()
      #|  let mut i = start
      #|  let at = (k : Int32) => if k < n { text[k].to_int() } else { -1 }
      #|  if at(i) == 0x2D {
      #|    i += 1
      #|  }
      #|  if at(i) == 0x30 {
      #|    i += 1
      #|  } else if at(i) >= 0x31 && at(i) <= 0x39 {
      #|    while is_digit(at(i)) {
      #|      i += 1
      #|    }
      #|  } else {
      #|    return None
      #|  }
      #|  if at(i) == 0x2E {
      #|    i += 1
      #|    guard is_digit(at(i)) else { return None }
      #|    while is_digit(at(i)) {
      #|      i += 1
      #|    }
      #|  }
      #|  if at(i) == 0x65 || at(i) == 0x45 {
      #|    i += 1
      #|    if at(i) == 0x2B || at(i) == 0x2D {
      #|      i += 1
      #|    }
      #|    guard is_digit(at(i)) else { return None }
      #|    while is_digit(at(i)) {
      #|      i += 1
      #|    }
      #|  }
      #|  Some(i)
      #|}
      #|
      #|///|
      #|/// The nearest Double of a JSON number text. A value out of range gives an
      #|/// infinity of the same sign.
      #|fn number_double(text : String) -> Double {
      #|  @string.parse_double(text) catch {
      #|    _ =>
      #|      if text.has_prefix("-") {
      #|        @double.neg_infinity
      #|      } else {
      #|        @double.infinity
      #|      }
      #|  }
      #|}
      #|
      #|///|
      #|fn JsonParser::parse_number(self : JsonParser) -> Json raise DecodeError {
      #|  guard scan_number(self.text, self.pos) is Some(end) else {
      #|    raise self.fail("a JSON number")
      #|  }
      #|  let repr = self.text.view(start_offset=self.pos, end_offset=end).to_owned()
      #|  self.pos = end
      #|  Json::number(number_double(repr), repr~)
      #|}
      #|
      #|///|
      #|fn hex_value(c : Int32) -> Int32 {
      #|  if c >= 0x30 && c <= 0x39 {
      #|    c - 0x30
      #|  } else if c >= 0x61 && c <= 0x66 {
      #|    c - 0x61 + 10
      #|  } else if c >= 0x41 && c <= 0x46 {
      #|    c - 0x41 + 10
      #|  } else {
      #|    -1
      #|  }
      #|}
      #|
      #|///|
      #|fn JsonParser::parse_hex4(self : JsonParser) -> Int32 raise DecodeError {
      #|  let mut value = 0
      #|  for _ in 0..<4 {
      #|    let digit = hex_value(self.peek())
      #|    if digit < 0 {
      #|      raise self.fail("a hexadecimal digit of a \\u escape")
      #|    }
      #|    value = value * 16 + digit
      #|    self.pos += 1
      #|  }
      #|  value
      #|}
      #|
      #|///|
      #|fn JsonParser::parse_string(self : JsonParser) -> String raise DecodeError {
      #|  // The caller checked the opening quote.
      #|  self.pos += 1
      #|  let out = StringBuilder()
      #|  let mut run = self.pos
      #|  while true {
      #|    if self.at_end() {
      #|      raise self.fail("a closing quote of the string")
      #|    }
      #|    let c = self.text[self.pos].to_int()
      #|    if c == 0x22 {
      #|      out.write_view(self.text.view(start_offset=run, end_offset=self.pos))
      #|      self.pos += 1
      #|      break
      #|    } else if c == 0x5C {
      #|      out.write_view(self.text.view(start_offset=run, end_offset=self.pos))
      #|      self.pos += 1
      #|      let e = self.peek()
      #|      self.pos += 1
      #|      match e {
      #|        0x22 => out.write_char('"')
      #|        0x5C => out.write_char('\\')
      #|        0x2F => out.write_char('/')
      #|        0x62 => out.write_char('\b')
      #|        0x66 => out.write_char('\u{0C}')
      #|        0x6E => out.write_char('\n')
      #|        0x72 => out.write_char('\r')
      #|        0x74 => out.write_char('\t')
      #|        0x75 => {
      #|          let unit = self.parse_hex4()
      #|          if unit >= 0xD800 &&
      #|            unit <= 0xDBFF &&
      #|            self.peek() == 0x5C &&
      #|            self.pos + 1 < self.text.length() &&
      #|            self.text[self.pos + 1].to_int() == 0x75 {
      #|            let save = self.pos
      #|            self.pos += 2
      #|            let low = self.parse_hex4()
      #|            if low >= 0xDC00 && low <= 0xDFFF {
      #|              let code = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
      #|              out.write_char(Int32::unsafe_to_char(code))
      #|            } else {
      #|              out.write_char('\u{FFFD}')
      #|              self.pos = save
      #|            }
      #|          } else if unit >= 0xD800 && unit <= 0xDFFF {
      #|            // A lone surrogate has no scalar value.
      #|            out.write_char('\u{FFFD}')
      #|          } else {
      #|            out.write_char(Int32::unsafe_to_char(unit))
      #|          }
      #|        }
      #|        _ => {
      #|          self.pos -= 1
      #|          raise self.fail("an escape character after a backslash")
      #|        }
      #|      }
      #|      run = self.pos
      #|    } else if c < 0x20 {
      #|      raise self.fail("an escaped control character in the string")
      #|    } else {
      #|      self.pos += 1
      #|    }
      #|  }
      #|  out.to_string()
      #|}
      #|
      #|///|
      #|/// Reads the key and the colon of an object member.
      #|fn JsonParser::parse_key(self : JsonParser) -> String raise DecodeError {
      #|  if self.peek() != 0x22 {
      #|    raise self.fail("a quoted member name")
      #|  }
      #|  let key = self.parse_string()
      #|  self.skip_space()
      #|  if self.peek() != 0x3A {
      #|    raise self.fail("':' after the member name")
      #|  }
      #|  self.pos += 1
      #|  self.skip_space()
      #|  key
      #|}
      #|
      #|///|
      #|/// Parses JSON text. Every number keeps its exact source text as its `repr`.
      #|/// A duplicate member name keeps the last value.
      #|pub fn parse_json(text : String) -> Json raise DecodeError {
      #|  let p = JsonParser::{ text, pos: 0, }
      #|  let stack : Array[ParseFrame] = []
      #|  p.skip_space()
      #|  while true {
      #|    // Read the start of one value.
      #|    let mut value = match p.peek() {
      #|      0x7B => {
      #|        p.pos += 1
      #|        p.skip_space()
      #|        if p.peek() == 0x7D {
      #|          p.pos += 1
      #|          Json::object(Map([]))
      #|        } else {
      #|          let key = p.parse_key()
      #|          stack.push(InObject({ fields: Map([]), key, }))
      #|          continue
      #|        }
      #|      }
      #|      0x5B => {
      #|        p.pos += 1
      #|        p.skip_space()
      #|        if p.peek() == 0x5D {
      #|          p.pos += 1
      #|          Json::array([])
      #|        } else {
      #|          stack.push(InArray([]))
      #|          continue
      #|        }
      #|      }
      #|      0x22 => Json::string(p.parse_string())
      #|      0x74 => p.expect_literal("true", Json::boolean(true))
      #|      0x66 => p.expect_literal("false", Json::boolean(false))
      #|      0x6E => p.expect_literal("null", Json::null())
      #|      c if c == 0x2D || is_digit(c) => p.parse_number()
      #|      _ => raise p.fail("a JSON value")
      #|    }
      #|    // Attach the complete value to its container, and close each container
      #|    // that ends here.
      #|    let mut need_value = false
      #|    while !need_value {
      #|      match stack.last() {
      #|        None => {
      #|          p.skip_space()
      #|          if !p.at_end() {
      #|            raise p.fail("the end of the input after the JSON value")
      #|          }
      #|          return value
      #|        }
      #|        Some(InArray(items)) => {
      #|          items.push(value)
      #|          p.skip_space()
      #|          match p.peek() {
      #|            0x2C => {
      #|              p.pos += 1
      #|              p.skip_space()
      #|              need_value = true
      #|            }
      #|            0x5D => {
      #|              p.pos += 1
      #|              stack.pop() |> ignore
      #|              value = Json::array(items)
      #|            }
      #|            _ => raise p.fail("',' or ']' after an array element")
      #|          }
      #|        }
      #|        Some(InObject(frame)) => {
      #|          frame.fields[frame.key] = value
      #|          p.skip_space()
      #|          match p.peek() {
      #|            0x2C => {
      #|              p.pos += 1
      #|              p.skip_space()
      #|              frame.key = p.parse_key()
      #|              need_value = true
      #|            }
      #|            0x7D => {
      #|              p.pos += 1
      #|              stack.pop() |> ignore
      #|              value = Json::object(frame.fields)
      #|            }
      #|            _ => raise p.fail("',' or '}' after an object member")
      #|          }
      #|        }
      #|      }
      #|    }
      #|  }
      #|  panic()
      #|}
      #|
      #|///|
      #|fn hex4(n : Int32) -> String {
      #|  let digits = "0123456789abcdef"
      #|  let out = StringBuilder()
      #|  for shift in [12, 8, 4, 0] {
      #|    out.write_char(Int32::unsafe_to_char(digits[(n >> shift) & 0xF].to_int()))
      #|  }
      #|  out.to_string()
      #|}
      #|
      #|///|
      #|fn write_escaped(out : StringBuilder, s : String) -> Unit {
      #|  out.write_char('"')
      #|  let n = s.length()
      #|  let mut run = 0
      #|  let mut i = 0
      #|  while i < n {
      #|    let c = s[i].to_int()
      #|    let escape : String? = match c {
      #|      0x22 => Some("\\\"")
      #|      0x5C => Some("\\\\")
      #|      0x0A => Some("\\n")
      #|      0x0D => Some("\\r")
      #|      0x09 => Some("\\t")
      #|      0x08 => Some("\\b")
      #|      0x0C => Some("\\f")
      #|      c if c < 0x20 => Some("\\u" + hex4(c))
      #|      c if c >= 0xD800 && c <= 0xDBFF =>
      #|        if i + 1 < n &&
      #|          s[i + 1].to_int() >= 0xDC00 &&
      #|          s[i + 1].to_int() <= 0xDFFF {
      #|          i += 1
      #|          None
      #|        } else {
      #|          Some("\\u" + hex4(c))
      #|        }
      #|      c if c >= 0xDC00 && c <= 0xDFFF => Some("\\u" + hex4(c))
      #|      _ => None
      #|    }
      #|    if escape is Some(text) {
      #|      out.write_view(s.view(start_offset=run, end_offset=i))
      #|      out.write_string(text)
      #|      run = i + 1
      #|    }
      #|    i += 1
      #|  }
      #|  out.write_view(s.view(start_offset=run, end_offset=n))
      #|  out.write_char('"')
      #|}
      #|
      #|///|
      #|/// The JSON text of a Double without a source text. A value that JSON cannot
      #|/// hold (NaN or an infinity) gives null.
      #|fn double_text(d : Double) -> String {
      #|  if d.is_nan() || d.is_inf() {
      #|    "null"
      #|  } else if d == d.floor() && d.abs() < 9007199254740992.0 {
      #|    d.to_int64().to_string()
      #|  } else {
      #|    d.to_string()
      #|  }
      #|}
      #|
      #|///|
      #|priv enum WriteFrame {
      #|  WArray(Array[Json], Ref[Int32])
      #|  WObject(Array[(String, Json)], Ref[Int32])
      #|}
      #|
      #|///|
      #|/// Writes compact JSON text. A number with a `repr` gives that text exactly.
      #|pub fn write_json(json : Json) -> String {
      #|  let out = StringBuilder()
      #|  let stack : Array[WriteFrame] = []
      #|  let open = (value : Json) => {
      #|    match value {
      #|      Null => out.write_string("null")
      #|      True => out.write_string("true")
      #|      False => out.write_string("false")
      #|      Number(d, repr~) =>
      #|        match repr {
      #|          Some(text) => out.write_string(text)
      #|          None => out.write_string(double_text(d))
      #|        }
      #|      String(s) => write_escaped(out, s)
      #|      Array(items) =>
      #|        if items.is_empty() {
      #|          out.write_string("[]")
      #|        } else {
      #|          out.write_char('[')
      #|          stack.push(WArray(items, Ref(0)))
      #|        }
      #|      Object(fields) =>
      #|        if fields.is_empty() {
      #|          out.write_string("{}")
      #|        } else {
      #|          out.write_char('{')
      #|          stack.push(WObject(fields.to_array(), Ref(0)))
      #|        }
      #|    }
      #|  }
      #|  open(json)
      #|  while stack.last() is Some(frame) {
      #|    match frame {
      #|      WArray(items, index) =>
      #|        if index.val < items.length() {
      #|          if index.val > 0 {
      #|            out.write_char(',')
      #|          }
      #|          let item = items[index.val]
      #|          index.val += 1
      #|          open(item)
      #|        } else {
      #|          out.write_char(']')
      #|          stack.pop() |> ignore
      #|        }
      #|      WObject(members, index) =>
      #|        if index.val < members.length() {
      #|          if index.val > 0 {
      #|            out.write_char(',')
      #|          }
      #|          let (key, item) = members[index.val]
      #|          index.val += 1
      #|          write_escaped(out, key)
      #|          out.write_char(':')
      #|          open(item)
      #|        } else {
      #|          out.write_char('}')
      #|          stack.pop() |> ignore
      #|        }
      #|    }
      #|  }
      #|  out.to_string()
      #|}
      #|
      #|///|
      #|/// The kind of a JSON value, for error messages.
      #|pub fn json_kind(json : Json) -> String {
      #|  match json {
      #|    Null => "null"
      #|    True | False => "a boolean"
      #|    Number(_, repr~) =>
      #|      match repr {
      #|        Some(text) => "the number \{text}"
      #|        None => "a number"
      #|      }
      #|    String(_) => "a string"
      #|    Array(_) => "an array"
      #|    Object(_) => "an object"
      #|  }
      #|}
      #|
      #|///|
      #|/// The JSON Pointer of the member `name` under `path`.
      #|pub fn child_path(path : String, name : String) -> String {
      #|  path +
      #|  "/" +
      #|  name.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
      #|}
      #|
      #|///|
      #|/// The JSON Pointer of the item `index` under `path`.
      #|pub fn index_path(path : String, index : Int32) -> String {
      #|  path + "/" + index.to_string()
      #|}
      #|
      #|///|
      #|/// Resolves a JSON Pointer (RFC 6901) in `json`. An invalid pointer or a
      #|/// missing value gives None.
      #|pub fn resolve_pointer(json : Json, pointer : String) -> Json? {
      #|  if pointer == "" {
      #|    return Some(json)
      #|  }
      #|  guard pointer.has_prefix("/") else { return None }
      #|  let mut current = json
      #|  for raw in pointer[1:].split("/") {
      #|    let token = raw
      #|      .to_owned()
      #|      .replace_all(old="~1", new="/")
      #|      .replace_all(old="~0", new="~")
      #|    match current {
      #|      Object(fields) =>
      #|        match fields.get(token) {
      #|          Some(next) => current = next
      #|          None => return None
      #|        }
      #|      Array(items) => {
      #|        guard scan_number(token, 0) == Some(token.length()) &&
      #|          token.find(".") is None &&
      #|          token.find("e") is None &&
      #|          token.find("E") is None &&
      #|          !token.has_prefix("-") else {
      #|          return None
      #|        }
      #|        let index = @string.parse_int(token) catch { _ => return None }
      #|        guard index < items.length() else { return None }
      #|        current = items[index]
      #|      }
      #|      _ => return None
      #|    }
      #|  }
      #|  Some(current)
      #|}
      #|
    ),
  ),
  (
    "log.mbt",
    (
      #|///|
      #|/// A session log in the JSONL form of the `dir-message` log preset of
      #|/// `smithy validate rpc transcript`. Each line is
      #|/// `{"dir":"send","message":<wire JSON>}` or `{"dir":"recv",...}`, from the
      #|/// view of the peer that writes it.
      #|struct TranscriptLog {
      #|  path : String?
      #|  mut file : @fs.File?
      #|  lines : Array[String]
      #|}
      #|
      #|///|
      #|/// A log that writes to the file at `path`. The file is created, or
      #|/// truncated, when the first line is written.
      #|pub fn TranscriptLog::open(path : String) -> TranscriptLog raise TransportError {
      #|  if path == "" {
      #|    raise TransportError(
      #|      "I expected a path for the transcript log, found an empty text.",
      #|    )
      #|  }
      #|  { path: Some(path), file: None, lines: [], }
      #|}
      #|
      #|///|
      #|/// A log that keeps its lines in memory, for tests.
      #|pub fn TranscriptLog::memory() -> TranscriptLog {
      #|  { path: None, file: None, lines: [], }
      #|}
      #|
      #|///|
      #|/// The lines of a memory log, without the line ends. A file log keeps no
      #|/// lines in memory.
      #|pub fn TranscriptLog::lines(self : TranscriptLog) -> Array[String] {
      #|  self.lines
      #|}
      #|
      #|///|
      #|/// Closes the file of the log.
      #|pub fn TranscriptLog::close(self : TranscriptLog) -> Unit {
      #|  if self.file is Some(file) {
      #|    file.close()
      #|    self.file = None
      #|  }
      #|}
      #|
      #|///|
      #|/// The text of one log line. `valid` is false when the wire text is not
      #|/// JSON; the line then holds the text as a JSON string.
      #|fn log_line(dir : String, text : String, valid : Bool) -> String {
      #|  let message = if valid {
      #|    // A raw line end can occur only between JSON tokens, so a space keeps
      #|    // the same JSON value on one line.
      #|    text.replace_all(old="\r", new=" ").replace_all(old="\n", new=" ")
      #|  } else {
      #|    write_json(Json::string(text))
      #|  }
      #|  "{\"dir\":\"\{dir}\",\"message\":\{message}}"
      #|}
      #|
      #|///|
      #|async fn TranscriptLog::record(
      #|  self : TranscriptLog,
      #|  dir : String,
      #|  text : String,
      #|  valid~ : Bool = true,
      #|) -> Unit {
      #|  let line = log_line(dir, text, valid)
      #|  guard self.path is Some(path) else {
      #|    self.lines.push(line)
      #|    return
      #|  }
      #|  let file = match self.file {
      #|    Some(file) => file
      #|    None => {
      #|      let file = @fs.open(path, mode=WriteOnly, create_mode=CreateOrTruncate)
      #|      self.file = Some(file)
      #|      file
      #|    }
      #|  }
      #|  file.write(line + "\n")
      #|}
      #|
    ),
  ),
  (
    "moon.pkg",
    (
      #|import {
      #|  "moonbitlang/async",
      #|  "moonbitlang/async/aqueue",
      #|  "moonbitlang/async/cond_var",
      #|  "moonbitlang/async/fs",
      #|  "moonbitlang/async/io",
      #|  "moonbitlang/async/process",
      #|  "moonbitlang/async/stdio",
      #|  "moonbitlang/core/encoding/base64",
      #|  "moonbitlang/core/encoding/utf8",
      #|  "moonbitlang/core/string",
      #|  "moonbitlang/core/double",
      #|}
      #|
    ),
  ),
  (
    "peer.mbt",
    (
      #|// The dispatcher. Its layers (an envelope reader, a table of handlers, a
      #|// table of pending calls, and a read loop that runs each incoming call in its
      #|// own task) follow moonbitlang/openseek jsonrpc (Apache-2.0). The session
      #|// rules, the cancellation and the transcript log are new.
      #|
      #|///|
      #|/// The message kinds that a method accepts.
      #|pub(all) enum MethodKind {
      #|  RequestOnly
      #|  NotificationOnly
      #|  RequestOrNotification
      #|} derive(Eq, Debug)
      #|
      #|///|
      #|priv enum Handler {
      #|  OnRequest(MethodKind, async (Json?, CallContext) -> Json)
      #|  OnNotification(MethodKind, async (Json?, CallContext) -> Unit)
      #|}
      #|
      #|///|
      #|priv enum Reply {
      #|  Success(Json)
      #|  Failure(Int32, String, Json?)
      #|  Lost(String)
      #|}
      #|
      #|///|
      #|/// A call that this peer sent and that has no reply yet.
      #|priv struct Pending {
      #|  method_name : String
      #|  /// False when the session refused the call; its reply then settles
      #|  /// nothing.
      #|  admitted : Bool
      #|  slot : @aqueue.Queue[Reply]
      #|}
      #|
      #|///|
      #|/// A call that this peer received and did not answer yet.
      #|priv struct Incoming {
      #|  method_name : String
      #|  mut task : @async.Task[Unit]?
      #|  mut cancelled : Bool
      #|}
      #|
      #|///|
      #|priv struct CallReference {
      #|  id_member : String
      #|  position : Int32?
      #|}
      #|
      #|///|
      #|priv struct PeerCore {
      #|  self_name : String
      #|  remote_name : String
      #|  session : Session
      #|  log : TranscriptLog?
      #|  handlers : Map[String, Handler]
      #|  references : Map[String, CallReference]
      #|  mut conn : &Connection?
      #|  mut finished : Bool
      #|  attached : @cond_var.Cond
      #|  lock : @async.Mutex
      #|  mut next_id : Int64
      #|  pending : Map[RequestId, Pending]
      #|  active : Map[RequestId, Incoming]
      #|}
      #|
      #|///|
      #|/// One peer of a JSON-RPC session. It answers the calls of the remote peer
      #|/// with its handlers, and it calls the remote peer.
      #|///
      #|/// A Peer that `CallContext::peer` gives belongs to one incoming call: the
      #|/// messages that it sends are related to that call (see `Connection`).
      #|struct Peer {
      #|  core : PeerCore
      #|  scope : RequestId?
      #|}
      #|
      #|///|
      #|/// The incoming call that a handler answers.
      #|struct CallContext {
      #|  request_id : RequestId?
      #|  name : String
      #|  owner : Peer
      #|}
      #|
      #|///|
      #|/// The ID of the call, or None for a notification.
      #|pub fn CallContext::id(self : CallContext) -> RequestId? {
      #|  self.request_id
      #|}
      #|
      #|///|
      #|/// The ID of the call as JSON, or null for a notification. A progress
      #|/// notification uses it to name the running call.
      #|pub fn CallContext::id_json(self : CallContext) -> Json {
      #|  match self.request_id {
      #|    Some(id) => id.to_json()
      #|    None => Json::null()
      #|  }
      #|}
      #|
      #|///|
      #|/// The method of the call.
      #|pub fn CallContext::method_name(self : CallContext) -> String {
      #|  self.name
      #|}
      #|
      #|///|
      #|/// The peer that received the call. The messages that it sends while the
      #|/// call runs are related to the call.
      #|pub fn CallContext::peer(self : CallContext) -> Peer {
      #|  { core: self.owner.core, scope: self.request_id, }
      #|}
      #|
      #|///|
      #|pub fn Peer::new(
      #|  self_name~ : String,
      #|  remote_name~ : String,
      #|  rules~ : SessionRules,
      #|  log~ : TranscriptLog? = None,
      #|) -> Peer {
      #|  let core : PeerCore = {
      #|    self_name,
      #|    remote_name,
      #|    session: Session::new(rules),
      #|    log,
      #|    handlers: Map([]),
      #|    references: Map([]),
      #|    conn: None,
      #|    finished: false,
      #|    attached: @cond_var.Cond(),
      #|    lock: @async.Mutex(),
      #|    next_id: 1L,
      #|    pending: Map([]),
      #|    active: Map([]),
      #|  }
      #|  { core, scope: None, }
      #|}
      #|
      #|///|
      #|/// The name of this peer.
      #|pub fn Peer::self_name(self : Peer) -> String {
      #|  self.core.self_name
      #|}
      #|
      #|///|
      #|/// The current session state.
      #|pub fn Peer::state(self : Peer) -> String {
      #|  self.core.session.state
      #|}
      #|
      #|///|
      #|/// Whether a result advertised the capability.
      #|pub fn Peer::advertised(self : Peer, capability : String) -> Bool {
      #|  self.core.session.advertised.contains(capability)
      #|}
      #|
      #|///|
      #|/// Registers the handler of a method that this peer accepts. The handler
      #|/// gives the result; use `Json::null()` for a method without a result.
      #|pub fn Peer::on_request(
      #|  self : Peer,
      #|  method_name : String,
      #|  kind : MethodKind,
      #|  handler : async (Json?, CallContext) -> Json,
      #|) -> Unit {
      #|  self.core.handlers[method_name] = OnRequest(kind, handler)
      #|}
      #|
      #|///|
      #|/// Registers the handler of a notification that this peer accepts.
      #|pub fn Peer::on_notification(
      #|  self : Peer,
      #|  method_name : String,
      #|  kind : MethodKind,
      #|  handler : async (Json?, CallContext) -> Unit,
      #|) -> Unit {
      #|  self.core.handlers[method_name] = OnNotification(kind, handler)
      #|}
      #|
      #|///|
      #|/// Declares that a received notification of `method_name` names an active
      #|/// call that this peer sent, in the params member `id_member` (or at
      #|/// `position` for positional params). The peer drops such a notification
      #|/// when no such call is pending, and writes a diagnostic to stderr.
      #|pub fn Peer::call_reference(
      #|  self : Peer,
      #|  method_name : String,
      #|  id_member~ : String,
      #|  position~ : Int32?,
      #|) -> Unit {
      #|  self.core.references[method_name] = { id_member, position, }
      #|}
      #|
      #|///|
      #|/// Serializes the diagnostics: stderr accepts one write at a time.
      #|let stderr_lock : @async.Mutex = @async.Mutex()
      #|
      #|///|
      #|/// Writes a diagnostic line to stderr. A diagnostic never goes to stdout.
      #|async fn diagnose(message : String) -> Unit {
      #|  stderr_lock.acquire()
      #|  defer stderr_lock.release()
      #|  @stdio.stderr.write(message + "\n") catch {
      #|    _ => ()
      #|  }
      #|}
      #|
      #|///|
      #|/// Runs `f` while the peer holds its lock, and protects it from
      #|/// cancellation, so that a log line, its session change and its wire text
      #|/// stay together and in order.
      #|async fn[T] PeerCore::locked(self : PeerCore, f : async () -> T) -> T {
      #|  self.lock.acquire()
      #|  defer self.lock.release()
      #|  let result : Result[T, Error] = @async.protect_from_cancel(() => {
      #|    try f() catch {
      #|      err => Err(err)
      #|    } noraise {
      #|      value => Ok(value)
      #|    }
      #|  })
      #|  match result {
      #|    Ok(value) => value
      #|    Err(err) => raise err
      #|  }
      #|}
      #|
      #|///|
      #|/// Waits until `run` attaches a connection.
      #|async fn PeerCore::connection(self : PeerCore) -> &Connection {
      #|  while true {
      #|    if self.conn is Some(conn) {
      #|      return conn
      #|    }
      #|    if self.finished {
      #|      raise TransportError(
      #|        "I have no connection: the session with \{self.remote_name} ended.",
      #|      )
      #|    }
      #|    self.attached.wait()
      #|  }
      #|  panic()
      #|}
      #|
      #|///|
      #|/// The incoming call that a message sent outside a handler is related to:
      #|/// the latest active call.
      #|fn PeerCore::latest_call(self : PeerCore) -> RequestId? {
      #|  let mut last = None
      #|  for id, _ in self.active {
      #|    last = Some(id)
      #|  }
      #|  last
      #|}
      #|
      #|///|
      #|/// Writes a message to the log and to the wire. The caller holds the lock.
      #|async fn PeerCore::send_locked(
      #|  self : PeerCore,
      #|  conn : &Connection,
      #|  message : Json,
      #|  related : RequestId?,
      #|) -> Unit {
      #|  let text = write_json(message)
      #|  if self.log is Some(log) {
      #|    log.record("send", text)
      #|  }
      #|  conn.send(text, related~)
      #|}
      #|
      #|///|
      #|fn request_message(
      #|  id : RequestId?,
      #|  method_name : String,
      #|  params : Json?,
      #|) -> Json {
      #|  let fields : Map[String, Json] = Map([("jsonrpc", Json::string("2.0"))])
      #|  if id is Some(id) {
      #|    fields["id"] = id.to_json()
      #|  }
      #|  fields["method"] = Json::string(method_name)
      #|  if params is Some(params) {
      #|    fields["params"] = params
      #|  }
      #|  Json::object(fields)
      #|}
      #|
      #|///|
      #|fn result_message(id : RequestId, result : Json) -> Json {
      #|  Json::object(
      #|    Map([
      #|      ("jsonrpc", Json::string("2.0")),
      #|      ("id", id.to_json()),
      #|      ("result", result),
      #|    ]),
      #|  )
      #|}
      #|
      #|///|
      #|fn error_message(
      #|  id : RequestId?,
      #|  code : Int32,
      #|  message : String,
      #|  data : Json?,
      #|) -> Json {
      #|  let error : Map[String, Json] = Map([
      #|    ("code", Json::number(code.to_double())),
      #|    ("message", Json::string(message)),
      #|  ])
      #|  if data is Some(data) {
      #|    error["data"] = data
      #|  }
      #|  Json::object(
      #|    Map([
      #|      ("jsonrpc", Json::string("2.0")),
      #|      (
      #|        "id",
      #|        match id {
      #|          Some(id) => id.to_json()
      #|          None => Json::null()
      #|        },
      #|      ),
      #|      ("error", Json::object(error)),
      #|    ]),
      #|  )
      #|}
      #|
      #|///|
      #|/// Sends a request and waits for its result. With `checked` true, a call
      #|/// that the session refuses raises the modeled RpcError, and nothing is sent.
      #|/// An error response raises RpcError with its code, message and data.
      #|pub async fn Peer::request(
      #|  self : Peer,
      #|  method_name : String,
      #|  params : Json?,
      #|  checked~ : Bool = true,
      #|) -> Json {
      #|  let core = self.core
      #|  let conn = core.connection()
      #|  let slot : @aqueue.Queue[Reply] = @aqueue.Queue(kind=Unbounded)
      #|  let id = core.locked(() => {
      #|    if core.finished {
      #|      raise TransportError(
      #|        "I have no connection: the session with \{core.remote_name} ended.",
      #|      )
      #|    }
      #|    let admission = core.session.check(core.remote_name, method_name)
      #|    if checked && admission is Refused(code, message) {
      #|      raise RpcError(code~, message~, data=None)
      #|    }
      #|    core.session.accept(admission)
      #|    let id = RequestId::Number(core.next_id.to_string())
      #|    core.next_id += 1L
      #|    core.pending[id] = {
      #|      method_name,
      #|      admitted: !(admission is Refused(_, _)),
      #|      slot,
      #|    }
      #|    let related = match self.scope {
      #|      Some(scope) => Some(scope)
      #|      None => core.latest_call()
      #|    }
      #|    errdefer core.pending.remove(id)
      #|    core.send_locked(
      #|      conn,
      #|      request_message(Some(id), method_name, params),
      #|      related,
      #|    )
      #|    id
      #|  })
      #|  defer core.pending.remove(id)
      #|  match slot.get() {
      #|    Success(result) => result
      #|    Failure(code, message, data) => raise RpcError(code~, message~, data~)
      #|    Lost(message) => raise TransportError(message)
      #|  }
      #|}
      #|
      #|///|
      #|/// Sends a notification. With `checked` true, a notification that the session
      #|/// refuses raises the modeled RpcError, and nothing is sent.
      #|pub async fn Peer::notify(
      #|  self : Peer,
      #|  method_name : String,
      #|  params : Json?,
      #|  checked~ : Bool = true,
      #|) -> Unit {
      #|  let core = self.core
      #|  let conn = core.connection()
      #|  core.locked(() => {
      #|    let admission = core.session.check(core.remote_name, method_name)
      #|    if checked && admission is Refused(code, message) {
      #|      raise RpcError(code~, message~, data=None)
      #|    }
      #|    core.session.accept(admission)
      #|    let related = match self.scope {
      #|      Some(scope) => Some(scope)
      #|      None => core.latest_call()
      #|    }
      #|    core.send_locked(conn, request_message(None, method_name, params), related)
      #|  })
      #|}
      #|
      #|///|
      #|/// Reads and answers messages from `conn` until the remote peer closes it.
      #|/// Each incoming call runs in its own task, so that a handler can call the
      #|/// remote peer while its call runs. When `run` returns, the calls that still
      #|/// run are cancelled, and the pending calls of this peer fail with a
      #|/// TransportError.
      #|pub async fn Peer::run(self : Peer, conn : &Connection) -> Unit {
      #|  let core = self.core
      #|  if core.conn is Some(_) || core.finished {
      #|    raise TransportError(
      #|      "I expected one connection for the peer \{core.self_name}; run was called again.",
      #|    )
      #|  }
      #|  core.conn = Some(conn)
      #|  core.attached.broadcast()
      #|  defer core.finish()
      #|  @async.with_task_group(group => {
      #|    while conn.receive() is Some(text) {
      #|      core.locked(() => core.receive_locked(group, conn, text))
      #|    }
      #|    group.return_immediately(())
      #|  })
      #|}
      #|
      #|///|
      #|/// Ends the session: no later call can be sent, and each pending call fails.
      #|fn PeerCore::finish(self : PeerCore) -> Unit {
      #|  self.finished = true
      #|  self.conn = None
      #|  self.attached.broadcast()
      #|  for _, pending in self.pending {
      #|    let _ = pending.slot.try_put(
      #|      Lost("I lost the connection before the reply to \{pending.method_name}."),
      #|    ) catch {
      #|      _ => false
      #|    }
      #|  }
      #|  for _, incoming in self.active {
      #|    incoming.cancelled = true
      #|  }
      #|  if self.log is Some(log) {
      #|    log.close()
      #|  }
      #|}
      #|
      #|///|
      #|/// The params member that names a call.
      #|fn named_call(params : Json?, key : String, position : Int32?) -> RequestId? {
      #|  let raw = match params {
      #|    Some(Object(fields)) => fields.get(key)
      #|    Some(Array(items)) => position.bind(i => items.get(i))
      #|    _ => None
      #|  }
      #|  raw.bind(RequestId::from_json)
      #|}
      #|
      #|///|
      #|/// Handles one received message. The caller holds the lock.
      #|async fn[G] PeerCore::receive_locked(
      #|  self : PeerCore,
      #|  group : @async.TaskGroup[G],
      #|  conn : &Connection,
      #|  text : String,
      #|) -> Unit {
      #|  let parsed : Result[Json, Error] = try parse_json(text) catch {
      #|    err => Err(err)
      #|  } noraise {
      #|    value => Ok(value)
      #|  }
      #|  if self.log is Some(log) {
      #|    log.record("recv", text, valid=parsed is Ok(_))
      #|  }
      #|  let value = match parsed {
      #|    Ok(value) => value
      #|    Err(err) => {
      #|      let detail = match err {
      #|        DecodeError(message~, ..) => message
      #|        other => "\{other}"
      #|      }
      #|      self.send_locked(
      #|        conn,
      #|        error_message(
      #|          None,
      #|          parse_error_code,
      #|          "I could not parse the message as JSON: \{detail}",
      #|          None,
      #|        ),
      #|        None,
      #|      )
      #|      return
      #|    }
      #|  }
      #|  guard value is Object(fields) else {
      #|    let message = if value is Array(_) {
      #|      "I do not accept a batch; I received a JSON array."
      #|    } else {
      #|      "I expected a valid JSON-RPC 2.0 request; I found \{json_kind(value)}."
      #|    }
      #|    self.send_locked(
      #|      conn,
      #|      error_message(None, invalid_request_code, message, None),
      #|      None,
      #|    )
      #|    return
      #|  }
      #|  if fields.get("method") is None &&
      #|    (fields.get("result") is Some(_) || fields.get("error") is Some(_)) {
      #|    self.receive_reply(fields)
      #|    return
      #|  }
      #|  // A request or a notification.
      #|  let raw_id = fields.get("id")
      #|  let id = raw_id.bind(RequestId::from_json)
      #|  let usable_id = if raw_id is Some(_) && id is None { None } else { id }
      #|  let invalid = (detail : String) => {
      #|    error_message(
      #|      usable_id,
      #|      invalid_request_code,
      #|      "I expected a valid JSON-RPC 2.0 request; I found \{detail}.",
      #|      None,
      #|    )
      #|  }
      #|  guard fields.get("jsonrpc") is Some(String("2.0")) else {
      #|    self.send_locked(
      #|      conn,
      #|      invalid("no jsonrpc member with the value 2.0"),
      #|      usable_id,
      #|    )
      #|    return
      #|  }
      #|  guard fields.get("method") is Some(String(method_name)) else {
      #|    self.send_locked(
      #|      conn,
      #|      invalid("a method member that is not a string"),
      #|      usable_id,
      #|    )
      #|    return
      #|  }
      #|  if raw_id is Some(raw) && id is None {
      #|    self.send_locked(
      #|      conn,
      #|      invalid("an id that is not a string or an integer: \{write_json(raw)}"),
      #|      None,
      #|    )
      #|    return
      #|  }
      #|  let params = fields.get("params")
      #|  match params {
      #|    None | Some(Object(_)) | Some(Array(_)) => ()
      #|    Some(other) => {
      #|      self.send_locked(conn, invalid("params that are \{json_kind(other)}"), id)
      #|      return
      #|    }
      #|  }
      #|  let handler = self.handlers.get(method_name)
      #|  let rule = self.session.rules.rule(self.self_name, method_name)
      #|  // A method is modeled when it has a handler, or a cancel rule that the
      #|  // runtime applies itself.
      #|  let modeled = handler is Some(_) || (rule is Some(r) && r.cancels is Some(_))
      #|  if !modeled {
      #|    if id is Some(id) {
      #|      self.send_locked(
      #|        conn,
      #|        error_message(
      #|          Some(id),
      #|          method_not_found_code,
      #|          "I do not know method \{method_name}.",
      #|          None,
      #|        ),
      #|        Some(id),
      #|      )
      #|    } else {
      #|      diagnose(
      #|        "I dropped the notification \{method_name}, which I do not know.",
      #|      )
      #|    }
      #|    return
      #|  }
      #|  if id is None && self.references.get(method_name) is Some(reference) {
      #|    let named = named_call(params, reference.id_member, reference.position)
      #|    if !(named is Some(call) && self.pending.contains(call)) {
      #|      diagnose(
      #|        "I dropped the notification \{method_name}, because it names no call that is pending.",
      #|      )
      #|      return
      #|    }
      #|  }
      #|  let admission = self.session.check(self.self_name, method_name)
      #|  if admission is Refused(code, message) {
      #|    match id {
      #|      Some(id) =>
      #|        self.send_locked(
      #|          conn,
      #|          error_message(Some(id), code, message, None),
      #|          Some(id),
      #|        )
      #|      None => diagnose("I dropped the notification \{method_name}: \{message}")
      #|    }
      #|    return
      #|  }
      #|  self.session.accept(admission)
      #|  if admission is Accepted(rule) && rule.cancels is Some(cancel) {
      #|    self.cancel_locked(conn, params, cancel)
      #|  }
      #|  match (id, handler) {
      #|    (Some(id), Some(OnNotification(NotificationOnly, _))) =>
      #|      self.reply_locked(
      #|        conn,
      #|        id,
      #|        method_name,
      #|        Err(
      #|          (
      #|            invalid_request_code,
      #|            "I expected a notification for method \{method_name}; I received a request.",
      #|            None,
      #|          ),
      #|        ),
      #|      )
      #|    (Some(id), None) =>
      #|      // A cancel method without a handler, sent as a request.
      #|      self.reply_locked(conn, id, method_name, Ok(Json::null()))
      #|    (Some(id), Some(handler)) =>
      #|      self.start_call(group, conn, id, method_name, handler, params)
      #|    (None, Some(OnRequest(RequestOnly, _))) =>
      #|      diagnose(
      #|        "I dropped the notification \{method_name}, because the method needs a request.",
      #|      )
      #|    (None, Some(OnRequest(_, f))) =>
      #|      self.start_notification(group, method_name, async fn(ctx) {
      #|        f(params, ctx) |> ignore
      #|      })
      #|    (None, Some(OnNotification(_, f))) =>
      #|      self.start_notification(group, method_name, async fn(ctx) {
      #|        f(params, ctx)
      #|      })
      #|    (None, None) => ()
      #|  }
      #|}
      #|
      #|///|
      #|/// Cancels the call that a cancel message names, and answers that call with
      #|/// the modeled code. A call that is not active is not changed.
      #|async fn PeerCore::cancel_locked(
      #|  self : PeerCore,
      #|  conn : &Connection,
      #|  params : Json?,
      #|  rule : CancelRule,
      #|) -> Unit {
      #|  guard named_call(params, rule.id_member, rule.position) is Some(id) &&
      #|    self.active.get(id) is Some(incoming) &&
      #|    !incoming.cancelled else {
      #|    return
      #|  }
      #|  incoming.cancelled = true
      #|  if incoming.task is Some(task) {
      #|    task.cancel()
      #|  }
      #|  self.reply_locked(
      #|    conn,
      #|    id,
      #|    incoming.method_name,
      #|    Err(
      #|      (
      #|        rule.code.unwrap_or(request_cancelled_code),
      #|        "I cancelled \{incoming.method_name}.",
      #|        None,
      #|      ),
      #|    ),
      #|  )
      #|}
      #|
      #|///|
      #|/// Sends the reply of an accepted incoming call, and settles the session.
      #|/// The caller holds the lock.
      #|async fn PeerCore::reply_locked(
      #|  self : PeerCore,
      #|  conn : &Connection,
      #|  id : RequestId,
      #|  method_name : String,
      #|  outcome : Result[Json, (Int32, String, Json?)],
      #|) -> Unit {
      #|  self.active.remove(id)
      #|  let message = match outcome {
      #|    Ok(result) => result_message(id, result)
      #|    Err((code, text, data)) => error_message(Some(id), code, text, data)
      #|  }
      #|  match outcome {
      #|    Ok(result) =>
      #|      self.session.settle(self.self_name, method_name, false, Some(result))
      #|    Err(_) => self.session.settle(self.self_name, method_name, true, None)
      #|  }
      #|  self.send_locked(conn, message, Some(id))
      #|}
      #|
      #|///|
      #|/// Maps an error of a handler to the error of its reply.
      #|fn handler_error(method_name : String, err : Error) -> (Int32, String, Json?) {
      #|  match err {
      #|    RpcError(code~, message~, data~) => (code, message, data)
      #|    DecodeError(path~, message~) =>
      #|      (
      #|        invalid_params_code,
      #|        "I could not decode \{method_name} params at \{path}: \{message}",
      #|        None,
      #|      )
      #|    other =>
      #|      (internal_error_code, "I could not handle \{method_name}: \{other}", None)
      #|  }
      #|}
      #|
      #|///|
      #|/// Runs the handler of an incoming call in its own task. The caller holds the
      #|/// lock.
      #|fn[G] PeerCore::start_call(
      #|  self : PeerCore,
      #|  group : @async.TaskGroup[G],
      #|  conn : &Connection,
      #|  id : RequestId,
      #|  method_name : String,
      #|  handler : Handler,
      #|  params : Json?,
      #|) -> Unit {
      #|  let incoming : Incoming = { method_name, task: None, cancelled: false, }
      #|  self.active[id] = incoming
      #|  let ctx : CallContext = {
      #|    request_id: Some(id),
      #|    name: method_name,
      #|    owner: { core: self, scope: Some(id), },
      #|  }
      #|  let task = group.spawn(allow_failure=true, () => {
      #|    let outcome = try {
      #|      match handler {
      #|        OnRequest(_, f) => Ok(f(params, ctx))
      #|        OnNotification(_, f) => {
      #|          f(params, ctx)
      #|          Ok(Json::null())
      #|        }
      #|      }
      #|    } catch {
      #|      err => Err(handler_error(method_name, err))
      #|    }
      #|    if incoming.cancelled || @async.is_being_cancelled() {
      #|      return
      #|    }
      #|    self.locked(() => {
      #|      // A cancel message may have answered the call while this task waited
      #|      // for the lock.
      #|      if incoming.cancelled || self.finished {
      #|        return
      #|      }
      #|      self.reply_locked(conn, id, method_name, outcome)
      #|    }) catch {
      #|      err => diagnose("I could not send the reply to \{method_name}: \{err}")
      #|    }
      #|  })
      #|  incoming.task = Some(task)
      #|}
      #|
      #|///|
      #|/// Runs the handler of an incoming notification in its own task. An error
      #|/// of the handler goes to stderr.
      #|fn[G] PeerCore::start_notification(
      #|  self : PeerCore,
      #|  group : @async.TaskGroup[G],
      #|  method_name : String,
      #|  f : async (CallContext) -> Unit,
      #|) -> Unit {
      #|  let ctx : CallContext = {
      #|    request_id: None,
      #|    name: method_name,
      #|    owner: { core: self, scope: None, },
      #|  }
      #|  group.spawn_bg(allow_failure=true, () => {
      #|    f(ctx) catch {
      #|      err =>
      #|        if !@async.is_being_cancelled() {
      #|          diagnose("I could not handle the notification \{method_name}: \{err}")
      #|        }
      #|    }
      #|  })
      #|}
      #|
      #|///|
      #|/// Gives a reply to the call that waits for it, and settles the session.
      #|fn PeerCore::receive_reply(self : PeerCore, fields : Map[String, Json]) -> Unit {
      #|  guard fields.get("id").bind(RequestId::from_json) is Some(id) &&
      #|    self.pending.get(id) is Some(pending) else {
      #|    // A reply without a pending call: an error about a message that the
      #|    // remote peer could not read, or a late reply.
      #|    return
      #|  }
      #|  self.pending.remove(id)
      #|  let reply = match fields.get("error") {
      #|    Some(Object(error)) => {
      #|      let code = match error.get("code").bind(RequestId::from_json) {
      #|        Some(Number(text)) =>
      #|          @string.parse_int(text) catch {
      #|            _ => internal_error_code
      #|          }
      #|        _ => internal_error_code
      #|      }
      #|      let message = match error.get("message") {
      #|        Some(String(text)) => text
      #|        _ => ""
      #|      }
      #|      Failure(code, message, error.get("data"))
      #|    }
      #|    Some(Null) | None => Success(fields.get("result").unwrap_or(Json::null()))
      #|    Some(other) =>
      #|      Failure(
      #|        internal_error_code,
      #|        "I expected an error object in the reply, found \{json_kind(other)}.",
      #|        None,
      #|      )
      #|  }
      #|  if pending.admitted {
      #|    match reply {
      #|      Success(result) =>
      #|        self.session.settle(
      #|          self.remote_name,
      #|          pending.method_name,
      #|          false,
      #|          Some(result),
      #|        )
      #|      _ =>
      #|        self.session.settle(self.remote_name, pending.method_name, true, None)
      #|    }
      #|  }
      #|  let _ = pending.slot.try_put(reply) catch { _ => false }
      #|}
      #|
    ),
  ),
  (
    "session.mbt",
    (
      #|// The session engine. The generator renders the rules from the prepared
      #|// session contract. The semantics follow the transcript checker in
      #|// pkgs/smithy-validation/rpc (transcript_order.mbt), so that a peer and the
      #|// checker agree about each message:
      #|//
      #|// - One session state. Each peer applies every message that it sends or
      #|//   receives, in the order of its transcript.
      #|// - A request or notification is refused when its method is not allowed in
      #|//   the current state, or when a required capability is not advertised. A
      #|//   refused message causes no transition, and its reply settles nothing.
      #|// - An accepted message applies `on_call`, then its cancellation.
      #|// - The reply of an accepted call applies `on_error` or `on_success` of the
      #|//   rule of the responding peer. A result advertises each capability of a
      #|//   source of that method, unless the value at the pointer is absent, null or
      #|//   false. A capability is never removed.
      #|
      #|///|
      #|/// A capability that the successful result of a method advertises.
      #|pub struct CapabilitySource {
      #|  name : String
      #|  method_name : String
      #|  /// A JSON Pointer into the result.
      #|  pointer : String
      #|} derive(Eq, Debug)
      #|
      #|///|
      #|pub fn CapabilitySource::new(
      #|  name~ : String,
      #|  method_name~ : String,
      #|  pointer~ : String,
      #|) -> CapabilitySource {
      #|  { name, method_name, pointer, }
      #|}
      #|
      #|///|
      #|/// How a method cancels a call: the params member (or the position) that
      #|/// holds the ID of the call, and the error code of the cancelled call.
      #|pub struct CancelRule {
      #|  id_member : String
      #|  position : Int32?
      #|  code : Int32?
      #|} derive(Eq, Debug)
      #|
      #|///|
      #|pub fn CancelRule::new(
      #|  id_member~ : String,
      #|  position~ : Int32?,
      #|  code~ : Int32?,
      #|) -> CancelRule {
      #|  { id_member, position, code, }
      #|}
      #|
      #|///|
      #|/// The order rules of one method that one peer receives.
      #|pub struct MethodRule {
      #|  receiver : String
      #|  method_name : String
      #|  /// None means every state.
      #|  allowed : Array[String]?
      #|  on_call : String?
      #|  on_success : String?
      #|  on_error : String?
      #|  /// The capability names that must be advertised.
      #|  requires : Array[String]
      #|  cancels : CancelRule?
      #|} derive(Eq, Debug)
      #|
      #|///|
      #|pub fn MethodRule::new(
      #|  receiver~ : String,
      #|  method_name~ : String,
      #|  allowed~ : Array[String]?,
      #|  on_call~ : String?,
      #|  on_success~ : String?,
      #|  on_error~ : String?,
      #|  requires~ : Array[String],
      #|  cancels~ : CancelRule?,
      #|) -> MethodRule {
      #|  {
      #|    receiver,
      #|    method_name,
      #|    allowed,
      #|    on_call,
      #|    on_success,
      #|    on_error,
      #|    requires,
      #|    cancels,
      #|  }
      #|}
      #|
      #|///|
      #|/// The session contract of a protocol. The first state is the initial state.
      #|pub struct SessionRules {
      #|  states : Array[String]
      #|  capabilities : Array[CapabilitySource]
      #|  priv methods : Map[String, Map[String, MethodRule]]
      #|  priv refusals : Map[String, Int32]
      #|  capability_refusal : Int32?
      #|}
      #|
      #|///|
      #|pub fn SessionRules::new(
      #|  states~ : Array[String],
      #|  capabilities~ : Array[CapabilitySource],
      #|  methods~ : Array[MethodRule],
      #|  refusals~ : Array[(String, Int32)],
      #|  capability_refusal~ : Int32?,
      #|) -> SessionRules {
      #|  let by_receiver : Map[String, Map[String, MethodRule]] = Map([])
      #|  for rule in methods {
      #|    match by_receiver.get(rule.receiver) {
      #|      Some(rules) => rules[rule.method_name] = rule
      #|      None => by_receiver[rule.receiver] = Map([(rule.method_name, rule)])
      #|    }
      #|  }
      #|  let codes = Map([])
      #|  for refusal in refusals {
      #|    codes[refusal.0] = refusal.1
      #|  }
      #|  {
      #|    states,
      #|    capabilities,
      #|    methods: by_receiver,
      #|    refusals: codes,
      #|    capability_refusal,
      #|  }
      #|}
      #|
      #|///|
      #|/// No session: every method is allowed in every state.
      #|pub fn SessionRules::none() -> SessionRules {
      #|  SessionRules::new(
      #|    states=[],
      #|    capabilities=[],
      #|    methods=[],
      #|    refusals=[],
      #|    capability_refusal=None,
      #|  )
      #|}
      #|
      #|///|
      #|/// The rule of `method_name` when `receiver` receives it.
      #|pub fn SessionRules::rule(
      #|  self : SessionRules,
      #|  receiver : String,
      #|  method_name : String,
      #|) -> MethodRule? {
      #|  self.methods.get(receiver).bind(rules => rules.get(method_name))
      #|}
      #|
      #|///|
      #|/// The code for a call refused in `state`. It is -32600 when the model gives
      #|/// no code for that state.
      #|pub fn SessionRules::state_refusal_code(
      #|  self : SessionRules,
      #|  state : String,
      #|) -> Int32 {
      #|  self.refusals.get(state).unwrap_or(invalid_request_code)
      #|}
      #|
      #|///|
      #|/// The outcome of the session check of a request or a notification.
      #|priv enum Admission {
      #|  /// The method has no rule; it is accepted.
      #|  Free
      #|  Accepted(MethodRule)
      #|  Refused(Int32, String)
      #|}
      #|
      #|///|
      #|/// The session state that one peer keeps.
      #|priv struct Session {
      #|  rules : SessionRules
      #|  mut state : String
      #|  advertised : Set[String]
      #|}
      #|
      #|///|
      #|fn Session::new(rules : SessionRules) -> Session {
      #|  { rules, state: rules.states.get(0).unwrap_or(""), advertised: Set([]), }
      #|}
      #|
      #|///|
      #|/// Checks a request or a notification that `receiver` receives, and does not
      #|/// change the session.
      #|fn Session::check(
      #|  self : Session,
      #|  receiver : String,
      #|  method_name : String,
      #|) -> Admission {
      #|  guard self.rules.rule(receiver, method_name) is Some(rule) else {
      #|    return Free
      #|  }
      #|  if rule.allowed is Some(allowed) && !allowed.contains(self.state) {
      #|    return Refused(
      #|      self.rules.state_refusal_code(self.state),
      #|      "I refused \{method_name} in state \{self.state}.",
      #|    )
      #|  }
      #|  for capability in rule.requires {
      #|    if !self.advertised.contains(capability) {
      #|      return Refused(
      #|        self.rules.capability_refusal.unwrap_or(invalid_request_code),
      #|        "I refused \{method_name} because \{capability} is not advertised.",
      #|      )
      #|    }
      #|  }
      #|  Accepted(rule)
      #|}
      #|
      #|///|
      #|/// Applies the transition of an accepted message.
      #|fn Session::accept(self : Session, admission : Admission) -> Unit {
      #|  if admission is Accepted(rule) && rule.on_call is Some(next) {
      #|    self.state = next
      #|  }
      #|}
      #|
      #|///|
      #|/// Applies the reply of an accepted call of `method_name` that `responder`
      #|/// received. `result` is the result of a success reply.
      #|fn Session::settle(
      #|  self : Session,
      #|  responder : String,
      #|  method_name : String,
      #|  failed : Bool,
      #|  result : Json?,
      #|) -> Unit {
      #|  if !failed && result is None {
      #|    return
      #|  }
      #|  if self.rules.rule(responder, method_name) is Some(rule) {
      #|    let next = if failed { rule.on_error } else { rule.on_success }
      #|    if next is Some(state) {
      #|      self.state = state
      #|    }
      #|  }
      #|  guard result is Some(result) else { return }
      #|  for source in self.rules.capabilities {
      #|    if source.method_name == method_name {
      #|      match resolve_pointer(result, source.pointer) {
      #|        None | Some(Null) | Some(False) => ()
      #|        Some(_) => self.advertised.add(source.name)
      #|      }
      #|    }
      #|  }
      #|}
      #|
    ),
  ),
  (
    "stdio.mbt",
    (
      #|// The stdio transport: `Content-Length: N\r\n\r\n` and then N bytes of UTF-8
      #|// JSON, as in LSP. A reader ignores the headers that it does not know, such
      #|// as Content-Type. Diagnostics go to stderr, never to stdout.
      #|
      #|///|
      #|/// The largest frame body that a reader accepts: 64 MiB.
      #|pub let max_frame_bytes : Int32 = 64 * 1024 * 1024
      #|
      #|///|
      #|fn header_lines(lines : Array[String]) -> String {
      #|  if lines.is_empty() {
      #|    "no header"
      #|  } else {
      #|    lines.map(line => "'" + line + "'").join(", ")
      #|  }
      #|}
      #|
      #|///|
      #|/// Reads one frame. It gives None at the end of the input before a frame.
      #|pub async fn[R : @io.Reader] read_frame(reader : R) -> String? {
      #|  let headers : Array[String] = []
      #|  let mut length : Int32? = None
      #|  while true {
      #|    let line = match reader.read_until("\n") {
      #|      Some(line) =>
      #|        if line.has_suffix("\r") {
      #|          line[:line.length() - 1].to_owned()
      #|        } else {
      #|          line
      #|        }
      #|      None =>
      #|        if headers.is_empty() {
      #|          return None
      #|        } else {
      #|          raise TransportError(
      #|            "I expected the empty line at the end of the frame headers, found the end of the input after \{header_lines(headers)}.",
      #|          )
      #|        }
      #|    }
      #|    if line == "" {
      #|      break
      #|    }
      #|    headers.push(line)
      #|    guard line.find(":") is Some(colon) else {
      #|      raise TransportError(
      #|        "I expected a frame header of the form 'Name: value', found '\{line}'.",
      #|      )
      #|    }
      #|    let name = line[:colon].to_owned().trim(chars=" \t").to_lower()
      #|    if name == "content-length" {
      #|      let value = line[colon + 1:].to_owned().trim(chars=" \t").to_owned()
      #|      let n = if value != "" && value.iter().all(c => c >= '0' && c <= '9') {
      #|        @string.parse_int(value) catch {
      #|          _ => -1
      #|        }
      #|      } else {
      #|        -1
      #|      }
      #|      if n < 0 || n > max_frame_bytes {
      #|        raise TransportError(
      #|          "I expected a byte count of at most \{max_frame_bytes} in the Content-Length header, found '\{value}'.",
      #|        )
      #|      }
      #|      length = Some(n)
      #|    }
      #|  }
      #|  guard length is Some(n) else {
      #|    raise TransportError(
      #|      "I expected a Content-Length header in the frame, found \{header_lines(headers)}.",
      #|    )
      #|  }
      #|  let body = reader.read_exactly(n) catch {
      #|    @io.ReaderClosed =>
      #|      raise TransportError(
      #|        "I expected \{n} bytes of the frame body, found the end of the input.",
      #|      )
      #|    err => raise err
      #|  }
      #|  let text = @utf8.decode(body) catch {
      #|    _ =>
      #|      raise TransportError(
      #|        "I expected UTF-8 text in the frame body, found other bytes.",
      #|      )
      #|  }
      #|  Some(text)
      #|}
      #|
      #|///|
      #|/// Writes one frame with a Content-Length header.
      #|pub async fn[W : @io.Writer] write_frame(writer : W, text : String) -> Unit {
      #|  let body = @utf8.encode(text)
      #|  // The header is ASCII, so one encoded text holds the header and the body.
      #|  writer.write(@utf8.encode("Content-Length: \{body.length()}\r\n\r\n" + text))
      #|}
      #|
      #|///|
      #|/// The stdio of this process as a connection: frames are read from stdin and
      #|/// written to stdout.
      #|struct StdioConnection {
      #|  mut closed : Bool
      #|}
      #|
      #|///|
      #|pub fn stdio_connection() -> StdioConnection {
      #|  { closed: false, }
      #|}
      #|
      #|///|
      #|pub impl Connection for StdioConnection with fn receive(self) {
      #|  if self.closed {
      #|    return None
      #|  }
      #|  read_frame(@stdio.stdin)
      #|}
      #|
      #|///|
      #|pub impl Connection for StdioConnection with fn send(self, text, related~) {
      #|  ignore(related)
      #|  if self.closed {
      #|    raise TransportError("I could not send the message: stdio is closed.")
      #|  }
      #|  write_frame(@stdio.stdout, text)
      #|}
      #|
      #|///|
      #|pub impl Connection for StdioConnection with fn close(self) {
      #|  self.closed = true
      #|}
      #|
      #|///|
      #|/// A child process as a connection: frames are written to its stdin and
      #|/// read from its stdout. Its stderr is the stderr of this process.
      #|struct ProcessConnection {
      #|  pid : Int32
      #|  reader : @process.ReadFromProcess
      #|  writer : @process.WriteToProcess
      #|  mut closed : Bool
      #|}
      #|
      #|///|
      #|/// Starts `argv` as a child process and connects to its stdio.
      #|pub async fn spawn_stdio(argv : Array[String]) -> ProcessConnection {
      #|  guard argv.length() > 0 else {
      #|    raise TransportError(
      #|      "I expected a command to start, found an empty argument list.",
      #|    )
      #|  }
      #|  let (child_in, writer) = @process.write_to_process()
      #|  let (reader, child_out) = @process.read_from_process()
      #|  let pid = @process.spawn_orphan(
      #|    argv[0],
      #|    argv[1:],
      #|    stdin=child_in,
      #|    stdout=child_out,
      #|  )
      #|  { pid, reader, writer, closed: false, }
      #|}
      #|
      #|///|
      #|/// The process ID of the child.
      #|pub fn ProcessConnection::pid(self : ProcessConnection) -> Int32 {
      #|  self.pid
      #|}
      #|
      #|///|
      #|/// Waits until the child ends, and gives its exit code.
      #|pub async fn ProcessConnection::wait(self : ProcessConnection) -> Int32 {
      #|  @process.wait_pid(self.pid)
      #|}
      #|
      #|///|
      #|pub impl Connection for ProcessConnection with fn receive(self) {
      #|  if self.closed {
      #|    return None
      #|  }
      #|  read_frame(self.reader)
      #|}
      #|
      #|///|
      #|pub impl Connection for ProcessConnection with fn send(self, text, related~) {
      #|  ignore(related)
      #|  if self.closed {
      #|    raise TransportError(
      #|      "I could not send the message: the connection to the child process is closed.",
      #|    )
      #|  }
      #|  write_frame(self.writer, text)
      #|}
      #|
      #|///|
      #|/// Closes the stdin of the child, so that it reads the end of its input,
      #|/// and stops the reading of its stdout.
      #|pub impl Connection for ProcessConnection with fn close(self) {
      #|  if !self.closed {
      #|    self.closed = true
      #|    self.writer.close()
      #|    self.reader.close()
      #|  }
      #|}
      #|
    ),
  ),
  (
    "values.mbt",
    (
      #|// Values that the generated codecs use. A Decimal, a BigInteger and an Int64
      #|// keep the exact text of the number, so that they never go through a Double.
      #|
      #|///|
      #|fn expected(path : String, what : String, json : Json) -> DecodeError {
      #|  decode_error(path, "I expected \{what}, found \{json_kind(json)}.")
      #|}
      #|
      #|///|
      #|/// The exact text of a JSON number. A number without a source text gives the
      #|/// text of its Double.
      #|fn number_text(json : Json) -> String? {
      #|  match json {
      #|    Number(d, repr~) =>
      #|      match repr {
      #|        Some(text) => Some(text)
      #|        None =>
      #|          if d.is_nan() || d.is_inf() {
      #|            None
      #|          } else {
      #|            Some(double_text(d))
      #|          }
      #|      }
      #|    _ => None
      #|  }
      #|}
      #|
      #|///|
      #|fn is_integer_text(text : String) -> Bool {
      #|  scan_number(text, 0) == Some(text.length()) &&
      #|  text.find(".") is None &&
      #|  text.find("e") is None &&
      #|  text.find("E") is None
      #|}
      #|
      #|///|
      #|/// A decimal number with its exact text, such as `20.00`. Two values are
      #|/// equal when their texts are equal.
      #|pub struct Decimal {
      #|  priv text : String
      #|} derive(Eq, Hash, Debug)
      #|
      #|///|
      #|/// Gives a Decimal when `text` is a number of the JSON grammar.
      #|pub fn Decimal::parse(text : String) -> Decimal? {
      #|  if scan_number(text, 0) == Some(text.length()) {
      #|    Some({ text, })
      #|  } else {
      #|    None
      #|  }
      #|}
      #|
      #|///|
      #|pub impl Show for Decimal with fn output(self, logger) {
      #|  logger.write_string(self.text)
      #|}
      #|
      #|///|
      #|pub fn Decimal::to_string(self : Decimal) -> String {
      #|  self.text
      #|}
      #|
      #|///|
      #|pub fn Decimal::to_json(self : Decimal) -> Json {
      #|  Json::number(number_double(self.text), repr=self.text)
      #|}
      #|
      #|///|
      #|pub fn Decimal::from_json(
      #|  json : Json,
      #|  path~ : String,
      #|) -> Decimal raise DecodeError {
      #|  guard number_text(json) is Some(text) && Decimal::parse(text) is Some(value) else {
      #|    raise expected(path, "a decimal number", json)
      #|  }
      #|  value
      #|}
      #|
      #|///|
      #|/// The sign, the digits and the exponent of a decimal: the value is
      #|/// `sign * digits * 10^exponent`, with no leading or trailing zero digit.
      #|fn Decimal::parts(self : Decimal) -> (Bool, String, Int32) {
      #|  let text = self.text
      #|  let negative = text.has_prefix("-")
      #|  let body = if negative { text[1:].to_owned() } else { text }
      #|  let (mantissa, exponent) = match body.find("e") {
      #|    Some(i) => (body[:i].to_owned(), body[i + 1:].to_owned())
      #|    None =>
      #|      match body.find("E") {
      #|        Some(i) => (body[:i].to_owned(), body[i + 1:].to_owned())
      #|        None => (body, "0")
      #|      }
      #|  }
      #|  let exponent = if exponent.has_prefix("+") {
      #|    exponent[1:].to_owned()
      #|  } else {
      #|    exponent
      #|  }
      #|  let mut exp = @string.parse_int(exponent) catch { _ => 0 }
      #|  let (whole, fraction) = match mantissa.find(".") {
      #|    Some(i) => (mantissa[:i].to_owned(), mantissa[i + 1:].to_owned())
      #|    None => (mantissa, "")
      #|  }
      #|  exp -= fraction.length()
      #|  let digits = whole + fraction
      #|  let mut start = 0
      #|  while start < digits.length() && digits[start].to_int() == 0x30 {
      #|    start += 1
      #|  }
      #|  let mut end = digits.length()
      #|  while end > start && digits[end - 1].to_int() == 0x30 {
      #|    end -= 1
      #|    exp += 1
      #|  }
      #|  let digits = digits[start:end].to_owned()
      #|  if digits == "" {
      #|    (false, "", 0)
      #|  } else {
      #|    (negative, digits, exp)
      #|  }
      #|}
      #|
      #|///|
      #|/// Compares the numeric values of two decimals exactly: -1, 0 or 1. `2.50`
      #|/// and `2.5` compare as 0, but they are not equal, because their texts differ.
      #|pub fn Decimal::compare_value(self : Decimal, other : Decimal) -> Int32 {
      #|  let (an, ad, ae) = self.parts()
      #|  let (bn, bd, be) = other.parts()
      #|  if ad == "" && bd == "" {
      #|    return 0
      #|  }
      #|  if ad == "" {
      #|    return if bn { 1 } else { -1 }
      #|  }
      #|  if bd == "" {
      #|    return if an { -1 } else { 1 }
      #|  }
      #|  if an != bn {
      #|    return if an { -1 } else { 1 }
      #|  }
      #|  // Compare the magnitudes: first the position of the leading digit, then
      #|  // the digits.
      #|  let a_top = ad.length() + ae
      #|  let b_top = bd.length() + be
      #|  let magnitude = if a_top != b_top {
      #|    if a_top > b_top {
      #|      1
      #|    } else {
      #|      -1
      #|    }
      #|  } else {
      #|    let n = if ad.length() > bd.length() { ad.length() } else { bd.length() }
      #|    let mut result = 0
      #|    for i in 0..<n {
      #|      let x = if i < ad.length() { ad[i].to_int() } else { 0x30 }
      #|      let y = if i < bd.length() { bd[i].to_int() } else { 0x30 }
      #|      if x != y {
      #|        result = if x > y { 1 } else { -1 }
      #|        break
      #|      }
      #|    }
      #|    result
      #|  }
      #|  if an {
      #|    -magnitude
      #|  } else {
      #|    magnitude
      #|  }
      #|}
      #|
      #|///|
      #|/// An integer with its exact text, such as `9007199254740993`.
      #|pub struct BigInteger {
      #|  priv text : String
      #|} derive(Eq, Hash, Debug)
      #|
      #|///|
      #|/// Gives a BigInteger when `text` is an integer of the JSON grammar.
      #|pub fn BigInteger::parse(text : String) -> BigInteger? {
      #|  if is_integer_text(text) {
      #|    Some({ text, })
      #|  } else {
      #|    None
      #|  }
      #|}
      #|
      #|///|
      #|pub impl Show for BigInteger with fn output(self, logger) {
      #|  logger.write_string(self.text)
      #|}
      #|
      #|///|
      #|pub fn BigInteger::to_string(self : BigInteger) -> String {
      #|  self.text
      #|}
      #|
      #|///|
      #|pub fn BigInteger::to_json(self : BigInteger) -> Json {
      #|  Json::number(number_double(self.text), repr=self.text)
      #|}
      #|
      #|///|
      #|pub fn BigInteger::from_json(
      #|  json : Json,
      #|  path~ : String,
      #|) -> BigInteger raise DecodeError {
      #|  guard number_text(json) is Some(text) &&
      #|    BigInteger::parse(text) is Some(value) else {
      #|    raise expected(path, "an integer", json)
      #|  }
      #|  value
      #|}
      #|
      #|///|
      #|/// The JSON forms of a timestamp in Smithy.
      #|pub(all) enum TimestampFormat {
      #|  EpochSeconds
      #|  DateTime
      #|  HttpDate
      #|} derive(Eq, Debug)
      #|
      #|///|
      #|/// A timestamp. It keeps the JSON value that it was read from, so that it
      #|/// writes the same text again.
      #|pub struct Timestamp {
      #|  priv value : Json
      #|} derive(Eq, Debug)
      #|
      #|///|
      #|pub impl Show for Timestamp with fn output(self, logger) {
      #|  logger.write_string(write_json(self.value))
      #|}
      #|
      #|///|
      #|/// A timestamp in epoch seconds, such as `1700000000` or `1700000000.5`.
      #|pub fn Timestamp::epoch_seconds(seconds : Decimal) -> Timestamp {
      #|  { value: seconds.to_json(), }
      #|}
      #|
      #|///|
      #|/// A timestamp as a string, in the date-time or the http-date format.
      #|pub fn Timestamp::text(text : String) -> Timestamp {
      #|  { value: Json::string(text), }
      #|}
      #|
      #|///|
      #|/// The JSON value of the timestamp.
      #|pub fn Timestamp::to_json(self : Timestamp) -> Json {
      #|  self.value
      #|}
      #|
      #|///|
      #|fn is_date_time(text : String) -> Bool {
      #|  // The RFC 3339 form that Smithy uses: 1985-04-12T23:20:50.52Z.
      #|  let n = text.length()
      #|  guard n >= 20 else { return false }
      #|  let digit = (i : Int32) => is_digit(text[i].to_int())
      #|  let char_at = (i : Int32, c : Int32) => text[i].to_int() == c
      #|  for i in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18] {
      #|    if !digit(i) {
      #|      return false
      #|    }
      #|  }
      #|  guard char_at(4, 0x2D) &&
      #|    char_at(7, 0x2D) &&
      #|    (char_at(10, 0x54) || char_at(10, 0x74)) &&
      #|    char_at(13, 0x3A) &&
      #|    char_at(16, 0x3A) else {
      #|    return false
      #|  }
      #|  let mut i = 19
      #|  if i < n && char_at(i, 0x2E) {
      #|    i += 1
      #|    guard i < n && digit(i) else { return false }
      #|    while i < n && digit(i) {
      #|      i += 1
      #|    }
      #|  }
      #|  guard i < n else { return false }
      #|  if char_at(i, 0x5A) || char_at(i, 0x7A) {
      #|    return i + 1 == n
      #|  }
      #|  guard (char_at(i, 0x2B) || char_at(i, 0x2D)) && i + 6 == n else {
      #|    return false
      #|  }
      #|  digit(i + 1) &&
      #|  digit(i + 2) &&
      #|  char_at(i + 3, 0x3A) &&
      #|  digit(i + 4) &&
      #|  digit(i + 5)
      #|}
      #|
      #|///|
      #|pub fn Timestamp::from_json(
      #|  json : Json,
      #|  format~ : TimestampFormat,
      #|  path~ : String,
      #|) -> Timestamp raise DecodeError {
      #|  match (format, json) {
      #|    (EpochSeconds, Number(_, ..)) if number_text(json) is Some(_) =>
      #|      { value: json, }
      #|    (EpochSeconds, _) =>
      #|      raise expected(path, "a timestamp in epoch seconds", json)
      #|    (DateTime, String(text)) if is_date_time(text) => { value: json, }
      #|    (DateTime, String(text)) =>
      #|      raise decode_error(
      #|        path,
      #|        "I expected a date-time timestamp such as 1985-04-12T23:20:50.52Z, found '\{text}'.",
      #|      )
      #|    (DateTime, _) => raise expected(path, "a date-time timestamp string", json)
      #|    (HttpDate, String(_)) => { value: json, }
      #|    (HttpDate, _) => raise expected(path, "an http-date timestamp string", json)
      #|  }
      #|}
      #|
      #|///|
      #|pub fn decode_string(json : Json, path~ : String) -> String raise DecodeError {
      #|  guard json is String(text) else { raise expected(path, "a string", json) }
      #|  text
      #|}
      #|
      #|///|
      #|pub fn decode_bool(json : Json, path~ : String) -> Bool raise DecodeError {
      #|  match json {
      #|    True => true
      #|    False => false
      #|    _ => raise expected(path, "a boolean", json)
      #|  }
      #|}
      #|
      #|///|
      #|fn decode_int_range(
      #|  json : Json,
      #|  path : String,
      #|  what : String,
      #|  low : Int64,
      #|  high : Int64,
      #|) -> Int64 raise DecodeError {
      #|  guard number_text(json) is Some(text) && is_integer_text(text) else {
      #|    raise expected(path, what, json)
      #|  }
      #|  let value = @string.parse_int64(text) catch {
      #|    _ =>
      #|      raise decode_error(
      #|        path,
      #|        "I expected \{what}, found \{text}, which is out of range.",
      #|      )
      #|  }
      #|  guard value >= low && value <= high else {
      #|    raise decode_error(
      #|      path,
      #|      "I expected \{what}, found \{text}, which is out of range.",
      #|    )
      #|  }
      #|  value
      #|}
      #|
      #|///|
      #|/// Decodes a Smithy `byte`.
      #|pub fn decode_byte(json : Json, path~ : String) -> Int32 raise DecodeError {
      #|  decode_int_range(json, path, "a byte integer", -128L, 127L).to_int()
      #|}
      #|
      #|///|
      #|/// Decodes a Smithy `short`.
      #|pub fn decode_short(json : Json, path~ : String) -> Int32 raise DecodeError {
      #|  decode_int_range(json, path, "a short integer", -32768L, 32767L).to_int()
      #|}
      #|
      #|///|
      #|/// Decodes a Smithy `integer`.
      #|pub fn decode_int(json : Json, path~ : String) -> Int32 raise DecodeError {
      #|  decode_int_range(json, path, "a 32-bit integer", -2147483648L, 2147483647L).to_int()
      #|}
      #|
      #|///|
      #|/// Decodes a Smithy `long` from the exact text of the number.
      #|pub fn decode_int64(json : Json, path~ : String) -> Int64 raise DecodeError {
      #|  decode_int_range(
      #|    json,
      #|    path,
      #|    "a 64-bit integer",
      #|    -9223372036854775807L - 1L,
      #|    9223372036854775807L,
      #|  )
      #|}
      #|
      #|///|
      #|/// Decodes a Smithy `double`. The strings `NaN`, `Infinity` and `-Infinity`
      #|/// give the special values.
      #|pub fn decode_double(json : Json, path~ : String) -> Double raise DecodeError {
      #|  match json {
      #|    Number(d, ..) => d
      #|    String("NaN") => @double.not_a_number
      #|    String("Infinity") => @double.infinity
      #|    String("-Infinity") => @double.neg_infinity
      #|    _ => raise expected(path, "a number", json)
      #|  }
      #|}
      #|
      #|///|
      #|/// Decodes a Smithy `float`.
      #|pub fn decode_float(json : Json, path~ : String) -> Float raise DecodeError {
      #|  Float::from_double(decode_double(json, path~))
      #|}
      #|
      #|///|
      #|/// Decodes a Smithy `blob` from base64 text.
      #|pub fn decode_blob(json : Json, path~ : String) -> Bytes raise DecodeError {
      #|  guard json is String(text) else {
      #|    raise expected(path, "a base64 string", json)
      #|  }
      #|  @base64.decode(text) catch {
      #|    _ => raise decode_error(path, "I expected base64 text, found '\{text}'.")
      #|  }
      #|}
      #|
      #|///|
      #|pub fn encode_blob(bytes : Bytes) -> Json {
      #|  Json::string(@base64.encode(bytes))
      #|}
      #|
      #|///|
      #|/// Encodes an Int64 with its exact text.
      #|pub fn encode_int64(value : Int64) -> Json {
      #|  let text = value.to_string()
      #|  Json::number(value.to_double(), repr=text)
      #|}
      #|
      #|///|
      #|pub fn encode_int(value : Int32) -> Json {
      #|  Json::number(value.to_double())
      #|}
      #|
      #|///|
      #|/// Encodes a Double. NaN and the infinities give the strings that Smithy uses.
      #|pub fn encode_double(value : Double) -> Json {
      #|  if value.is_nan() {
      #|    Json::string("NaN")
      #|  } else if value.is_pos_inf() {
      #|    Json::string("Infinity")
      #|  } else if value.is_neg_inf() {
      #|    Json::string("-Infinity")
      #|  } else {
      #|    Json::number(value)
      #|  }
      #|}
      #|
      #|///|
      #|pub fn encode_float(value : Float) -> Json {
      #|  encode_double(value.to_double())
      #|}
      #|
      #|///|
      #|pub fn object_of(
      #|  json : Json,
      #|  path~ : String,
      #|) -> Map[String, Json] raise DecodeError {
      #|  guard json is Object(fields) else { raise expected(path, "an object", json) }
      #|  fields
      #|}
      #|
      #|///|
      #|pub fn array_of(json : Json, path~ : String) -> Array[Json] raise DecodeError {
      #|  guard json is Array(items) else { raise expected(path, "an array", json) }
      #|  items
      #|}
      #|
      #|///|
      #|/// The value of a required member. An absent member and a null member are
      #|/// errors.
      #|pub fn required(
      #|  obj : Map[String, Json],
      #|  name : String,
      #|  path~ : String,
      #|) -> Json raise DecodeError {
      #|  match obj.get(name) {
      #|    Some(Null) | None =>
      #|      raise decode_error(
      #|        child_path(path, name),
      #|        "I expected the required member \{name}, found nothing.",
      #|      )
      #|    Some(value) => value
      #|  }
      #|}
      #|
      #|///|
      #|/// The value of an optional member. A null member counts as absent.
      #|pub fn optional(obj : Map[String, Json], name : String) -> Json? {
      #|  match obj.get(name) {
      #|    Some(Null) | None => None
      #|    value => value
      #|  }
      #|}
      #|
      #|///|
      #|/// Decodes a list. `f` gets each item and its path.
      #|pub fn[T] decode_array(
      #|  json : Json,
      #|  path~ : String,
      #|  f : (Json, String) -> T raise DecodeError,
      #|) -> Array[T] raise DecodeError {
      #|  let items = array_of(json, path~)
      #|  let out = []
      #|  for index, item in items {
      #|    out.push(f(item, index_path(path, index)))
      #|  }
      #|  out
      #|}
      #|
      #|///|
      #|/// Decodes a map. It keeps the key order of the input. `f` gets each value
      #|/// and its path.
      #|pub fn[T] decode_map(
      #|  json : Json,
      #|  path~ : String,
      #|  f : (Json, String) -> T raise DecodeError,
      #|) -> Map[String, T] raise DecodeError {
      #|  let fields = object_of(json, path~)
      #|  let out = Map([])
      #|  for key, value in fields {
      #|    out[key] = f(value, child_path(path, key))
      #|  }
      #|  out
      #|}
      #|
      #|///|
      #|pub fn[T] encode_array(items : Array[T], f : (T) -> Json) -> Json {
      #|  Json::array(items.map(f))
      #|}
      #|
      #|///|
      #|pub fn[T] encode_map(items : Map[String, T], f : (T) -> Json) -> Json {
      #|  let out = Map([])
      #|  for key, value in items {
      #|    out[key] = f(value)
      #|  }
      #|  Json::object(out)
      #|}
      #|
      #|///|
      #|/// The one member of a union object whose value is not null: its name and
      #|/// its value.
      #|pub fn union_member(
      #|  json : Json,
      #|  path~ : String,
      #|) -> (String, Json) raise DecodeError {
      #|  let fields = object_of(json, path~)
      #|  let set = []
      #|  for key, value in fields {
      #|    if !(value is Null) {
      #|      set.push((key, value))
      #|    }
      #|  }
      #|  match set {
      #|    [one] => one
      #|    [] =>
      #|      raise decode_error(
      #|        path, "I expected one union member that is not null, found none.",
      #|      )
      #|    _ => {
      #|      let names = set.map(m => m.0)
      #|      raise decode_error(
      #|        path,
      #|        "I expected one union member that is not null, found \{names.length()}: \{names.join(", ")}.",
      #|      )
      #|    }
      #|  }
      #|}
      #|
      #|///|
      #|/// Rejects a member that the structure does not declare. Use it only for a
      #|/// structure whose unknown member policy is reject.
      #|pub fn reject_unknown(
      #|  obj : Map[String, Json],
      #|  known : Array[String],
      #|  path~ : String,
      #|) -> Unit raise DecodeError {
      #|  for key, _ in obj {
      #|    if !known.contains(key) {
      #|      raise decode_error(
      #|        child_path(path, key),
      #|        "I expected only declared members, found the unknown member \{key}.",
      #|      )
      #|    }
      #|  }
      #|}
      #|
      #|///|
      #|/// The params of a method with named params: absent params give `{}`.
      #|pub fn named_params(params : Json?, path~ : String) -> Json raise DecodeError {
      #|  match params {
      #|    None => Json::object(Map([]))
      #|    Some(Object(_) as value) => value
      #|    Some(value) => raise expected(path, "named params (an object)", value)
      #|  }
      #|}
      #|
      #|///|
      #|/// The params of a method with positional params, as an object keyed by
      #|/// `names`. When `either` is true, named params (an object) are also
      #|/// accepted.
      #|pub fn positional_params(
      #|  params : Json?,
      #|  names : Array[String],
      #|  either~ : Bool,
      #|  path~ : String,
      #|) -> Json raise DecodeError {
      #|  match params {
      #|    None => Json::object(Map([]))
      #|    Some(Array(items)) => {
      #|      if items.length() > names.length() {
      #|        raise decode_error(
      #|          index_path(path, names.length()),
      #|          "I expected at most \{names.length()} positional params, found \{items.length()}.",
      #|        )
      #|      }
      #|      let out = Map([])
      #|      for index, item in items {
      #|        out[names[index]] = item
      #|      }
      #|      Json::object(out)
      #|    }
      #|    Some(Object(_) as value) if either => value
      #|    Some(value) =>
      #|      raise expected(
      #|        path,
      #|        if either {
      #|          "params as an array or an object"
      #|        } else {
      #|          "positional params (an array)"
      #|        },
      #|        value,
      #|      )
      #|  }
      #|}
      #|
      #|///|
      #|/// Writes an object as positional params in the order of `names`. A
      #|/// trailing absent member is dropped; an inner absent member gives null.
      #|pub fn to_positional(json : Json, names : Array[String]) -> Json {
      #|  guard json is Object(fields) else { return json }
      #|  let mut last = -1
      #|  for index, name in names {
      #|    if fields.get(name) is Some(_) {
      #|      last = index
      #|    }
      #|  }
      #|  let out = []
      #|  for index in 0..<=last {
      #|    out.push(fields.get(names[index]).unwrap_or(Json::null()))
      #|  }
      #|  Json::array(out)
      #|}
      #|
    ),
  ),
]
