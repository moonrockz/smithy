///|
const DEFAULT_LINE_BYTES : Int32 = 1048576

///|
/// Leading text that a log line has before its JSON record. It is a fixed
/// rule, not a pattern language.
pub(all) enum LogPrefix {
  NoPrefix
  /// Skip to the first `{` of the line.
  ToFirstBrace
  /// Skip this many fields, each one ended by the delimiter.
  Fields(Int32, Char)
} derive(Eq, Debug)

///|
/// Decides whether a JSON record is a protocol entry. Paths are JSON Pointers.
pub(all) enum LogSelector {
  HasField(String)
  /// The field is a string with this value.
  FieldEquals(String, String)
  /// The record, or an element of a record array, has `jsonrpc`, `method`,
  /// `result` or `error`.
  AnyJsonRpc
} derive(Eq, Debug)

///|
/// Where the message of a record is. Paths are JSON Pointers.
pub(all) enum MessageSource {
  WholeRecord
  /// The exact source text of this field's value.
  Field(String)
  /// The decoded value of this string field.
  EscapedField(String)
} derive(Eq, Debug)

///|
/// Who sent the message of a record. Paths are JSON Pointers.
pub(all) enum SenderSource {
  /// Every entry has this sender; the log has one direction.
  Fixed(PeerName)
  /// The string value of this field, mapped to a peer.
  Field(String, Map[String, PeerName])
} derive(Eq, Debug)

///|
/// A parsed JSON Pointer (RFC 6901).
pub struct JsonPointer {
  priv text : String
  priv tokens : Array[String]
} derive(Eq, Debug)

///|
pub fn JsonPointer::parse(
  text : String,
) -> JsonPointer raise @validation.ConfigurationError {
  let invalid = @validation.ConfigurationError(
    "I expected a JSON Pointer such as \"/dir\", and I found \"\{text}\".",
  )
  if text.is_empty() {
    return { text, tokens: [], }
  }
  if text[0] != '/' {
    raise invalid
  }
  for i in 0..<text.length() {
    if text[i] == '~' &&
      (i + 1 >= text.length() || (text[i + 1] != '0' && text[i + 1] != '1')) {
      raise invalid
    }
  }
  let tokens = text[1:]
    .split("/")
    .map(part => {
      part
      .to_owned()
      .replace_all(old="~1", new="/")
      .replace_all(old="~0", new="~")
    })
    .collect()
  { text, tokens, }
}

///|
pub fn JsonPointer::to_string(self : JsonPointer) -> String {
  self.text
}

///|
/// A field name that the built-in presets use.
fn JsonPointer::name(key : String) -> JsonPointer {
  { text: "/" + key, tokens: [key], }
}

///|
/// An array index token: digits with no leading zero.
fn array_index(token : String) -> Int32? {
  let n = token.length()
  if n == 0 || n > 9 || (n > 1 && token[0] == '0') {
    return None
  }
  let mut index = 0
  for i in 0..<n {
    let c = token[i].to_int()
    if c < '0'.to_int() || c > '9'.to_int() {
      return None
    }
    index = index * 10 + (c - '0'.to_int())
  }
  Some(index)
}

///|
/// The value the pointer names inside `json`.
fn JsonPointer::resolve(self : JsonPointer, json : Json) -> Json? {
  let mut value = json
  for token in self.tokens {
    match value {
      Object(fields) =>
        match fields.get(token) {
          Some(next) => value = next
          None => return None
        }
      Array(items) =>
        match array_index(token) {
          Some(i) if i < items.length() => value = items[i]
          _ => return None
        }
      _ => return None
    }
  }
  Some(value)
}

///|
/// The source span of the value the pointer names inside the record that
/// spans `record` of `text`.
fn JsonPointer::locate(
  self : JsonPointer,
  text : String,
  record : Span,
) -> Span? {
  let mut span = record
  for token in self.tokens {
    let c = text[span.start]
    if c == '{' {
      let members = object_members(text, span) catch { _ => return None }
      // The last member with the name wins, as in a parsed object.
      let mut found : Span? = None
      for item in members {
        if item.key == token {
          found = Some(item.value)
        }
      }
      guard found is Some(next) else { return None }
      span = next
    } else if c == '[' {
      guard array_index(token) is Some(i) else { return None }
      let elements = array_elements(text, span) catch { _ => return None }
      guard i < elements.length() else { return None }
      span = elements[i]
    } else {
      return None
    }
  }
  Some(span)
}

///|
priv enum Selector {
  JsonRpcRecord
  Has(JsonPointer)
  Equals(JsonPointer, String)
} derive(Eq, Debug)

