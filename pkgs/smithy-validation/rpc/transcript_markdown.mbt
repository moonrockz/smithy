///|
/// A line of the document: its code unit span without the line terminator, and
/// its one-based line number.
priv struct DocLine {
  start : Int32
  end : Int32
  number : Int32
  /// The offset after the terminator.
  next : Int32
}

///|
/// The line that starts at `from`. A `\r` before `\n` is part of the
/// terminator.
fn doc_line(text : String, from : Int32, number : Int32) -> DocLine {
  let n = text.length()
  let mut i = from
  while i < n && text[i] != '\n' {
    i += 1
  }
  let next = if i < n { i + 1 } else { i }
  let end = if i > from && text[i - 1] == '\r' { i - 1 } else { i }
  { start: from, end, number, next, }
}

///|
fn line_text(text : String, line : DocLine) -> String {
  text[line.start:line.end].to_owned()
}

///|
/// A fence line: up to three spaces, then three or more backticks or tildes.
priv struct Fence {
  char : UInt16
  length : Int32
  /// The info string, trimmed.
  info : String
}

///|
fn parse_fence(content : String) -> Fence? {
  let n = content.length()
  let mut i = 0
  while i < n && i < 3 && content[i] == ' ' {
    i += 1
  }
  if i >= n || (content[i] != '`' && content[i] != '~') {
    return None
  }
  let char = content[i]
  let mut length = 0
  while i < n && content[i] == char {
    i += 1
    length += 1
  }
  if length < 3 {
    return None
  }
  let rest = content[i:n].to_owned()
  // A backtick fence cannot have a backtick in its info string.
  if char == '`' && rest.contains("`") {
    return None
  }
  Some({ char, length, info: rest.trim().to_owned(), })
}

///|
/// True when `content` closes `open`: the same character, at least as long,
/// and nothing else.
fn closes_fence(content : String, open : Fence) -> Bool {
  match parse_fence(content) {
    Some(fence) =>
      fence.char == open.char &&
      fence.length >= open.length &&
      fence.info.is_empty()
    None => false
  }
}

///|
/// An InvalidTranscript reader finding at a one-based line and column.
fn located_problem(
  line : Int32,
  column : Int32,
  message : String,
) -> TranscriptFinding {
  {
    code: InvalidTranscript,
    severity: @validation.Error,
    entry: None,
    location: Some({ line, column, }),
    sender: None,
    related: [],
    finding: None,
    message,
  }
}

///|
/// The sender and the named receiver of a `jsonrpc A -> B` or `jsonrpc A` info
/// string rest. The receiver, when given, must differ from the sender; the
/// checker compares it with the other peer.
fn read_direction(rest : String) -> Result[(PeerName, PeerName?), String] {
  let parts = rest.split("->").map(part => part.trim().to_owned()).collect()
  if parts.length() > 2 || parts[0].is_empty() {
    return Err(
      "I expected a direction like \"jsonrpc client -> server\" or \"jsonrpc client\", and I found \"\{rest}\".",
    )
  }
  guard PeerName::parse(parts[0]) is Some(sender) else {
    return Err(
      "I expected a peer name as the sender, and I found \"\{parts[0]}\".",
    )
  }
  let mut named : PeerName? = None
  if parts.length() == 2 {
    guard PeerName::parse(parts[1]) is Some(receiver) else {
      return Err(
        "I expected a peer name as the receiver, and I found \"\{parts[1]}\".",
      )
    }
    if receiver == sender {
      return Err(
        "I expected the receiver to be the other peer, and I found \"\{receiver.to_string()}\" on both sides.",
      )
    }
    named = Some(receiver)
  }
  Ok((sender, named))
}

///|
/// Reads the flat `version` and `complete` keys of the front matter that
/// spans `lines`.
fn read_front_matter(
  text : String,
  lines : Array[DocLine],
  findings : Array[TranscriptFinding],
) -> (ProtocolVersion?, Completeness?) {
  let mut version : ProtocolVersion? = None
  let mut completeness : Completeness? = None
  for line in lines {
    let content = line_text(text, line)
    guard content.find(":") is Some(colon) else { continue }
    let key = content[:colon].to_owned().trim().to_owned()
    let mut value = content[colon + 1:].to_owned().trim().to_owned()
    if value.length() >= 2 &&
      (
        (value[0] == '"' && value[value.length() - 1] == '"') ||
        (value[0] == '\'' && value[value.length() - 1] == '\'')
      ) {
      value = value[1:value.length() - 1].to_owned()
    }
    match key {
      "version" =>
        match value {
          "1.0" => version = Some(V1_0)
          "2.0" => version = Some(V2_0)
          _ =>
            findings.push(
              located_problem(
                line.number,
                1,
                "I expected \"1.0\" or \"2.0\" for \"version\" in the front matter, and I found \{value}.",
              ),
            )
        }
      "complete" =>
        match value {
          "true" => completeness = Some(Complete)
          "false" => completeness = Some(Partial)
          _ =>
            findings.push(
              located_problem(
                line.number,
                1,
                "I expected true or false for \"complete\" in the front matter, and I found \{value}.",
              ),
            )
        }
      _ => ()
    }
  }
  (version, completeness)
}

