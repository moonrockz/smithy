///|
/// What makes two diagnostics repeats of each other: the same severity and
/// code at the same place in the same file.
priv struct RepeatKey {
  severity : String
  code : String
  file : String
  start_line : Int32
  start_column : Int32
  end_line : Int32
  end_column : Int32
} derive(Eq, Hash)

///|
fn Diagnostic::repeat_key(self : Diagnostic) -> RepeatKey {
  {
    severity: self.severity,
    code: self.code,
    file: self.file,
    start_line: self.start_line,
    start_column: self.start_column,
    end_line: self.end_line,
    end_column: self.end_column,
  }
}

///|
/// One row of the Validate list: a diagnostic and its repeats. `first` is the
/// earliest of them in the list; `repeats` keep the order of the list.
pub(all) struct DiagnosticGroup {
  first : Diagnostic
  repeats : Array[Diagnostic]
} derive(Eq, Debug)

///|
pub extend DiagnosticGroup with Eq::{equal, not_equal}

///|
pub extend DiagnosticGroup with @debug.Debug::{to_repr}

///|
/// The number of diagnostics in the group.
pub fn DiagnosticGroup::size(self : DiagnosticGroup) -> Int32 {
  self.repeats.length() + 1
}

///|
/// The rows of the Validate list. With `grouped`, the repeats of a diagnostic
/// join the row of its first one, in the order of the list; without it, each
/// diagnostic has a row of its own.
pub fn group_diagnostics(
  items : Array[Diagnostic],
  grouped : Bool,
) -> Array[DiagnosticGroup] {
  if !grouped {
    return items.map(d => { first: d, repeats: [], })
  }
  let groups : Array[DiagnosticGroup] = []
  let index : Map[RepeatKey, Int32] = Map([])
  for d in items {
    let key = d.repeat_key()
    match index.get(key) {
      Some(at) => groups[at].repeats.push(d)
      None => {
        index[key] = groups.length()
        groups.push({ first: d, repeats: [], })
      }
    }
  }
  groups
}

///|
/// A part of a diagnostic message. Smithy puts the names of shapes, traits and
/// members between backticks, and many messages name shapes by their shape ID
/// without them; the list shows both as code.
pub(all) enum MessagePart {
  Text(String)
  Name(String)
} derive(Eq, Debug)

///|
pub extend MessagePart with Eq::{equal, not_equal}

///|
pub extend MessagePart with @debug.Debug::{to_repr}

///|
/// The text and the names of a message, in order: the text between a pair of
/// backticks, and each absolute shape ID in the other text. A backtick without
/// its pair, and an empty pair, stay text.
pub fn message_parts(message : String) -> Array[MessagePart] {
  let pieces = message.split("`").map(piece => piece.to_owned()).to_array()
  let parts : Array[MessagePart] = []
  let text = StringBuilder()
  // The pieces at odd indexes are between backticks. With an even count of
  // pieces, the last one follows a backtick that has no pair.
  for i, piece in pieces {
    if i % 2 == 0 {
      text.write_string(piece)
    } else if i == pieces.length() - 1 {
      text.write_string("`" + piece)
    } else if piece == "" {
      text.write_string("``")
    } else {
      parts.append(shape_id_parts(text.to_string()))
      text.reset()
      parts.push(Name(piece))
    }
  }
  parts.append(shape_id_parts(text.to_string()))
  parts
}

///|
fn is_id_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn is_id_char(c : Char) -> Bool {
  is_id_start(c) || (c >= '0' && c <= '9')
}

///|
/// True when `text` is a dot-separated list of identifiers.
fn is_namespace(text : String) -> Bool {
  text != "" &&
  text
  .split(".")
  .all(segment => {
    segment.length() > 0 &&
    is_id_start(segment.get_char(0).unwrap_or(' ')) &&
    segment.iter().all(is_id_char)
  })
}

///|
/// Text with each absolute shape ID (`namespace#Name` or
/// `namespace#Name$member`) as a name. The ID ends before the first character
/// that it cannot have, so the full stop that ends a sentence stays text.
fn shape_id_parts(text : String) -> Array[MessagePart] {
  let chars = text.to_array()
  let parts : Array[MessagePart] = []
  let mut done = 0
  for hash in 0..<chars.length() {
    guard chars[hash] == '#' && hash >= done else { continue }
    // The namespace: identifiers and dots before the `#`, with no dot at an end.
    let mut start = hash
    while start > done &&
          (is_id_char(chars[start - 1]) || chars[start - 1] == '.') {
      start -= 1
    }
    while start < hash && chars[start] == '.' {
      start += 1
    }
    // The name, and the member after a `$`.
    let mut end = hash + 1
    while end < chars.length() && is_id_char(chars[end]) {
      end += 1
    }
    if end + 1 < chars.length() &&
      chars[end] == '$' &&
      is_id_start(chars[end + 1]) {
      end += 1
      while end < chars.length() && is_id_char(chars[end]) {
        end += 1
      }
    }
    let prefix = String::from_array(chars[start:hash])
    guard is_namespace(prefix) && end > hash + 1 && is_id_start(chars[hash + 1]) else {
      continue
    }
    if start > done {
      parts.push(Text(String::from_array(chars[done:start])))
    }
    parts.push(Name(String::from_array(chars[start:end])))
    done = end
  }
  if done < chars.length() {
    parts.push(Text(String::from_array(chars[done:])))
  }
  parts
}
