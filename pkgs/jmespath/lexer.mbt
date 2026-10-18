///|
priv struct Token {
  tag : String
  text : String
  value : Json
  span : Span
}

///|
fn ascii_letter(c : UInt16) -> Bool {
  c == 95 || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
}

///|
fn ascii_digit(c : UInt16) -> Bool {
  c >= 48 && c <= 57
}

///|
fn lex(source : String) -> Array[Token] raise JmespathError {
  let tokens = []
  let mut i = 0
  while i < source.length() {
    let start = i
    let c = source.code_unit_at(i)
    if c == 32 || c == 9 || c == 10 || c == 13 {
      i += 1
      continue
    }
    let mut tag = ""
    let mut value = Json::null()
    if ascii_letter(c) {
      i += 1
      while i < source.length() &&
            (
              ascii_letter(source.code_unit_at(i)) ||
              ascii_digit(source.code_unit_at(i))
            ) {
        i += 1
      }
      tag = "identifier"
    } else if ascii_digit(c) || c == 45 {
      i += 1
      let digits = i
      while i < source.length() && ascii_digit(source.code_unit_at(i)) {
        i += 1
      }
      if c == 45 && i == digits {
        problem(
          Syntax,
          { start, end: i, },
          "I expected digits after '-' in an index.",
        )
      }
      tag = "number"
    } else if c == 34 || c == 39 || c == 96 {
      i += 1
      let contents = StringBuilder()
      let mut segment = i
      let mut closed = false
      while i < source.length() {
        let at = i
        let current = source.code_unit_at(i)
        i += 1
        if c == 39 && current < 32 {
          problem(
            Syntax,
            { start: at, end: i, },
            "I found control character \{Json::string(source[at:i].to_owned()).stringify()} in a JMESPath raw string.",
          )
        }
        if current == c {
          contents.write_stringview(source[segment:at])
          closed = true
          break
        }
        if current == 92 && i < source.length() {
          let escaped = source.code_unit_at(i)
          i += 1
          if c == 39 && escaped < 32 {
            problem(
              Syntax,
              { start: i - 1, end: i, },
              "I found control character \{Json::string(source[i - 1:i].to_owned()).stringify()} in a JMESPath raw string escape.",
            )
          }
          if (c == 39 && escaped == 39) || (c == 96 && escaped == 96) {
            contents.write_stringview(source[segment:at])
            contents.write_stringview(source[i - 1:i])
            segment = i
          }
        }
      }
      if !closed {
        problem(
          Syntax,
          { start, end: i, },
          "I expected a closing quote in the JMESPath expression.",
        )
      }
      if c == 39 {
        tag = "literal"
        value = Json::string(contents.to_string())
      } else {
        tag = if c == 34 { "quoted" } else { "literal" }
        let text = if c == 34 {
          source[start:i].to_owned()
        } else {
          contents.to_string()
        }
        value = @json.parse(text) catch {
          _ => {
            problem(
              Syntax,
              { start, end: i, },
              "I expected valid JSON in the JMESPath literal or quoted identifier.",
            )
            Json::null()
          }
        }
      }
    } else {
      i += 1
      // Keep an unexpected astral character intact in its diagnostic span.
      if c >= 0xD800 &&
        c <= 0xDBFF &&
        i < source.length() &&
        source.code_unit_at(i) >= 0xDC00 &&
        source.code_unit_at(i) <= 0xDFFF {
        i += 1
      }
      tag = source[start:i].to_owned()
      if i < source.length() {
        let pair = source[start:i + 1].to_owned()
        if ["[]", "[?", "||", "&&", "==", "!=", "<=", ">="].contains(pair) {
          tag = pair
          i += 1
        }
      }
      if ![
          ".", "[", "]", "[]", "[?", "(", ")", "{", "}", ",", ":", "*", "@", "&",
          "!", "|", "||", "&&", "==", "!=", "<", "<=", ">", ">=",
        ].contains(tag) {
        problem(
          Syntax,
          { start, end: i, },
          "I found an unexpected JMESPath token \{Json::string(tag).stringify()}.",
        )
      }
    }
    tokens.push({
      tag,
      text: source[start:i].to_owned(),
      value,
      span: { start, end: i, },
    })
  }
  tokens.push({
    tag: "eof",
    text: "",
    value: Json::null(),
    span: { start: i, end: i, },
  })
  tokens
}
