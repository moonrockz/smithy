///|
pub(all) enum Kind {
  Plain
  Keyword
  Str
  Comment
  Number
  Tag
  /// A shape name.
  Type
  /// A `///` comment.
  DocComment
} derive(Eq, Debug)

///|
pub extend Kind with Eq::{equal, not_equal}

///|
pub extend Kind with @debug.Debug::{to_repr}

///|
pub(all) struct Token {
  kind : Kind
  text : String
} derive(Eq, Debug)

///|
pub extend Token with Eq::{equal, not_equal}

///|
pub extend Token with @debug.Debug::{to_repr}

///|
let moonbit_keywords : Array[String] = [
  "fn", "let", "mut", "if", "else", "match", "for", "while", "loop", "return", "break",
  "continue", "struct", "enum", "trait", "impl", "pub", "priv", "type", "test", "async",
  "raise", "noraise", "try", "catch", "guard", "is", "with", "using", "extern", "derive",
  "suberror", "true", "false",
]

///|
let smithy_shape_keywords : Array[String] = [
  "service", "resource", "operation", "structure", "union", "list", "map", "set",
  "string", "blob", "boolean", "byte", "short", "integer", "long", "float", "double",
  "bigInteger", "bigDecimal", "timestamp", "document", "enum", "intEnum", "apply",
]

///|
let smithy_statement_keywords : Array[String] = ["namespace", "use", "metadata"]

///|
/// Collects tokens and merges neighbouring plain text.
priv struct Out {
  tokens : Array[Token]
}

///|
fn Out::push(self : Out, kind : Kind, text : String) -> Unit {
  if text == "" {
    return
  }
  match (kind, self.tokens.last()) {
    (Plain, Some({ kind: Plain, text: prev, })) => {
      ignore(self.tokens.pop())
      self.tokens.push({ kind: Plain, text: prev + text, })
    }
    _ => self.tokens.push({ kind, text, })
  }
}

///|
fn is_ident_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// Index after a string literal that starts at `i` (a `"`). Stops at the end
/// of the line when the string is not closed.
fn string_end(s : Array[Char], i : Int32) -> Int32 {
  let mut j = i + 1
  while j < s.length() && s[j] != '\n' {
    if s[j] == '\\' && j + 1 < s.length() {
      j = j + 2
      continue
    }
    if s[j] == '"' {
      return j + 1
    }
    j = j + 1
  }
  j
}

///|
fn line_end(s : Array[Char], i : Int32) -> Int32 {
  let mut j = i
  while j < s.length() && s[j] != '\n' {
    j = j + 1
  }
  j
}

///|
fn slice(s : Array[Char], from : Int32, to : Int32) -> String {
  String::from_array(s[from:to].to_owned())
}

///|
fn scan_moonbit(s : Array[Char], out : Out) -> Unit {
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    if c == '/' && i + 1 < s.length() && s[i + 1] == '/' {
      let e = line_end(s, i)
      out.push(Comment, slice(s, i, e))
      i = e
    } else if c == '#' && i + 1 < s.length() && s[i + 1] == '|' {
      let e = line_end(s, i)
      out.push(Str, slice(s, i, e))
      i = e
    } else if c == '#' && i + 1 < s.length() && is_ident_char(s[i + 1]) {
      let mut j = i + 1
      while j < s.length() && (is_ident_char(s[j]) || s[j] == '.') {
        j = j + 1
      }
      out.push(Tag, slice(s, i, j))
      i = j
    } else if c == '"' {
      let e = string_end(s, i)
      out.push(Str, slice(s, i, e))
      i = e
    } else if is_digit(c) {
      let mut j = i
      while j < s.length() && (is_digit(s[j]) || s[j] == '_' || s[j] == '.') {
        j = j + 1
      }
      out.push(Number, slice(s, i, j))
      i = j
    } else if is_ident_char(c) {
      let mut j = i
      while j < s.length() && is_ident_char(s[j]) {
        j = j + 1
      }
      let word = slice(s, i, j)
      out.push(
        if moonbit_keywords.contains(word) {
          Keyword
        } else {
          Plain
        },
        word,
      )
      i = j
    } else {
      out.push(Plain, slice(s, i, i + 1))
      i = i + 1
    }
  }
}

///|
fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\t'
}

///|
/// Index after the text block that starts at `i` (`"""`). An unclosed block
/// runs to the end of the source.
fn text_block_end(s : Array[Char], i : Int32) -> Int32 {
  let mut j = i + 3
  while j < s.length() {
    if s[j] == '"' && j + 2 < s.length() && s[j + 1] == '"' && s[j + 2] == '"' {
      return j + 3
    }
    j = j + 1
  }
  s.length()
}

///|
/// Index after the number that starts at `i`: digits, a fraction and an exponent.
fn number_end(s : Array[Char], i : Int32) -> Int32 {
  let mut j = i
  if s[j] == '-' {
    j = j + 1
  }
  while j < s.length() {
    let c = s[j]
    if is_digit(c) || c == '.' {
      j = j + 1
    } else if (c == 'e' || c == 'E') &&
      j + 1 < s.length() &&
      (is_digit(s[j + 1]) || s[j + 1] == '+' || s[j + 1] == '-') {
      j = j + 2
    } else {
      break
    }
  }
  j
}

