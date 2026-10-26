///|
/// The keywords of Python 3.11. A field, a method or a parameter with one of
/// these names gets a `_` suffix.
let python_keywords : Array[String] = [
  "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class",
  "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global",
  "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise",
  "return", "try", "while", "with", "yield",
]

///|
/// The attributes of a Pydantic `BaseModel`, and the names that the generated
/// classes use. A field with one of these names gets a `_` suffix.
let model_attributes : Array[String] = [
  "construct", "copy", "dict", "from_orm", "json", "model_computed_fields", "model_config",
  "model_construct", "model_copy", "model_dump", "model_dump_json", "model_extra",
  "model_fields", "model_fields_set", "model_json_schema", "model_parametrized_name",
  "model_post_init", "model_rebuild", "model_validate", "model_validate_json", "model_validate_strings",
  "parse_file", "parse_obj", "parse_raw", "schema", "schema_json", "union_member",
  "update_forward_refs", "validate",
]

///|
/// The names that the generated modules import or define. A shape with one of
/// these names gets a `_` suffix.
let python_type_names : Array[String] = [
  "Annotated", "Any", "BaseModel", "BigDecimal", "BigInteger", "Blob", "Byte", "CallContext",
  "Callable", "CancelRule", "Decimal", "FastAPI", "Integer", "Long", "Short", "TypeAlias",
  "CapabilitySource", "ClassVar", "ConfigDict", "DateTimeTimestamp", "Discriminator",
  "Document", "Double", "Enum", "EpochSecondsTimestamp", "Exception", "Field", "HttpDateTimestamp",
  "IntEnum", "JsonValue", "MethodKind", "MethodRule", "ModeledError", "Peer", "Protocol",
  "RpcError", "SessionRules", "StrEnum", "StrictBool", "Tag", "Timestamp", "TranscriptLog",
  "TypeAdapter", "Unit",
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
/// A `snake_case` name for a field, a method or a function. A keyword or a
/// model attribute gets a `_` suffix. A name that starts with a digit gets an
/// `n` prefix.
pub fn snake_name(name : String) -> String {
  let text = words(name).map(word => word.to_lower()).join("_")
  let text = if text.is_empty() { "value" } else { text }
  let text = if text.to_array()[0].is_ascii_digit() { "n" + text } else { text }
  if python_keywords.contains(text) || model_attributes.contains(text) {
    text + "_"
  } else {
    text
  }
}

///|
/// The name of a handler or client method: a `snake_case` name. The client
/// keeps its peer in attribute `peer`, so a method `peer` gets a `_` suffix.
pub fn method_name(name : String) -> String {
  let text = snake_name(name)
  if text == "peer" {
    text + "_"
  } else {
    text
  }
}

///|
/// A `PascalCase` part of a class name, such as the member part of a union
/// member class. `manualEntry` is `ManualEntry`.
pub fn pascal_name(name : String) -> String {
  let text = words(name).map(capitalize).join("")
  let text = if text.is_empty() { "Value" } else { text }
  if text.to_array()[0].is_ascii_digit() {
    "V" + text
  } else {
    text
  }
}

///|
/// An `UPPER_SNAKE` name for an enum member. `insertCard` is `INSERT_CARD`
/// and `USD` stays `USD`.
pub fn enum_member_name(name : String) -> String {
  let text = words(name).map(word => word.to_upper()).join("_")
  let text = if text.is_empty() { "VALUE" } else { text }
  if text.to_array()[0].is_ascii_digit() {
    "V_" + text
  } else {
    text
  }
}

///|
/// The name of a generated class: the contextual name with an upper-case
/// first letter. A name that the generated modules use gets a `_` suffix.
pub fn class_name(name : String) -> String {
  let chars = name.to_array()
  let text = if chars.is_empty() {
    "Value"
  } else {
    chars[0] = chars[0].to_ascii_uppercase()
    String::from_array(chars)
  }
  if python_type_names.contains(text) || python_keywords.contains(text) {
    text + "_"
  } else {
    text
  }
}

///|
/// The text of a Python string literal in double quotes.
pub fn py_string(text : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in text {
    match c {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      c if c.to_int() < 0x20 || c.to_int() == 0x7f => {
        let hex = c.to_int().to_string(radix=16)
        let padded = if hex.length() < 2 { "0" + hex } else { hex }
        out.write_string("\\x" + padded)
      }
      c => out.write_char(c)
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
/// The text of a docstring line: a backslash, a quote or a control character
/// becomes a space, so the line never ends or escapes the docstring.
fn doc_text(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    if c == '\\' || c == '"' || c.to_int() < 0x20 {
      out.write_char(' ')
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// I accept a Python package name: ASCII letters, digits and `_`, with a
/// letter or `_` first, and not a keyword.
fn check_package_name(text : String) -> Unit raise @codegen.CodegenError {
  let chars = text.to_array()
  let valid = !chars.is_empty() &&
    (chars[0].is_ascii_alphabetic() || chars[0] == '_') &&
    chars
    .iter()
    .all(c => c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_') &&
    !python_keywords.contains(text)
  if !valid {
    raise @codegen.InvalidSettings(
      "I expected setting `package` to be a Python package name such as `payment_terminal`, found `\{text}`.",
    )
  }
}

///|
/// The distribution name of a package for `pyproject.toml`: `_` becomes `-`.
fn distribution_name(package_name : String) -> String {
  package_name.replace_all(old="_", new="-")
}
