///|
/// A value that a template can use: an argument or a context value.
pub(all) enum TemplateValue {
  Null
  Bool(Bool)
  Int(Int32)
  Text(String)
  Sym(Symbol)
  Ref(SymbolReference)
  Call((CodeWriter) -> Unit raise CodegenError)
  List(Array[TemplateValue])
  Record(Map[String, TemplateValue])
}

///|
/// False for `Null`, `Bool(false)`, empty text, an empty list and an empty
/// record. True for every other value, also for `Int(0)`.
pub fn TemplateValue::is_truthy(self : TemplateValue) -> Bool {
  match self {
    Null => false
    Bool(value) => value
    Text(text) => !text.is_empty()
    List(items) => !items.is_empty()
    Record(fields) => !fields.is_empty()
    Int(_) | Sym(_) | Ref(_) | Call(_) => true
  }
}

///|
/// The text as a JSON string literal. I escape `"`, `\`, newline, carriage
/// return and tab. I write other code points below 0x20 as `\u00XX`. I keep
/// all other characters as they are.
pub fn json_string_literal(text : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in text {
    match c {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ =>
        if c.to_int() < 0x20 {
          out.write_string("\\u00")
          out.write_char(hex_digit(c.to_int() / 16))
          out.write_char(hex_digit(c.to_int() % 16))
        } else {
          out.write_char(c)
        }
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
fn hex_digit(value : Int32) -> Char {
  "0123456789abcdef"[value].to_int().unsafe_to_char()
}