///|
priv enum MessagePlace {
  Record
  Exact(JsonPointer)
  Escaped(JsonPointer)
} derive(Eq, Debug)

///|
priv enum SenderPlace {
  Constant(PeerName)
  Lookup(JsonPointer, Map[String, PeerName])
} derive(Eq, Debug)

///|
/// How a log line becomes a transcript entry: the prefix to remove, the
/// records to keep, and where the message and the sender are. Built with
/// validated constructors; it never changes.
pub struct LogMapping {
  priv prefix : LogPrefix
  priv selector : Selector
  priv message : MessagePlace
  priv sender : SenderPlace
} derive(Eq, Debug)

///|
/// Raises when a path is not a JSON Pointer, when a `Fields` count is
/// negative, or when a sender map is empty.
pub fn LogMapping::new(
  prefix~ : LogPrefix = NoPrefix,
  selector~ : LogSelector = AnyJsonRpc,
  message~ : MessageSource = WholeRecord,
  sender~ : SenderSource,
) -> LogMapping raise @validation.ConfigurationError {
  if prefix is Fields(count, _) && count < 0 {
    raise @validation.ConfigurationError(
      "I expected a field count of 0 or more in the log prefix, and I found \{count}.",
    )
  }
  let selector = match selector {
    AnyJsonRpc => JsonRpcRecord
    HasField(path) => Has(JsonPointer::parse(path))
    FieldEquals(path, value) => Equals(JsonPointer::parse(path), value)
  }
  let message = match message {
    WholeRecord => Record
    Field(path) => Exact(JsonPointer::parse(path))
    EscapedField(path) => Escaped(JsonPointer::parse(path))
  }
  let sender = match sender {
    Fixed(peer) => Constant(peer)
    Field(path, values) => {
      if values.is_empty() {
        raise @validation.ConfigurationError(
          "I expected at least one value in the sender map for \{path}, and I found none.",
        )
      }
      Lookup(JsonPointer::parse(path), values.copy())
    }
  }
  { prefix, selector, message, sender, }
}

///|
/// The `raw` preset: each line is a JSON-RPC record (`jsonrpc`, `method`,
/// `result` or `error`) sent by `sender`.
pub fn LogMapping::raw(sender : PeerName) -> LogMapping {
  {
    prefix: NoPrefix,
    selector: JsonRpcRecord,
    message: Record,
    sender: Constant(sender),
  }
}

///|
/// The `dir-message` preset: `{"dir": ..., "message": ...}` records, with
/// `directions` mapping each `dir` value to its sender. Raises when
/// `directions` is empty.
pub fn LogMapping::dir_message(
  directions : Map[String, PeerName],
) -> LogMapping raise @validation.ConfigurationError {
  if directions.is_empty() {
    raise @validation.ConfigurationError(
      "I expected at least one dir value in the dir-message map; directions was empty.",
    )
  }
  let dir = JsonPointer::name("dir")
  {
    prefix: NoPrefix,
    selector: Has(dir),
    message: Exact(JsonPointer::name("message")),
    sender: Lookup(dir, directions.copy()),
  }
}

