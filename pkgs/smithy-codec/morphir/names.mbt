// Morphir name, path and fully qualified name spellings.
//
// Authorities (see examples/morphir-codecs/README.md for the pins):
// - v3: finos/morphir-elm src/Morphir/IR/{Name,Path,FQName}/Codec.elm. A Name is a list of words, a Path a list
//   of Names, an FQName [package path, module path, name]. The word grammar is the v3 JSON Schema's
//   `^([a-z][a-z0-9]*|[0-9]+)$` (decision D10 of the wire reference: the schema, not the prose page).
// - v4: finos/morphir docs/spec/ir/fixtures/naming-conformance.json and spec/ir/mck/names.md. Canonical strings
//   are kept as written; a legacy word array collapses each maximal run of two or more single-letter words into
//   one initialism (decision 0001).

///|
/// A refusal of a name spelling: a message and the index path inside the input value.
priv struct NameError {
  message : String
  at : Array[Int32]
}

///|
fn name_error(message : String, at~ : Array[Int32] = []) -> NameError {
  { message, at, }
}

///|
fn is_lower(c : Char) -> Bool {
  c >= 'a' && c <= 'z'
}

///|
fn is_upper(c : Char) -> Bool {
  c >= 'A' && c <= 'Z'
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// Compare two strings by UTF-16 code units, as Elm (JavaScript) does. `String::compare` orders by length
/// first, so it cannot be used for Elm's Dict order.
fn code_unit_compare(a : String, b : String) -> Int32 {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let x = a.code_unit_at(i).to_int()
    let y = b.code_unit_at(i).to_int()
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  a.length().compare(b.length())
}

///|
/// Elm's `compare` on lists: element by element, a shorter prefix first.
fn list_compare(
  a : Array[String],
  b : Array[String],
  item : (String, String) -> Int32,
) -> Int32 {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let c = item(a[i], b[i])
    if c != 0 {
      return c
    }
  }
  a.length().compare(b.length())
}

///|
fn split(text : String, separator : String) -> Array[String] {
  text.split(separator).map(part => part.to_owned()).to_array()
}

// ---------------------------------------------------------------------------------------------------------
// v3: word arrays. The logical string joins words with "-", names with "/" and uses ":" and "#" for an FQName.
// Words contain neither separator, so the logical string is reversible.

///|
fn v3_word_ok(word : String) -> Bool {
  if word.is_empty() {
    return false
  }
  let first = word.get_char(0).unwrap()
  if is_lower(first) {
    word.iter().all(c => is_lower(c) || is_digit(c))
  } else {
    word.iter().all(is_digit)
  }
}

///|
fn v3_name_read(value : Json, at : Array[Int32]) -> Result[String, NameError] {
  guard value is Array(words) else {
    return Err(name_error("I expected a v3 Name: an array of words.", at~))
  }
  guard !words.is_empty() else {
    return Err(name_error("I expected a v3 Name with at least one word.", at~))
  }
  let out : Array[String] = []
  for i, word in words {
    guard word is String(text) && v3_word_ok(text) else {
      return Err(
        name_error(
          "I expected a v3 word matching ^([a-z][a-z0-9]*|[0-9]+)$.",
          at=at + [i],
        ),
      )
    }
    out.push(text)
  }
  Ok(out.join("-"))
}

///|
fn v3_path_read(value : Json, at : Array[Int32]) -> Result[String, NameError] {
  guard value is Array(names) else {
    return Err(name_error("I expected a v3 Path: an array of Names.", at~))
  }
  guard !names.is_empty() else {
    return Err(name_error("I expected a v3 Path with at least one Name.", at~))
  }
  let out : Array[String] = []
  for i, name in names {
    match v3_name_read(name, at + [i]) {
      Ok(text) => out.push(text)
      Err(e) => return Err(e)
    }
  }
  Ok(out.join("/"))
}

///|
fn v3_fqname_read(value : Json) -> Result[String, NameError] {
  guard value is Array(parts) && parts.length() == 3 else {
    return Err(
      name_error(
        "I expected a v3 FQName: [package path, module path, local name].",
      ),
    )
  }
  let package_path = v3_path_read(parts[0], [0])
  let module_ = v3_path_read(parts[1], [1])
  let local_name = v3_name_read(parts[2], [2])
  match (package_path, module_, local_name) {
    (Ok(p), Ok(m), Ok(n)) => Ok(p + ":" + m + "#" + n)
    (Err(e), _, _) | (_, Err(e), _) | (_, _, Err(e)) => Err(e)
  }
}

///|
fn v3_name_json(text : String) -> Result[Json, NameError] {
  let words = split(text, "-")
  for word in words {
    guard v3_word_ok(word) else {
      return Err(name_error("I cannot write \{text.escape()} as a v3 Name."))
    }
  }
  Ok(Json::array(words.map(w => Json::string(w))))
}

///|
fn v3_path_json(text : String) -> Result[Json, NameError] {
  let out : Array[Json] = []
  for name in split(text, "/") {
    match v3_name_json(name) {
      Ok(json) => out.push(json)
      Err(e) => return Err(e)
    }
  }
  Ok(Json::array(out))
}

///|
fn v3_fqname_json(text : String) -> Result[Json, NameError] {
  guard split_fqname(text) is Some((p, m, n)) else {
    return Err(name_error("I cannot write \{text.escape()} as a v3 FQName."))
  }
  match (v3_path_json(p), v3_path_json(m), v3_name_json(n)) {
    (Ok(a), Ok(b), Ok(c)) => Ok(Json::array([a, b, c]))
    (Err(e), _, _) | (_, Err(e), _) | (_, _, Err(e)) => Err(e)
  }
}

