///|
/// The words that MoonBit 0.10.15 refuses or reserves as identifiers. I found
/// them with the compiler: each is an error or a `reserved_keyword` warning.
let moonbit_keywords : Array[String] = [
  "abstract", "alias", "and", "as", "assert", "async", "await", "break", "catch",
  "const", "continue", "declare", "defer", "derive", "do", "dyn", "else", "enum",
  "enumview", "export", "extern", "false", "final", "fn", "fnalias", "for", "guard",
  "if", "impl", "import", "in", "include", "is", "lazy", "let", "letrec", "lexmatch",
  "local", "loop", "macro", "match", "member", "method", "module", "move", "mut",
  "namespace", "nobreak", "noraise", "override", "package", "priv", "protected",
  "pub", "raise", "readonly", "recur", "ref", "resume", "return", "sealed", "static",
  "struct", "suberror", "super", "test", "throw", "trait", "traitalias", "true",
  "try", "type", "typealias", "typeof", "unsafe", "use", "using", "var", "virtual",
  "void", "volatile", "where", "while", "with", "yield",
]

///|
/// The type names that the generated code uses from the core library. A shape
/// with one of these names gets a `_` suffix.
let moonbit_type_names : Array[String] = [
  "Array", "Bool", "Byte", "Bytes", "Char", "Double", "Error", "Float", "FixedArray",
  "Int", "Int16", "Int64", "Json", "Map", "Option", "Result", "Self", "Set", "String",
  "StringBuilder", "UInt", "UInt16", "UInt64", "Unit",
]

///|
/// The words of a name. A word ends at `_`, `-`, `.`, `$`, at a change from a
/// lower-case letter or a digit to an upper-case letter, and before the last
/// upper-case letter of a run that a lower-case letter follows (`HTTPServer` is
/// `HTTP` and `Server`).
fn words(name : String) -> Array[String] {
  let chars = name.to_array()
  let out : Array[String] = []
  let current = StringBuilder()
  let flush = () => {
    let word = current.to_string()
    if !word.is_empty() {
      out.push(word)
    }
    current.reset()
  }
  for index, c in chars {
    if c == '_' || c == '-' || c == '.' || c == '$' || c == ' ' || c == '/' {
      flush()
      continue
    }
    if c.is_ascii_uppercase() && index > 0 {
      let before = chars[index - 1]
      let after_lower = index + 1 < chars.length() &&
        chars[index + 1].is_ascii_lowercase()
      if before.is_ascii_lowercase() ||
        before.is_ascii_digit() ||
        (before.is_ascii_uppercase() && after_lower) {
        flush()
      }
    }
    current.write_char(c)
  }
  flush()
  out
}

///|
fn capitalize(word : String) -> String {
  let chars = word.to_lower().to_array()
  if chars.is_empty() {
    return ""
  }
  chars[0] = chars[0].to_ascii_uppercase()
  String::from_array(chars)
}

///|
/// A `snake_case` name for a field, a function or a method. A keyword gets a
/// `_` suffix. A name that starts with a digit gets an `n` prefix.
pub fn snake_name(name : String) -> String {
  let text = words(name).map(word => word.to_lower()).join("_")
  let text = if text.is_empty() { "value" } else { text }
  let text = if text.to_array()[0].is_ascii_digit() { "n" + text } else { text }
  if moonbit_keywords.contains(text) {
    text + "_"
  } else {
    text
  }
}

///|
/// A `PascalCase` name for an enum or a union variant. `INSERT_CARD` is
/// `InsertCard`, `manualEntry` is `ManualEntry` and `USD` is `Usd`.
pub fn variant_name(name : String) -> String {
  let text = words(name).map(capitalize).join("")
  let text = if text.is_empty() { "Value" } else { text }
  if text.to_array()[0].is_ascii_digit() {
    "V" + text
  } else {
    text
  }
}

///|
/// The name of a generated type: the contextual name with an upper-case first
/// letter. A name that the core library uses gets a `_` suffix.
pub fn type_name(name : String) -> String {
  let chars = name.to_array()
  let text = if chars.is_empty() {
    "Value"
  } else {
    chars[0] = chars[0].to_ascii_uppercase()
    String::from_array(chars)
  }
  if moonbit_type_names.contains(text) {
    text + "_"
  } else {
    text
  }
}

///|
/// The text of a MoonBit string literal.
fn mbt_string(text : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in text {
    match c {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      c if c.to_int() < 0x20 => {
        let hex = c.to_int().to_string(radix=16)
        out.write_string("\\u{" + hex + "}")
      }
      c => out.write_char(c)
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
/// One JSON Pointer token (RFC 6901): `~` is `~0` and `/` is `~1`.
fn pointer_token(name : String) -> String {
  name.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}
