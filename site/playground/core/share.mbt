///|
/// The most characters that a share link may have, with its version prefix.
pub const MAX_SHARE_LENGTH : Int32 = 8000

///|
const SHARE_PREFIX : String = "v1."

///|
let alphabet : String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

///|
fn base64url_encode(bytes : Bytes) -> String {
  let out = StringBuilder()
  let n = bytes.length()
  let mut i = 0
  while i < n {
    let b0 = bytes[i].to_int()
    let b1 = if i + 1 < n { bytes[i + 1].to_int() } else { 0 }
    let b2 = if i + 2 < n { bytes[i + 2].to_int() } else { 0 }
    let group = (b0 << 16) | (b1 << 8) | b2
    out.write_char(alphabet[(group >> 18) & 63].to_int().unsafe_to_char())
    out.write_char(alphabet[(group >> 12) & 63].to_int().unsafe_to_char())
    if i + 1 < n {
      out.write_char(alphabet[(group >> 6) & 63].to_int().unsafe_to_char())
    }
    if i + 2 < n {
      out.write_char(alphabet[group & 63].to_int().unsafe_to_char())
    }
    i += 3
  }
  out.to_string()
}

///|
fn base64url_value(c : Char) -> Int32 {
  match c {
    'A'..<='Z' => c.to_int() - 'A'.to_int()
    'a'..<='z' => c.to_int() - 'a'.to_int() + 26
    '0'..<='9' => c.to_int() - '0'.to_int() + 52
    '-' => 62
    '_' => 63
    _ => -1
  }
}

///|
fn base64url_decode(text : String) -> Result[Bytes, String] {
  let values = []
  for c in text {
    let value = base64url_value(c)
    if value < 0 {
      return Err(
        "I found the character '\{c}' in the link, which is not in base64url.",
      )
    }
    values.push(value)
  }
  if values.length() % 4 == 1 {
    return Err("The link has a length that base64url cannot have.")
  }
  let out : Array[Byte] = []
  let mut i = 0
  while i < values.length() {
    let v0 = values[i]
    let v1 = values[i + 1]
    let v2 = if i + 2 < values.length() { values[i + 2] } else { 0 }
    let v3 = if i + 3 < values.length() { values[i + 3] } else { 0 }
    let group = (v0 << 18) | (v1 << 12) | (v2 << 6) | v3
    out.push((group >> 16).land(255).to_byte())
    if i + 2 < values.length() {
      out.push((group >> 8).land(255).to_byte())
    }
    if i + 3 < values.length() {
      out.push(group.land(255).to_byte())
    }
    i += 4
  }
  Ok(Bytes::from_array(out))
}

///|
/// The reason a link is too long, or `None` when it fits.
pub fn share_length_problem(fragment : String) -> String? {
  if fragment.length() > MAX_SHARE_LENGTH {
    Some(
      "The link has \{fragment.length()} characters. A link can have \{MAX_SHARE_LENGTH} at most. Use Download instead.",
    )
  } else {
    None
  }
}

///|
/// The text of the URL fragment for a state: `v1.` and the base64url text of
/// the deflated UTF-8 JSON. The text can be longer than `MAX_SHARE_LENGTH`;
/// check it with `share_length_problem` before you use it as a link.
pub fn encode_share(state : ShareState) -> String {
  let json = @utf8.encode(@json.to_json(state).stringify())
  SHARE_PREFIX + base64url_encode(@flate.deflate_all(json))
}

///|
pub fn decode_share(text : String) -> Result[ShareState, String] {
  if share_length_problem(text) is Some(problem) {
    return Err(problem)
  }
  guard text.has_prefix(SHARE_PREFIX) else {
    return Err("I expected the link to start with v1. so I cannot read it.")
  }
  let packed = match base64url_decode(text[SHARE_PREFIX.length():].to_owned()) {
    Ok(bytes) => bytes
    Err(reason) => return Err(reason)
  }
  let inflated = @flate.inflate_all(packed) catch {
    @flate.InflateError(message) =>
      return Err("I could not unpack the link: \{message}")
  }
  let json_text = @utf8.decode(inflated) catch {
    _ => return Err("The link does not hold UTF-8 text.")
  }
  let json = @json.parse(json_text) catch {
    _ => return Err("The link does not hold JSON.")
  }
  try @json.from_json(json) catch {
    _ => Err("The link holds JSON that is not a playground state.")
  } noraise {
    state => Ok(state)
  }
}
