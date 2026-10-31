///|
/// Input offsets use UTF-16 code units, matching MoonBit string locations.
pub(all) suberror ValueInputError {
  InvalidJson(Int32, String)
  DuplicateJsonKey(Int32)
  JsonInputLimit(Int32, String)
} derive(Debug)

///|
/// The UTF-8 length of `text`. A surrogate pair counts 4 bytes, and a lone
/// surrogate counts 3, the length of its replacement character.
#internal(internal, "a helper of the smithy-validation packages")
pub fn utf8_length(text : StringView) -> Int32 {
  let mut bytes = 0
  for c in text.iter() {
    let n = c.to_int()
    bytes += if n < 0x80 {
      1
    } else if n < 0x800 {
      2
    } else if n < 0x10000 {
      3
    } else {
      4
    }
  }
  bytes
}

///|
priv struct JsonContainer {
  object_ : Bool
  keys : Set[String]
  mut expect_key : Bool
}

///|
/// Parse one bounded JSON value, rejecting duplicate decoded object names.
pub fn parse_json_value(text : String) -> Json raise ValueInputError {
  if utf8_length(text) > 16777216 {
    raise JsonInputLimit(0, "I expected at most 16 MiB of UTF-8 JSON input.")
  }
  let stack : Array[JsonContainer] = []
  let mut i = 0
  while i < text.length() {
    let c = text.code_unit_at(i).to_int()
    match c {
      34 => {
        let start = i
        i += 1
        let mut closed = false
        while i < text.length() {
          let part = text.code_unit_at(i).to_int()
          if part == 34 {
            i += 1
            closed = true
            break
          }
          if part == 92 {
            i += 2
          } else {
            i += 1
          }
        }
        guard closed else {
          raise InvalidJson(
            start, "I expected a closing quote for the JSON string.",
          )
        }
        if stack.last() is Some(frame) && frame.object_ && frame.expect_key {
          let value = @json.parse(text[start:i].to_owned()) catch {
            _ =>
              raise InvalidJson(
                start, "I expected a valid JSON object member name.",
              )
          }
          guard value is String(name) else {
            raise InvalidJson(start, "I expected a string object member name.")
          }
          if frame.keys.contains(name) {
            raise DuplicateJsonKey(start)
          }
          frame.keys.add(name)
          frame.expect_key = false
        }
        continue
      }
      123 | 91 => {
        if stack.length() >= 128 {
          raise JsonInputLimit(
            i, "I expected JSON nesting depth no greater than 128.",
          )
        }
        stack.push({ object_: c == 123, keys: Set([]), expect_key: c == 123, })
      }
      125 | 93 => {
        guard stack.pop() is Some(frame) && frame.object_ == (c == 125) else {
          raise InvalidJson(
            i, "I expected a matching JSON container delimiter.",
          )
        }
      }
      44 =>
        if stack.last() is Some(frame) && frame.object_ {
          frame.expect_key = true
        }
      _ => ()
    }
    i += 1
  }
  @syntax.parse_json_value(text) catch {
    error => {
      let offset = match error {
        @json.InvalidChar(position, _)
        | @json.InvalidNumber(position, _)
        | @json.InvalidIdentEscape(position)
        // The parse keeps the last value of a duplicate key, so it does not raise this.
        | @json.DuplicateKey(position, _) => {
          let mut line = 1
          let mut start = 0
          for at = 0; at < text.length(); at = at + 1 {
            if line == position.line {
              break
            }
            if text.code_unit_at(at).to_int() == 10 {
              line += 1
              start = at + 1
            }
          }
          start + position.column
        }
        @json.InvalidEof => text.length()
        @json.DepthLimitExceeded => 0 // Preflight already enforces a tighter limit.
      }
      raise InvalidJson(
        offset,
        "I expected one well-formed JSON value: " + error.to_string(),
      )
    }
  }
}