///|
/// Whitespace in an info string: space, tab, line tabulation and form feed.
fn is_info_space(c : UInt16) -> Bool {
  c == ' ' || c == '\t' || c == '\u{0B}' || c == '\u{0C}'
}

///|
/// Reads a Markdown transcript. Fenced blocks whose info string starts with
/// `jsonrpc` are entries, and `jsonrpc-expect` blocks hold the expected
/// findings; all other text is ignored. Optional front matter gives `version`
/// and `complete`. Each message keeps its exact source text, located at the
/// first line of its block. It never raises; problems are InvalidTranscript
/// findings, and a block with a problem is dropped.
pub fn read_markdown_transcript(
  text : String,
) -> (TranscriptDocument, Array[TranscriptFinding]) {
  let findings = []
  let entries = []
  let mut expect : Array[ExpectedFinding]? = None
  let mut version : ProtocolVersion? = None
  let mut completeness : Completeness? = None
  let n = text.length()
  let mut offset : Int32 = if n > 0 && text[0] == '\u{FEFF}' { 1 } else { 0 }
  let mut number : Int32 = 1
  // Front matter: the first line is "---" and a later line is "---".
  let first = doc_line(text, offset, number)
  if offset < n && line_text(text, first).trim_end().to_owned() == "---" {
    let inside = []
    let mut cursor = first.next
    let mut at = number + 1
    let mut closed = false
    while cursor < n {
      let line = doc_line(text, cursor, at)
      cursor = line.next
      at += 1
      if line_text(text, line).trim_end().to_owned() == "---" {
        closed = true
        break
      }
      inside.push(line)
    }
    if closed {
      let (v, c) = read_front_matter(text, inside, findings)
      version = v
      completeness = c
      offset = cursor
      number = at
    }
  }
  while offset < n {
    let line = doc_line(text, offset, number)
    offset = line.next
    number += 1
    guard parse_fence(line_text(text, line)) is Some(open) else { continue }
    // The first word ends at any whitespace, such as a space or a tab.
    let mut word_end = 0
    while word_end < open.info.length() && !is_info_space(open.info[word_end]) {
      word_end += 1
    }
    let word = open.info[:word_end].to_owned()
    let rest = open.info[word_end:].to_owned()
    let is_entry = word == "jsonrpc"
    let is_expect = word == "jsonrpc-expect"
    // Find the closing fence; the body is every line between.
    let body_start = offset
    let body_number = number
    let mut body_end = offset
    let mut closed = false
    while offset < n {
      let inner = doc_line(text, offset, number)
      offset = inner.next
      number += 1
      if closes_fence(line_text(text, inner), open) {
        closed = true
        break
      }
      body_end = inner.end
    }
    if !is_entry && !is_expect {
      continue
    }
    if !closed {
      findings.push(
        located_problem(
          line.number,
          1,
          "I expected a closing fence for this \{word} block, and I found the end of the text.",
        ),
      )
      continue
    }
    let body = if body_end > body_start {
      text[body_start:body_end].to_owned()
    } else {
      ""
    }
    if is_entry {
      match read_direction(rest) {
        Ok((sender, receiver)) =>
          entries.push({
            sender,
            receiver,
            message: body,
            location: Some({ line: body_number, column: 1, }),
          })
        Err(message) => findings.push(located_problem(line.number, 1, message))
      }
    } else {
      let items = read_expected(body, { start: 0, end: body.length(), }) catch {
        Problem((message, at)) => {
          let place = source_location(body, at)
          findings.push(
            located_problem(body_number + place.line - 1, place.column, message),
          )
          continue
        }
      }
      match expect {
        Some(all) => all.append(items)
        None => expect = Some(items)
      }
    }
  }
  ({ version, completeness, entries, expect, }, findings)
}