///|
/// Smithy IDL. Keywords are contextual, as in the scanner of `smithy-syntax`:
/// a shape keyword counts at the start of a line, and the name after it is a shape name.
fn scan_smithy(s : Array[Char], out : Out) -> Unit {
  let mut i = 0
  let mut line_start = true
  let mut expect_name = false
  let mut expect_mods = false
  while i < s.length() {
    let c = s[i]
    if c == '\n' {
      out.push(Plain, "\n")
      i = i + 1
      line_start = true
      expect_name = false
      expect_mods = false
      continue
    }
    if is_space(c) || c == ',' || c == '\r' {
      out.push(Plain, slice(s, i, i + 1))
      i = i + 1
      continue
    }
    let at_start = line_start
    line_start = false
    if c == '/' && i + 1 < s.length() && s[i + 1] == '/' {
      let e = line_end(s, i)
      let kind = if i + 2 < s.length() && s[i + 2] == '/' {
        DocComment
      } else {
        Comment
      }
      out.push(kind, slice(s, i, e))
      i = e
    } else if c == '"' &&
      i + 2 < s.length() &&
      s[i + 1] == '"' &&
      s[i + 2] == '"' {
      let e = text_block_end(s, i)
      out.push(Str, slice(s, i, e))
      i = e
    } else if c == '"' {
      let e = string_end(s, i)
      out.push(Str, slice(s, i, e))
      i = e
    } else if (c == '@' || c == '$') &&
      i + 1 < s.length() &&
      is_ident_char(s[i + 1]) {
      let mut j = i + 1
      while j < s.length() &&
            (is_ident_char(s[j]) || s[j] == '.' || s[j] == '#') {
        j = j + 1
      }
      out.push(if c == '@' { Tag } else { Keyword }, slice(s, i, j))
      i = j
    } else if is_digit(c) ||
      (c == '-' && i + 1 < s.length() && is_digit(s[i + 1])) {
      let e = number_end(s, i)
      out.push(Number, slice(s, i, e))
      i = e
    } else if is_ident_char(c) {
      let mut j = i
      while j < s.length() && is_ident_char(s[j]) {
        j = j + 1
      }
      let word = slice(s, i, j)
      let mut k = j
      while k < s.length() && is_space(s[k]) {
        k = k + 1
      }
      // `list: String` names a member, not a shape.
      let is_member = k < s.length() && s[k] == ':'
      if is_member {
        out.push(Plain, word)
      } else if at_start && smithy_shape_keywords.contains(word) {
        out.push(Keyword, word)
        expect_name = true
      } else if at_start && smithy_statement_keywords.contains(word) {
        out.push(Keyword, word)
      } else if expect_name {
        out.push(Type, word)
        expect_name = false
        expect_mods = true
      } else if expect_mods && (word == "for" || word == "with") {
        out.push(Keyword, word)
      } else if word == "true" || word == "false" || word == "null" {
        out.push(Keyword, word)
      } else {
        out.push(Plain, word)
      }
      i = j
    } else {
      if c == '{' {
        expect_name = false
        expect_mods = false
      }
      out.push(Plain, slice(s, i, i + 1))
      i = i + 1
    }
  }
}

///|
/// JSON and JSON Lines.
fn scan_json(s : Array[Char], out : Out) -> Unit {
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    if c == '"' {
      let e = string_end(s, i)
      out.push(Str, slice(s, i, e))
      i = e
    } else if is_digit(c) ||
      (c == '-' && i + 1 < s.length() && is_digit(s[i + 1])) {
      let e = number_end(s, i)
      out.push(Number, slice(s, i, e))
      i = e
    } else if is_ident_char(c) {
      let mut j = i
      while j < s.length() && is_ident_char(s[j]) {
        j = j + 1
      }
      let word = slice(s, i, j)
      out.push(
        if word == "true" || word == "false" || word == "null" {
          Keyword
        } else {
          Plain
        },
        word,
      )
      i = j
    } else {
      out.push(Plain, slice(s, i, i + 1))
      i = i + 1
    }
  }
}

///|
fn scan_shell(s : Array[Char], out : Out) -> Unit {
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    if c == '#' && (i == 0 || s[i - 1] == ' ' || s[i - 1] == '\n') {
      let e = line_end(s, i)
      out.push(Comment, slice(s, i, e))
      i = e
    } else if c == '"' || c == '\'' {
      let mut j = i + 1
      while j < s.length() && s[j] != c && s[j] != '\n' {
        j = j + 1
      }
      let e = if j < s.length() && s[j] == c { j + 1 } else { j }
      out.push(Str, slice(s, i, e))
      i = e
    } else {
      out.push(Plain, slice(s, i, i + 1))
      i = i + 1
    }
  }
}

///|
/// Tokens of `code` in `lang`. The token texts concatenate to `code`.
pub fn highlight(lang : String, code : String) -> Array[Token] {
  let out = Out::{ tokens: [], }
  let chars = code.to_array()
  match lang {
    "moonbit" | "mbt" => scan_moonbit(chars, out)
    "smithy" => scan_smithy(chars, out)
    "bash" | "sh" | "shell" | "console" | "zsh" => scan_shell(chars, out)
    "json" | "jsonl" => scan_json(chars, out)
    _ => out.push(Plain, code)
  }
  out.tokens
}
