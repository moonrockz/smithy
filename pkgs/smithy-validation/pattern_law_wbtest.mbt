///|
/// Pieces of the portable pattern profile, as a Smithy model writes them.
let portable_atoms : Array[String] = [
  "a", "b", "-", ".", "\\d", "\\w", "\\s", "\\D", "\\W", "\\S", "[ab]", "[^a]", "[a-]",
  "[\\d-a]", "[a-z0-9]", "[^\\s]", "(a|b)", "(?:ab|a)", "(a-)", "😀", "[😀a]",
  "\\u00e9", "\\.",
]

///|
/// Assertions, which take no quantifier.
let portable_assertions : Array[String] = ["\\b", "\\B", "^", "$"]

///|
let portable_quantifiers : Array[String] = [
  "", "", "", "*", "+", "?", "{2}", "{1,3}", "{0,}", "*?", "+?",
]

///|
/// Letters of the inputs, with both halves of a surrogate pair alone.
let portable_letters : Array[String] = [
  "a",
  "b",
  "-",
  " ",
  "😀",
  "😀".view(end_offset=1).to_owned(),
  "😀".view(start_offset=1).to_owned(),
  "é",
  "\n",
  "A",
  "0",
  "_",
  ".",
]

///|
fn pick_piece(items : Array[String], code : Int32) -> String {
  items[(code % items.length() + items.length()) % items.length()]
}

///|
fn portable_pattern(codes : Array[Int32]) -> String {
  let out = StringBuilder()
  for i, code in codes[:Int32::min(codes.length(), 8)] {
    if i > 0 && code % 11 == 0 {
      out.write_string("|")
    }
    if code % 5 == 0 {
      out.write_string(pick_piece(portable_assertions, code / 5))
    } else {
      out.write_string(pick_piece(portable_atoms, code))
      out.write_string(pick_piece(portable_quantifiers, code / 7))
    }
  }
  out.to_string()
}

///|
test "law: prepared patterns match as @string.Regex matches their translation" {
  let id = @smithy.ShapeId::parse("example#String").unwrap()
  @quickcheck.check(
    (input : (Array[Int32], Array[Array[Int32]])) => {
      let pattern = portable_pattern(input.0)
      let compiled = compile_pattern(pattern, id) catch { _ => return true }
      let core = @string.Regex(translate_pattern(pattern, id)) catch {
        _ => return false
      }
      for codes in input.1 {
        let text = codes
          .map(code => pick_piece(portable_letters, code))
          .join("")
        // A search that runs out of work leaves no partial state behind.
        ignore(compiled.matches(text, work=text.length() + 3))
        guard compiled.matches(text, work=0x7fffffff) is Some((matched, _)) else {
          return false
        }
        if matched != (core.execute(text) is Some(_)) {
          return false
        }
      }
      true
    },
    count=500,
    max_size=12,
    seed=5309,
  )
}

///|
test "the generated portable patterns mostly pass preparation" {
  let id = @smithy.ShapeId::parse("example#String").unwrap()
  let samples : Array[Array[Int32]] = @quickcheck.samples(200)
  let mut prepared = 0
  for codes in samples {
    try compile_pattern(portable_pattern(codes), id) catch {
      _ => ()
    } noraise {
      _ => prepared += 1
    }
  }
  assert_true(prepared > 190, msg="\{prepared} of 200 prepared")
}
