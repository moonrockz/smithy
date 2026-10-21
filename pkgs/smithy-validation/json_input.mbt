///|
/// Input offsets use UTF-16 code units, matching MoonBit string locations.
pub(all) suberror ValueInputError {
  InvalidJson(Int32, String)
  DuplicateJsonKey(Int32)
  JsonInputLimit(Int32, String)
} derive(Debug)

///|
priv struct JsonContainer {
  object_ : Bool
  keys : Set[String]
  mut expect_key : Bool
}

///|
/// Parse one bounded JSON value, rejecting duplicate decoded object names.
pub fn parse_json_value(text : String) -> Json raise ValueInputError {
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
    if bytes > 16777216 {
      raise JsonInputLimit(0, "I expected at most 16 MiB of UTF-8 JSON input.")
    }
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
    _ => raise InvalidJson(i, "I expected one well-formed JSON value.")
  }
}
