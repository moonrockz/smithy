///|
/// A transcript read from a JSON document. `version` and `completeness` are
/// None when the document does not say; `expect` is None without an `expect`
/// key.
pub(all) struct TranscriptDocument {
  version : ProtocolVersion?
  completeness : Completeness?
  entries : Array[TranscriptEntry]
  expect : Array[ExpectedFinding]?
} derive(Eq, Debug)

///|
/// A problem at a code unit offset of the document text.
priv suberror JsonDocumentError {
  Problem((String, Int32))
}

///|
/// A value's code unit span in the document text, end exclusive.
priv struct Span {
  start : Int32
  end : Int32
}

///|
fn is_blank(c : UInt16) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
fn skip_blank(text : String, from : Int32) -> Int32 {
  let mut i = from
  while i < text.length() && is_blank(text[i]) {
    i += 1
  }
  i
}

///|
fn describe_unit(text : String, at : Int32) -> String {
  if at >= text.length() {
    "the end of the text"
  } else {
    "'" + text[at:at + 1].to_owned() + "'"
  }
}

///|
/// The end of the string literal that starts at `from`.
fn skip_string(text : String, from : Int32) -> Int32 raise JsonDocumentError {
  let mut i = from + 1
  while i < text.length() {
    let c = text[i]
    if c == '\\' {
      i += 2
    } else if c == '"' {
      return i + 1
    } else {
      i += 1
    }
  }
  raise Problem(
    (
      "I expected the end of the string that starts here, and I found the end of the text.",
      from,
    ),
  )
}

///|
/// The end of the JSON value that starts at `from`, found by tracking strings,
/// escapes and nesting. It does not check the value; scalars end at a
/// delimiter.
fn skip_value(text : String, from : Int32) -> Int32 raise JsonDocumentError {
  let n = text.length()
  if from >= n {
    raise Problem(
      ("I expected a JSON value, and I found the end of the text.", from),
    )
  }
  let open : Array[UInt16] = []
  let mut i = from
  while i < n {
    let c = text[i]
    if c == '"' {
      i = skip_string(text, i)
    } else if c == '{' || c == '[' {
      open.push(c)
      i += 1
    } else if c == '}' || c == ']' {
      let expected : UInt16 = if c == '}' { '{' } else { '[' }
      if open.length() == 0 || open[open.length() - 1] != expected {
        raise Problem(("I did not expect \{describe_unit(text, i)} here.", i))
      }
      ignore(open.pop())
      i += 1
    } else if is_blank(c) || c == ',' || c == ':' {
      if open.length() == 0 {
        break
      }
      i += 1
    } else {
      i += 1
    }
    if open.length() == 0 {
      // A scalar continues to its delimiter; a closed container ends here.
      if c == '"' || c == '}' || c == ']' {
        return i
      }
      if c != '{' && c != '[' {
        while i < n {
          let d = text[i]
          if is_blank(d) || d == ',' || d == ':' || d == '}' || d == ']' {
            break
          }
          i += 1
        }
        return i
      }
    }
  }
  if open.length() > 0 {
    raise Problem(
      (
        "I expected the end of the value that starts here, and I found the end of the text.",
        from,
      ),
    )
  }
  i
}

///|
fn expect_unit(
  text : String,
  at : Int32,
  unit : UInt16,
  what : String,
) -> Int32 raise JsonDocumentError {
  if at < text.length() && text[at] == unit {
    at + 1
  } else {
    raise Problem(
      ("I expected \{what}, and I found \{describe_unit(text, at)}.", at),
    )
  }
}

///|
/// An object member: its name, the offset of the name and the value span.
priv struct Member {
  key : String
  at : Int32
  value : Span
}

///|
/// The members of the object whose span is `span`, in document order.
fn object_members(
  text : String,
  span : Span,
) -> Array[Member] raise JsonDocumentError {
  let members = []
  let mut i = expect_unit(text, span.start, '{', "'{'")
  i = skip_blank(text, i)
  if i < text.length() && text[i] == '}' {
    return members
  }
  while true {
    i = skip_blank(text, i)
    if i >= text.length() || text[i] != '"' {
      raise Problem(
        ("I expected a member name, and I found \{describe_unit(text, i)}.", i),
      )
    }
    let key_start = i
    let key_end = skip_string(text, i)
    let invalid_name = Problem(
      ("I expected a valid member name, and I found an invalid string.", i),
    )
    let key = match
      (@json.parse(text[i:key_end].to_owned()) catch {
        _ => raise invalid_name
      }) {
      String(key) => key
      _ => raise invalid_name
    }
    i = skip_blank(text, key_end)
    i = skip_blank(text, expect_unit(text, i, ':', "':' after the member name"))
    let value_end = skip_value(text, i)
    if value_end == i {
      raise Problem(
        ("I expected a member value, and I found \{describe_unit(text, i)}.", i),
      )
    }
    members.push({ key, at: key_start, value: { start: i, end: value_end, }, })
    i = skip_blank(text, value_end)
    if i < text.length() && text[i] == ',' {
      i += 1
      continue
    }
    ignore(expect_unit(text, i, '}', "',' or '}'"))
    break
  }
  members
}

