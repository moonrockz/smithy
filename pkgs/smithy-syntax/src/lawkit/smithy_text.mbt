///|
/// A string of these UTF-16 code units. A string literal cannot hold a
/// lone surrogate; this can.
pub fn units(xs : Array[Int32]) -> String {
  let sb = StringBuilder()
  for x in xs {
    sb.write_char(x.unsafe_to_char())
  }
  sb.to_string()
}

///|
/// Characters at the edges of what the scanner handles: lone surrogates, a
/// pair, CR, CRLF, LF, tab, a byte order mark, ASCII, non-ASCII, nothing.
pub fn edge_chars() -> Array[String] {
  [
    units([0xD800]),
    units([0xDC00]),
    units([0xD83D, 0xDE00]),
    "\r",
    "\r\n",
    "\n",
    "\t",
    "\u{FEFF}",
    "a",
    "é",
    "€",
    "",
  ]
}

///|
/// Token texts of the Smithy IDL, one of each kind, plus keywords.
pub fn token_pieces() -> Array[String] {
  [
    "namespace", "use", "metadata", "apply", "structure", "list", "map", "set", "union",
    "enum", "intEnum", "service", "resource", "operation", "string", "integer", "blob",
    "boolean", "document", "byte", "short", "long", "float", "double", "bigInteger",
    "bigDecimal", "timestamp", "with", "for", "input", "output", "errors", "true",
    "false", "null", "Foo", "foo_bar", "_x", "__y1", "smithy.api#String", "Foo$bar",
    "0", "42", "-1", "1.5", "1e3", "\"\"", "\"hi\"", "\"a\\nb\"", "\"\"\"\n  x\n  \"\"\"",
    "@", ":", ":=", "=", ".", "#", "$", "{", "}", "[", "]", "(", ")", ",", " ", "\n",
    "\r\n", "\t", "//", "///", "// c", "/// d", "$version: \"2\"",
  ]
}

///|
/// Fragments the scanner rejects: open strings and blocks, bad escapes,
/// bad numbers, odd characters.
pub fn broken_pieces() -> Array[String] {
  [
    "\"", "\"abc", "\\", "\"\\q\"", "\"\\u", "\"\\u12\"", "\"\"\"", "\"\"\"x\"\"\"",
    "01", "1.", "1e", "1e+", "-", "-a", "^", "&", ";", "'", "`", "~", "|", "!", "?",
    "%", "*", "+", "<", ">", "\u{00A0}", "\u{201C}", "1e2147483648", "1e-2147483648",
    "1e99999999999",
  ]
}

///|
/// A small valid Smithy 2.0 model: every statement form, every shape
/// kind, docs, traits, mixins, elision, an inline shape and an apply.
pub fn small_model() -> String {
  (
    #|$version: "2"
    #|
    #|metadata foo = ["bar"]
    #|
    #|namespace smithy.example
    #|
    #|use smithy.api#String
    #|
    #|/// Docs.
    #|@deprecated(message: "old")
    #|structure Foo with [Mix] {
    #|    @required
    #|    bar: String = "x"
    #|    $baz
    #|}
    #|
    #|@mixin
    #|structure Mix {
    #|    baz: Integer
    #|}
    #|
    #|enum Color {
    #|    RED = "red"
    #|    BLUE
    #|}
    #|
    #|list Names {
    #|    member: String
    #|}
    #|
    #|service Shop {
    #|    version: "2024-01-01"
    #|    operations: [GetFoo]
    #|}
    #|
    #|operation GetFoo {
    #|    input := {
    #|        id: String
    #|    }
    #|    output: Foo
    #|    errors: [NotFound]
    #|}
    #|
    #|@error("client")
    #|structure NotFound {}
    #|
    #|apply Foo @since("1.0")
    #|
  )
}

///|
fn pick(rs : @splitmix.RandomState, n : Int32) -> Int32 {
  rs.next_uint(limit=n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
fn one_of(rs : @splitmix.RandomState, xs : Array[String]) -> String {
  xs[pick(rs, xs.length())]
}

///|
/// One piece: a token, a broken fragment, an edge character, an edge
/// character inside a literal or comment form, or a cut of the small model.
fn piece(rs : @splitmix.RandomState) -> String {
  match pick(rs, 10) {
    0 | 1 | 2 => one_of(rs, token_pieces())
    3 | 4 => one_of(rs, broken_pieces())
    5 | 6 => one_of(rs, edge_chars())
    7 => {
      let edge = one_of(rs, edge_chars())
      match pick(rs, 6) {
        0 => "\"" + edge + "\""
        1 => "\"" + edge
        2 => "// " + edge
        3 => "/// " + edge + "\n"
        4 => "\"\\" + edge + "\""
        _ => "\"\"\"\n" + edge + "\n\"\"\""
      }
    }
    _ => {
      let m = small_model()
      let cut = pick(rs, m.length() + 1)
      if pick(rs, 2) == 0 {
        m.unsafe_substring(start=0, end=cut)
      } else {
        m.unsafe_substring(start=cut, end=m.length())
      }
    }
  }
}

///|
/// Text that is mostly not valid Smithy, for laws that must hold for any
/// text: no crash, lossless scan, spans in bounds. It is a list of pieces;
/// `text()` joins them. It shrinks by dropping a piece or halving the
/// longest one.
pub(all) struct SmithyText(Array[String]) derive(Debug)

///|
/// The pieces joined into one text.
pub fn SmithyText::text(self : SmithyText) -> String {
  self.0.join("")
}

///|
/// Up to `size + 1` random pieces.
pub impl @quickcheck.Arbitrary for SmithyText with fn arbitrary(size, rs) {
  SmithyText(Array::makei(pick(rs, size + 1), _ => piece(rs)))
}

///|
/// Drop one piece, or halve the longest piece over length 1.
pub impl @quickcheck.Shrink for SmithyText with fn shrink(self) {
  let SmithyText(parts) = self
  let out = Array::makei(parts.length(), i => {
    let fewer = parts.copy()
    ignore(fewer.remove(i))
    SmithyText(fewer)
  })
  let mut longest = -1
  for i, p in parts {
    if p.length() > 1 && (longest < 0 || p.length() > parts[longest].length()) {
      longest = i
    }
  }
  if longest >= 0 {
    let halved = parts.copy()
    let p = parts[longest]
    halved[longest] = p.unsafe_substring(start=0, end=p.length() / 2)
    out.push(SmithyText(halved))
  }
  out.iter()
}
