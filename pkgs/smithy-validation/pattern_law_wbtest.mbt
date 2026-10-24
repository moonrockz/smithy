///|
/// Pieces of the portable pattern profile, as a Smithy model writes them.
let portable_atoms : Array[String] = [
  "a", "b", "-", ".", "\\d", "\\w", "\\s", "\\D", "\\W", "\\S", "[ab]", "[^a]", "[a-]",
  "[\\d-a]", "[a-z0-9]", "[^\\s]", "(a|b)", "(?:ab|a)", "(a-)", "😀", "[😀a]",
  "\\u00e9", "\\.", "[^😀]", "(|a)", "((a*b)+)", "(((a|b)?)*)",
]

///|
/// Assertions, which take no quantifier.
let portable_assertions : Array[String] = ["\\b", "\\B", "^", "$"]

///|
let portable_quantifiers : Array[String] = [
  "", "", "", "*", "+", "?", "{2}", "{1,3}", "{0,}", "{0}", "{0,1}", "*?", "+?",
  "??", "{1,3}?", "{2}?",
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
/// A portable pattern built from `codes`. Some pieces are groups of an inner
/// pattern under a quantifier, two levels deep.
fn portable_pattern(codes : ArrayView[Int32], depth~ : Int32 = 0) -> String {
  let out = StringBuilder()
  let count = Int32::min(codes.length(), 8)
  let mut i = 0
  while i < count {
    let code = codes[i]
    if i > 0 && code % 11 == 0 {
      out.write_string("|")
    }
    if code % 5 == 0 {
      out.write_string(pick_piece(portable_assertions, code / 5))
    } else if code % 13 == 0 && depth < 2 && i + 1 < codes.length() {
      let inner = codes[i + 1:Int32::min(codes.length(), i + 4)]
      out.write_string("(" + portable_pattern(inner, depth=depth + 1) + ")")
      out.write_string(pick_piece(portable_quantifiers, code / 7))
      i += inner.length()
    } else {
      out.write_string(pick_piece(portable_atoms, code))
      out.write_string(pick_piece(portable_quantifiers, code / 7))
    }
    i += 1
  }
  out.to_string()
}

///|
test "law: prepared patterns match as @string.Regex matches their translation" {
  let id = @smithy.ShapeId::parse("example#String").unwrap()
  @quickcheck.check(
    (input : (Array[Int32], Array[Array[Int32]])) => {
      let pattern = portable_pattern(input.0[:])
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
    try compile_pattern(portable_pattern(codes[:]), id) catch {
      _ => ()
    } noraise {
      _ => prepared += 1
    }
  }
  assert_true(prepared > 190, msg="\{prepared} of 200 prepared")
}

///|
/// A prepared validator of a string with `pattern`, at `work` units.
fn pattern_validator(pattern : String, work : Int32) -> PreparedValidator raise {
  let loader = @smithy.Loader::new()
  let escaped = pattern.replace_all(old="\\", new="\\\\")
  ignore(
    loader.add_idl(
      "model.smithy",
      "$version: \"2\"\nnamespace example\n@pattern(\"" +
      escaped +
      "\")\nstring Value",
    ),
  )
  guard loader.assemble().model is Some(model) else { fail("no model") }
  PreparedValidator::prepare(
    model,
    @smithy.ShapeId::parse("example#Value").unwrap(),
    config=Config::new(limits=Limits::new(work~)),
  )
}

///|
test "law: a used validator gives the result of a new one for every value" {
  @quickcheck.check(
    (input : (Array[Int32], Array[Array[Int32]], Int32)) => {
      let pattern = portable_pattern(input.0[:])
      // Small limits, so that some values reach `LimitExceeded`.
      let work = 200 + (input.2 & 0x7fff)
      let warm = pattern_validator(pattern, work) catch { _ => return true }
      for codes in input.1 {
        let text = codes
          .map(code => pick_piece(portable_letters, code))
          .join("")
        let value = Json::string(text)
        let used = warm.validate_json(value)
        let fresh = pattern_validator(pattern, work).validate_json(value)
        if used.findings.map(f => f.code) != fresh.findings.map(f => f.code) ||
          used.complete != fresh.complete {
          return false
        }
      }
      true
    },
    count=100,
    max_size=8,
    seed=7741,
  )
}