///|
/// Reads a mapping from its JSON form. Every key is optional except `sender`:
///
/// - `prefix`: `"none"`, `"first-brace"` or `{"fields": n, "delimiter": "c"}`;
/// - `selector`: `"jsonrpc"`, `{"hasField": pointer}` or
///   `{"field": pointer, "equals": string}`;
/// - `message`: `"record"`, `{"field": pointer}` or `{"escapedField": pointer}`;
/// - `sender`: a peer name, or `{"field": pointer, "values": {value: peer}}`.
///
/// Peer names must be in `peers`. Raises on anything else.
pub fn LogMapping::from_json(
  text : String,
  peers : Array[PeerName],
) -> LogMapping raise @validation.ConfigurationError {
  fn fail(message : String) -> LogMapping raise @validation.ConfigurationError {
    raise @validation.ConfigurationError(message)
  }

  let json = parse_bounded_json(text) catch {
    _ =>
      return fail(
        "I expected a JSON object for the log mapping, and I found text that is not JSON.",
      )
  }
  guard json is Object(fields) else {
    fail(
      "I expected a JSON object for the log mapping, and I found \{json.stringify()}.",
    )
  }
  for key, _ in fields {
    if !["prefix", "selector", "message", "sender"].contains(key) {
      return fail(
        "I expected prefix, selector, message or sender in the log mapping, and I found \"\{key}\".",
      )
    }
  }
  let names = peers.map(p => p.to_string()).join(", ")
  fn known_peer(
    name : String,
    role : String,
  ) -> PeerName raise @validation.ConfigurationError {
    match PeerName::parse(name) {
      Some(peer) if peers.contains(peer) => peer
      _ =>
        raise @validation.ConfigurationError(
          "I expected a peer of the protocol (\{names}) \{role}, and I found \"\{name}\".",
        )
    }
  }

  fn found(value : Json) -> String {
    value.stringify()
  }

  let prefix = match fields.get("prefix") {
    None | Some(String("none")) => NoPrefix
    Some(String("first-brace")) => ToFirstBrace
    Some(Object(rule)) if rule.length() == 2 &&
      rule.get("fields") is Some(Number(count, ..)) &&
      count == count.to_int().to_double() &&
      rule.get("delimiter") is Some(String(delimiter)) => {
      guard delimiter.char_length() == 1 && delimiter.get_char(0) is Some(char) else {
        return fail(
          "I expected one character as the prefix delimiter, and I found \"\{delimiter}\".",
        )
      }
      Fields(count.to_int(), char)
    }
    Some(other) =>
      return fail(
        "I expected \"none\", \"first-brace\" or {\"fields\": count, \"delimiter\": character} for \"prefix\", and I found \{found(other)}.",
      )
  }
  let selector = match fields.get("selector") {
    None | Some(String("jsonrpc")) => AnyJsonRpc
    Some(Object(rule)) if rule.length() == 1 &&
      rule.get("hasField") is Some(String(path)) => HasField(path)
    Some(Object(rule)) if rule.length() == 2 &&
      rule.get("field") is Some(String(path)) &&
      rule.get("equals") is Some(String(value)) => FieldEquals(path, value)
    Some(other) =>
      return fail(
        "I expected \"jsonrpc\", {\"hasField\": pointer} or {\"field\": pointer, \"equals\": value} for \"selector\", and I found \{found(other)}.",
      )
  }
  let message : MessageSource = match fields.get("message") {
    None | Some(String("record")) => WholeRecord
    Some(Object(rule)) if rule.length() == 1 &&
      rule.get("field") is Some(String(path)) => Field(path)
    Some(Object(rule)) if rule.length() == 1 &&
      rule.get("escapedField") is Some(String(path)) => EscapedField(path)
    Some(other) =>
      return fail(
        "I expected \"record\", {\"field\": pointer} or {\"escapedField\": pointer} for \"message\", and I found \{found(other)}.",
      )
  }
  let sender : SenderSource = match fields.get("sender") {
    None =>
      return fail(
        "I expected a \"sender\" in the log mapping, and I found none.",
      )
    Some(String(name)) => Fixed(known_peer(name, "as the sender"))
    Some(Object(rule)) if rule.length() == 2 &&
      rule.get("field") is Some(String(path)) &&
      rule.get("values") is Some(Object(values)) => {
      let map : Map[String, PeerName] = Map([])
      for value, peer in values {
        guard peer is String(name) else {
          return fail(
            "I expected a peer name for sender value \"\{value}\", and I found \{found(peer)}.",
          )
        }
        map[value] = known_peer(name, "for sender value \"\{value}\"")
      }
      Field(path, map)
    }
    Some(other) =>
      return fail(
        "I expected a peer name or {\"field\": pointer, \"values\": {...}} for \"sender\", and I found \{found(other)}.",
      )
  }
  LogMapping::new(prefix~, selector~, message~, sender~)
}

///|
/// What a log reader has seen so far. Each finished line is counted once in
/// `lines`; a line that is blank or not JSON after its prefix is `not_json`,
/// a JSON record that the selector rejects is `skipped`, and a line that
/// gives an entry is in `entries`. Lines with a finding are only in `lines`.
pub struct LogCounts {
  lines : Int32
  not_json : Int32
  skipped : Int32
  entries : Int32
} derive(Eq, Debug)

///|
/// Turns log text, given in chunks of any size, into transcript entries. It
/// does no I/O and never raises on its input: problems are InvalidTranscript findings with
/// a location, and the line with a problem is dropped. Memory is bounded by
/// `line_bytes`.
pub struct LogReader {
  priv mapping : LogMapping
  priv line_bytes : Int32
  /// The line being assembled, while it is within the limit.
  priv pending : StringBuilder
  priv mut pending_bytes : Int32
  priv mut pending_cr : Bool
  /// The line being assembled ends with the first half of a surrogate pair.
  priv mut pending_lead : Bool
  priv mut has_pending : Bool
  /// The line being assembled is over the limit; it is skipped to its end.
  priv mut overlong : Bool
  priv mut started : Bool
  priv mut ended : Bool
  priv mut lines : Int32
  priv mut not_json : Int32
  priv mut skipped : Int32
  priv mut entries : Int32
}