///|
/// The elements of the array whose span is `span`.
fn array_elements(
  text : String,
  span : Span,
) -> Array[Span] raise JsonDocumentError {
  let elements = []
  let mut i = expect_unit(text, span.start, '[', "'['")
  i = skip_blank(text, i)
  if i < text.length() && text[i] == ']' {
    return elements
  }
  while true {
    i = skip_blank(text, i)
    let end = skip_value(text, i)
    if end == i {
      raise Problem(
        (
          "I expected an array element, and I found \{describe_unit(text, i)}.",
          i,
        ),
      )
    }
    elements.push({ start: i, end, })
    i = skip_blank(text, end)
    if i < text.length() && text[i] == ',' {
      i += 1
      continue
    }
    ignore(expect_unit(text, i, ']', "',' or ']'"))
    break
  }
  elements
}

///|
/// Gives the one-based line and column of code unit offsets. It continues
/// from the last offset, so offsets in increasing order cost one scan of the
/// text; an earlier offset starts the scan again.
priv struct Locator {
  text : String
  mut offset : Int32
  mut line : Int32
  mut column : Int32
}

///|
fn Locator::new(text : String) -> Locator {
  { text, offset: 0, line: 1, column: 1, }
}

///|
fn Locator::locate(self : Locator, at : Int32) -> SourceLocation {
  if at < self.offset {
    self.offset = 0
    self.line = 1
    self.column = 1
  }
  while self.offset < at && self.offset < self.text.length() {
    if self.text[self.offset] == '\n' {
      self.line += 1
      self.column = 1
    } else {
      self.column += 1
    }
    self.offset += 1
  }
  { line: self.line, column: self.column, }
}

///|
fn source_location(text : String, at : Int32) -> SourceLocation {
  Locator::new(text).locate(at)
}

///|
fn invalid_document(
  locator : Locator,
  at : Int32,
  message : String,
) -> TranscriptFinding {
  {
    code: InvalidTranscript,
    severity: @validation.Error,
    entry: None,
    location: Some(locator.locate(at)),
    sender: None,
    related: [],
    finding: None,
    message,
  }
}

///|
fn parse_span(text : String, span : Span) -> Json raise JsonDocumentError {
  @json.parse(text[span.start:span.end].to_owned()) catch {
    _ =>
      raise Problem(
        (
          "I expected a valid JSON value here, and I found \{text[span.start:span.end].to_owned()}.",
          span.start,
        ),
      )
  }
}

///|
fn read_entry(
  text : String,
  locator : Locator,
  span : Span,
) -> TranscriptEntry raise JsonDocumentError {
  if text[span.start] != '{' {
    raise Problem(
      (
        "I expected an entry object with \"from\" and \"message\", and I found \{describe_unit(text, span.start)}.",
        span.start,
      ),
    )
  }
  let mut sender : PeerName? = None
  let mut message : Span? = None
  for item in object_members(text, span) {
    let { key, value, .. } = item
    if key == "from" {
      match parse_span(text, value) {
        String(name) =>
          match PeerName::parse(name) {
            Some(peer) => sender = Some(peer)
            None =>
              raise Problem(
                (
                  "I expected a peer name in \"from\", and I found \"\{name}\".",
                  value.start,
                ),
              )
          }
        _ =>
          raise Problem(
            ("I expected a string peer name in \"from\".", value.start),
          )
      }
    } else if key == "message" {
      message = Some(value)
    }
  }
  guard sender is Some(sender) else {
    raise Problem(("I expected a \"from\" pair in this entry.", span.start))
  }
  guard message is Some(message) else {
    raise Problem(("I expected a \"message\" pair in this entry.", span.start))
  }
  {
    sender,
    receiver: None,
    message: text[message.start:message.end].to_owned(),
    location: Some(locator.locate(message.start)),
  }
}