///|
/// Elm Dict order of v3 Names: lexicographic word lists, words by UTF-16 code unit.
fn v3_name_compare(a : String, b : String) -> Int32 {
  list_compare(split(a, "-"), split(b, "-"), code_unit_compare)
}

///|
/// Elm Dict order of v3 Paths: lexicographic lists of Names.
fn v3_path_compare(a : String, b : String) -> Int32 {
  list_compare(split(a, "/"), split(b, "/"), v3_name_compare)
}

///|
/// Split "package:module#name" at its single ":" and the single "#" after it.
fn split_fqname(text : String) -> (String, String, String)? {
  guard text.find(":") is Some(colon) && text.find("#") is Some(hash) else {
    return None
  }
  guard colon < hash else { return None }
  let package_path = text[:colon].to_owned()
  let module_ = text[colon + 1:hash].to_owned()
  let local_name = text[hash + 1:].to_owned()
  if module_.contains(":") ||
    local_name.contains(":") ||
    local_name.contains("#") {
    return None
  }
  Some((package_path, module_, local_name))
}

// ---------------------------------------------------------------------------------------------------------
// v4: canonical strings, with legacy word arrays accepted on read.

///|
/// A canonical v4 name segment: all lowercase (a word) or all uppercase (an initialism); digits in both.
fn v4_segment_ok(segment : String) -> Bool {
  !segment.is_empty() &&
  (
    segment.iter().all(c => is_lower(c) || is_digit(c)) ||
    segment.iter().all(c => is_upper(c) || is_digit(c))
  )
}

///|
fn v4_name_ok(text : String) -> Bool {
  split(text, "-").iter().all(v4_segment_ok)
}

///|
fn v4_path_ok(text : String) -> Bool {
  split(text, "/").iter().all(v4_name_ok)
}

///|
/// Decode a legacy word array (decision 0001): a maximal run of two or more single-letter words is one
/// initialism, written in uppercase; every other word stays a lowercase word.
fn v4_legacy_name(
  words : Array[Json],
  at : Array[Int32],
) -> Result[String, NameError] {
  guard !words.is_empty() else {
    return Err(
      name_error("I expected a legacy Name with at least one word.", at~),
    )
  }
  let texts : Array[String] = []
  for i, word in words {
    guard word is String(text) &&
      !text.is_empty() &&
      text.iter().all(c => is_lower(c) || is_digit(c)) else {
      return Err(
        name_error(
          "I expected a legacy word matching ^[a-z0-9]+$.",
          at=at + [i],
        ),
      )
    }
    texts.push(text)
  }
  let single_letter = fn(w : String) {
    w.length() == 1 && is_lower(w.get_char(0).unwrap())
  }
  let segments : Array[String] = []
  let mut i = 0
  while i < texts.length() {
    if single_letter(texts[i]) {
      let mut j = i
      let run = StringBuilder()
      while j < texts.length() && single_letter(texts[j]) {
        run.write_string(texts[j])
        j = j + 1
      }
      if j - i >= 2 {
        segments.push(run.to_string().to_upper())
      } else {
        segments.push(texts[i])
      }
      i = j
    } else {
      segments.push(texts[i])
      i = i + 1
    }
  }
  Ok(segments.join("-"))
}

///|
fn v4_name_read(value : Json, at : Array[Int32]) -> Result[String, NameError] {
  match value {
    String(text) =>
      if v4_name_ok(text) {
        Ok(text)
      } else {
        Err(
          name_error(
            "invalid_name: \{text.escape()} is not a canonical Name (lowercase words and uppercase initialisms joined by \"-\").",
            at~,
          ),
        )
      }
    Array(words) => v4_legacy_name(words, at)
    _ =>
      Err(
        name_error("invalid_name: I expected a Name string or word array.", at~),
      )
  }
}

///|
fn v4_path_read(value : Json, at : Array[Int32]) -> Result[String, NameError] {
  match value {
    String(text) =>
      if v4_path_ok(text) {
        Ok(text)
      } else {
        Err(
          name_error(
            "invalid_name: \{text.escape()} is not a canonical Path.",
            at~,
          ),
        )
      }
    Array(names) => {
      guard !names.is_empty() else {
        return Err(
          name_error(
            "invalid_name: I expected a Path with at least one Name.",
            at~,
          ),
        )
      }
      let out : Array[String] = []
      for i, name in names {
        match v4_name_read(name, at + [i]) {
          Ok(text) => out.push(text)
          Err(e) => return Err(e)
        }
      }
      Ok(out.join("/"))
    }
    _ =>
      Err(name_error("invalid_name: I expected a Path string or array.", at~))
  }
}

///|
fn v4_fqname_read(value : Json) -> Result[String, NameError] {
  match value {
    String(text) =>
      match split_fqname(text) {
        Some((p, m, n)) if v4_path_ok(p) && v4_path_ok(m) && v4_name_ok(n) =>
          Ok(text)
        _ =>
          Err(
            name_error(
              "invalid_name: \{text.escape()} is not a canonical FQName \"package_path:module#name\".",
            ),
          )
      }
    Array(parts) => {
      guard parts.length() == 3 else {
        return Err(
          name_error(
            "invalid_name: a legacy FQName has exactly 3 parts, [package_path, module, name].",
          ),
        )
      }
      match
        (
          v4_path_read(parts[0], [0]),
          v4_path_read(parts[1], [1]),
          v4_name_read(parts[2], [2]),
        ) {
        (Ok(p), Ok(m), Ok(n)) => Ok(p + ":" + m + "#" + n)
        (Err(e), _, _) | (_, Err(e), _) | (_, _, Err(e)) => Err(e)
      }
    }
    _ => Err(name_error("invalid_name: I expected an FQName string or array."))
  }
}