///|
/// `line_bytes` is the most UTF-8 bytes a line may have, without its line
/// ending. Raises when it is below 1.
pub fn LogReader::new(
  mapping : LogMapping,
  line_bytes~ : Int32 = DEFAULT_LINE_BYTES,
) -> LogReader raise @validation.ConfigurationError {
  if line_bytes < 1 {
    raise @validation.ConfigurationError(
      "I expected a positive log line limit; line_bytes was \{line_bytes}.",
    )
  }
  {
    mapping,
    line_bytes,
    pending: StringBuilder(),
    pending_bytes: 0,
    pending_cr: false,
    pending_lead: false,
    has_pending: false,
    overlong: false,
    started: false,
    ended: false,
    lines: 0,
    not_json: 0,
    skipped: 0,
    entries: 0,
  }
}

///|
/// True when every entry has the same sender (`SenderSource::Fixed`). Such a
/// log can be checked only message by message, so the caller turns
/// correlation off.
pub fn LogReader::single_sender(self : LogReader) -> Bool {
  self.mapping.sender is Constant(_)
}

///|
pub fn LogReader::counts(self : LogReader) -> LogCounts {
  {
    lines: self.lines,
    not_json: self.not_json,
    skipped: self.skipped,
    entries: self.entries,
  }
}

///|
/// Gives the next chunk of text. A line split between chunks, also inside a
/// surrogate pair or a CRLF, is held until its newline. A leading BOM of the
/// stream is removed, and CRLF counts as LF. Returns the entries and findings
/// of the lines that this chunk finishes. Text after `end` is ignored.
pub fn LogReader::push_text(
  self : LogReader,
  chunk : String,
) -> (Array[TranscriptEntry], Array[TranscriptFinding]) {
  let entries = []
  let findings = []
  if self.ended {
    return (entries, findings)
  }
  let n = chunk.length()
  let mut i = 0
  if !self.started && n > 0 {
    self.started = true
    if chunk[0] == '\u{FEFF}' {
      i = 1
    }
  }
  while i < n {
    let mut j = i
    while j < n && chunk[j] != '\n' {
      j += 1
    }
    self.take(chunk, i, j, findings)
    if j == n {
      break
    }
    self.finish_line(entries, findings)
    i = j + 1
  }
  (entries, findings)
}

///|
/// Ends the stream: a final line with no newline is read. Later calls give
/// nothing.
pub fn LogReader::end(
  self : LogReader,
) -> (Array[TranscriptEntry], Array[TranscriptFinding]) {
  let entries = []
  let findings = []
  if self.ended {
    return (entries, findings)
  }
  self.ended = true
  if self.has_pending {
    self.finish_line(entries, findings)
  }
  (entries, findings)
}

///|
/// Adds `chunk[start:end]`, which has no newline, to the line being
/// assembled, and reports the line once when it goes over the limit.
fn LogReader::take(
  self : LogReader,
  chunk : String,
  start : Int32,
  end : Int32,
  findings : Array[TranscriptFinding],
) -> Unit {
  if start == end {
    return
  }
  self.has_pending = true
  if self.overlong {
    return
  }
  self.pending_bytes += @validation.utf8_length(chunk[start:end])
  // A surrogate pair split between chunks counts 3 bytes for each half; the
  // pair has 4.
  if self.pending_lead && chunk[start].is_trailing_surrogate() {
    self.pending_bytes -= 2
  }
  self.pending_lead = chunk[end - 1].is_leading_surrogate()
  self.pending_cr = chunk[end - 1] == '\r'
  // A final carriage return can still be part of a CRLF line ending.
  let content = self.pending_bytes - (if self.pending_cr { 1 } else { 0 })
  if content > self.line_bytes {
    self.overlong = true
    self.pending.reset()
    findings.push(
      located_problem(
        { line: self.lines + 1, column: 1, },
        "I expected a log line of at most \{self.line_bytes} bytes, and I found more on line \{self.lines + 1}; I skipped the line.",
      ),
    )
  } else {
    self.pending.write_view(chunk[start:end])
  }
}

///|
fn LogReader::finish_line(
  self : LogReader,
  entries : Array[TranscriptEntry],
  findings : Array[TranscriptFinding],
) -> Unit {
  self.lines += 1
  let text = self.pending.to_string()
  let overlong = self.overlong
  let end = if self.pending_cr { text.length() - 1 } else { text.length() }
  self.pending.reset()
  self.pending_bytes = 0
  self.pending_cr = false
  self.pending_lead = false
  self.has_pending = false
  self.overlong = false
  if !overlong {
    self.read_line(text, end, entries, findings)
  }
}