///|
fn read_expected(
  text : String,
  span : Span,
) -> Array[ExpectedFinding] raise JsonDocumentError {
  let expected = []
  for element in array_elements(text, span) {
    let json = parse_span(text, element)
    guard json is Object(fields) else {
      raise Problem(
        (
          "I expected an object with a \"code\" in the expect list.",
          element.start,
        ),
      )
    }
    let code = match fields.get("code") {
      Some(String(code)) => code
      _ =>
        raise Problem(
          (
            "I expected a string \"code\" in this expected finding.",
            element.start,
          ),
        )
    }
    fn index(name : String) -> Int32? raise JsonDocumentError {
      match fields.get(name) {
        None | Some(Null) => None
        Some(Number(n, ..)) if n >= 0.0 && n == n.to_int().to_double() =>
          Some(n.to_int())
        _ =>
          raise Problem(
            (
              "I expected a non-negative whole number for \"\{name}\" in this expected finding.",
              element.start,
            ),
          )
      }
    }

    let entry = index("entry")
    let related = index("related")
    match ExpectedFinding::new(code, entry~, related~) {
      Some(item) => expected.push(item)
      None =>
        raise Problem(
          (
            "I do not know the finding code \"\{code}\" in the expect list.",
            element.start,
          ),
        )
    }
  }
  expected
}

///|
/// Reads a transcript document: an object with one `entries` member and
/// optional `version`, `complete` and `expect`, or a bare array of entries. An
/// unknown member of the object gives an advisory. Each
/// message keeps its exact source text. It never raises; problems are
/// InvalidTranscript findings with a location, and an entry with a problem is
/// dropped.
pub fn read_json_transcript(
  text : String,
) -> (TranscriptDocument, Array[TranscriptFinding]) {
  let findings = []
  // Entries and problems come in offset order, so one scan locates them all.
  let locator = Locator::new(text)
  fn problem(error : JsonDocumentError) -> Unit {
    let Problem((message, at)) = error
    findings.push(invalid_document(locator, at, message))
  }

  let start = skip_blank(
    text,
    if text.length() > 0 && text[0] == '\u{FEFF}' {
      1
    } else {
      0
    },
  )
  let mut version : ProtocolVersion? = None
  let mut completeness : Completeness? = None
  let mut expect : Array[ExpectedFinding]? = None
  let entries = []
  fn read_entries(span : Span) -> Unit {
    let elements = array_elements(text, span) catch {
      error => {
        problem(error)
        return
      }
    }
    for element in elements {
      entries.push(read_entry(text, locator, element)) catch {
        error => problem(error)
      }
    }
  }

  try {
    if start >= text.length() {
      raise Problem(
        ("I expected a transcript, and I found an empty document.", start),
      )
    }
    let end = skip_value(text, start)
    let tail = skip_blank(text, end)
    if tail < text.length() {
      raise Problem(
        (
          "I expected the end of the document, and I found \{describe_unit(text, tail)}.",
          tail,
        ),
      )
    }
    if text[start] == '[' {
      read_entries({ start, end, })
    } else {
      let mut entries_at : Int32? = None
      for item in object_members(text, { start, end, }) {
        let { key, at, value, } = item
        try {
          match key {
            "version" =>
              match parse_span(text, value) {
                String("1.0") => version = Some(V1_0)
                String("2.0") => version = Some(V2_0)
                _ =>
                  raise Problem(
                    (
                      "I expected \"1.0\" or \"2.0\" for \"version\", and I found \{text[value.start:value.end].to_owned()}.",
                      value.start,
                    ),
                  )
              }
            "complete" =>
              match parse_span(text, value) {
                True => completeness = Some(Complete)
                False => completeness = Some(Partial)
                _ =>
                  raise Problem(
                    (
                      "I expected true or false for \"complete\", and I found \{text[value.start:value.end].to_owned()}.",
                      value.start,
                    ),
                  )
              }
            "entries" =>
              if entries_at is None {
                entries_at = Some(at)
                read_entries(value)
              } else {
                raise Problem(
                  (
                    "I expected one \"entries\" member in the transcript object, and I found a second one.",
                    at,
                  ),
                )
              }
            "expect" => expect = Some(read_expected(text, value))
            _ =>
              findings.push({
                ..invalid_document(
                  locator,
                  at,
                  "I do not know the transcript member \"\{key}\"; I ignored it.",
                ),
                severity: @validation.Advisory,
              })
          }
        } catch {
          error => problem(error)
        }
      }
      if entries_at is None {
        raise Problem(
          (
            "I expected an \"entries\" member in the transcript object, and I found none.",
            start,
          ),
        )
      }
    }
  } catch {
    error => problem(error)
  }
  ({ version, completeness, entries, expect, }, findings)
}
