///|
/// The most characters that a share link may have, with its version prefix.
pub const MAX_SHARE_LENGTH : Int32 = 8000

///|
/// The most bytes that the JSON of a state can have, in a link and after it
/// unpacks. Deflate packs repeated text by about 1000 to 1, so a link of 8000
/// characters can unpack to 6 MB; `decode_share` rejects such a state before
/// it reads it. A model of a few hundred KB fits. The Smithy library needs
/// minutes for a model of 1 MB, so a larger state is of no use.
pub const MAX_STATE_BYTES : Int32 = 2097152

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
  length_reason(fragment).map(reason => reason + " Use Download instead.")
}

///|
fn length_reason(fragment : String) -> String? {
  if fragment.length() > MAX_SHARE_LENGTH {
    Some(
      "The link has \{fragment.length()} characters. A link can have \{MAX_SHARE_LENGTH} at most.",
    )
  } else {
    None
  }
}

///|
const INFLATE_CHUNK : Int32 = 65536

///|
/// Unpack a raw deflate stream, and stop as soon as the output passes
/// `MAX_STATE_BYTES`, so a link that packs 1000 to 1 never unpacks in full.
fn bounded_inflate(packed : Bytes) -> Result[Bytes, String] {
  let inflater = @flate.Inflater::new()
  let chunk : FixedArray[Byte] = FixedArray::make(INFLATE_CHUNK, b'\x00')
  let out : Array[Byte] = []
  let mut offset = 0
  while true {
    let (status, consumed, produced) = inflater.step(
      packed[offset:],
      chunk.mut_view(),
    ) catch {
      @flate.InflateError(message) =>
        return Err("I could not unpack the link: \{message}")
      _ => return Err("I could not unpack the link.")
    }
    offset += consumed
    for i in 0..<produced {
      out.push(chunk[i])
    }
    if out.length() > MAX_STATE_BYTES {
      return Err(
        "The link unpacks to more than \{MAX_STATE_BYTES} bytes. I do not open a state that large.",
      )
    }
    match status {
      Done => break
      NeedMoreOutput => ()
      NeedMoreInput =>
        return Err("I could not unpack the link: the data ends too soon.")
    }
  }
  Ok(Bytes::from_array(out))
}

///|
/// The reason a state is too large for a link, or `None` when it fits. A link
/// of a state that is too large would not open.
pub fn share_state_problem(state : ShareState) -> String? {
  let size = @utf8.encode(@json.to_json(state).stringify()).length()
  if size > MAX_STATE_BYTES {
    Some(
      "The state has \{size} bytes. A link can hold \{MAX_STATE_BYTES} bytes at most. Use Download instead.",
    )
  } else {
    None
  }
}

///|
/// The format number of a fragment that starts with `v`, digits and a dot,
/// as text; `None` for any other fragment.
fn format_of(text : String) -> String? {
  guard text.has_prefix("v") else { return None }
  let mut i = 1
  while i < text.length() && text[i] >= '0' && text[i] <= '9' {
    i += 1
  }
  if i > 1 && i < text.length() && text[i] == '.' {
    Some(text[1:i].to_owned())
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
  if length_reason(text) is Some(reason) {
    return Err(reason)
  }
  guard text.has_prefix(SHARE_PREFIX) else {
    if format_of(text) is Some(format) {
      return Err(
        "I cannot read this link: it has the format v\{format}, and I know only v1. It may come from a newer version of the site.",
      )
    }
    return Err("I expected the link to start with v1. so I cannot read it.")
  }
  let packed = match base64url_decode(text[SHARE_PREFIX.length():].to_owned()) {
    Ok(bytes) => bytes
    Err(reason) => return Err(reason)
  }
  let inflated = match bounded_inflate(packed) {
    Ok(bytes) => bytes
    Err(reason) => return Err(reason)
  }
  let json_text = @utf8.decode(inflated) catch {
    _ => return Err("The link does not hold UTF-8 text.")
  }
  let json = @json.parse(json_text) catch {
    _ => return Err("The link does not hold JSON.")
  }
  try @json.from_json(json) catch {
    _ =>
      Err(
        "The link holds JSON that is not a playground state. It may come from another version of the site.",
      )
  } noraise {
    state => Ok(state)
  }
}