///|
/// The offset of the first unit of `needle` in `text[from:end]`.
fn find_units(
  text : String,
  from : Int32,
  end : Int32,
  needle : String,
) -> Int32? {
  let m = needle.length()
  for i in from..<(end - m + 1) {
    let mut same = true
    for k in 0..<m {
      if text[i + k] != needle[k] {
        same = false
        break
      }
    }
    if same {
      return Some(i)
    }
  }
  None
}

///|
/// Where the record starts after the prefix, or None when the line does not
/// have the prefix.
fn LogPrefix::record_start(
  self : LogPrefix,
  text : String,
  end : Int32,
) -> Int32? {
  match self {
    NoPrefix => Some(0)
    ToFirstBrace => find_units(text, 0, end, "{")
    Fields(count, delimiter) => {
      let needle = delimiter.to_string()
      let mut at = 0
      for _ in 0..<count {
        guard find_units(text, at, end, needle) is Some(found) else {
          return None
        }
        at = found + needle.length()
      }
      Some(at)
    }
  }
}

///|
fn is_json_rpc_record(json : Json) -> Bool {
  guard json is Object(fields) else { return false }
  fields.contains("jsonrpc") ||
  fields.contains("method") ||
  fields.contains("result") ||
  fields.contains("error")
}

///|
fn Selector::selects(self : Selector, json : Json) -> Bool {
  match self {
    JsonRpcRecord =>
      is_json_rpc_record(json) ||
      (json is Array(items) && items.iter().any(is_json_rpc_record))
    Has(pointer) => pointer.resolve(json) is Some(_)
    Equals(pointer, value) =>
      pointer.resolve(json) is Some(String(found)) && found == value
  }
}

///|
fn no_message(pointer : JsonPointer) -> String {
  "I expected a message at \{pointer.text}, and I found no such field"
}

///|
/// Reads one finished line, `text[:end]` without its line ending.
fn LogReader::read_line(
  self : LogReader,
  text : String,
  end : Int32,
  entries : Array[TranscriptEntry],
  findings : Array[TranscriptFinding],
) -> Unit {
  let line = self.lines
  guard self.mapping.prefix.record_start(text, end) is Some(start) else {
    self.not_json += 1
    return
  }
  let first = skip_blank(text, start)
  let mut last = end
  while last > first && is_blank(text[last - 1]) {
    last -= 1
  }
  if first >= last {
    self.not_json += 1
    return
  }
  let record : Span = { start: first, end: last, }
  let json = parse_bounded_json(text[first:last]) catch {
    _ => {
      self.not_json += 1
      return
    }
  }
  if !self.mapping.selector.selects(json) {
    self.skipped += 1
    return
  }
  fn problem(at : Int32, message : String) -> Unit {
    findings.push(
      located_problem({ line, column: at + 1, }, message + " on line \{line}."),
    )
  }

  fn source(span : Span) -> String {
    text[span.start:span.end].to_owned()
  }

  let sender = match self.mapping.sender {
    Constant(peer) => peer
    Lookup(pointer, values) => {
      guard pointer.locate(text, record) is Some(span) else {
        problem(
          record.start,
          "I expected a sender value at \{pointer.text}, and I found no such field",
        )
        return
      }
      let value = parse_span(text, span) catch { _ => Json::null() }
      guard value is String(name) else {
        problem(
          span.start,
          "I expected a string sender value at \{pointer.text}, and I found \{source(span)}",
        )
        return
      }
      guard values.get(name) is Some(peer) else {
        let known = values.keys().collect().join(", ")
        problem(
          span.start,
          "I expected a sender value at \{pointer.text} that the mapping names (\{known}), and I found \{source(span)}",
        )
        return
      }
      peer
    }
  }
  let (at, message) = match self.mapping.message {
    Record => (record.start, source(record))
    Exact(pointer) => {
      guard pointer.locate(text, record) is Some(span) else {
        problem(record.start, no_message(pointer))
        return
      }
      (span.start, source(span))
    }
    Escaped(pointer) => {
      guard pointer.locate(text, record) is Some(span) else {
        problem(record.start, no_message(pointer))
        return
      }
      let value = parse_span(text, span) catch { _ => Json::null() }
      guard value is String(decoded) else {
        problem(
          span.start,
          "I expected a string holding the message at \{pointer.text}, and I found \{source(span)}",
        )
        return
      }
      // The message starts after the opening quote.
      (span.start + 1, decoded)
    }
  }
  self.entries += 1
  entries.push({
    sender,
    receiver: None,
    message,
    location: Some({ line, column: at + 1, }),
  })
}
