///|
let atoms : Array[String] = [
  "a", "b", "-", "[ab]", "[^a]", "[a-z0-9]", "[A-Z]", "[^\\n\\r\\u2028\\u2029]",
  "(?:a|b)", "(?:ab|a)", "\\u00e9", "😀", "[😀a]", "[\\u0000-\\uFFFF]", "[\\-a]",
]

///|
/// Assertions, which take no quantifier.
let assertions : Array[String] = ["\\b", "\\B", "^", "$"]

///|
let quantifiers : Array[String] = [
  "", "", "", "*", "+", "?", "{2}", "{1,3}", "{0,}", "*?", "+?", "??",
]

///|
/// Letters of the inputs, with both halves of a surrogate pair alone.
let letters : Array[String] = [
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
]

///|
fn pick(items : Array[String], code : Int32) -> String {
  items[(code % items.length() + items.length()) % items.length()]
}

///|
/// A pattern of the portable profile, built from `codes`.
fn pattern_of(codes : Array[Int32]) -> String {
  let out = StringBuilder()
  for i, code in codes[:Int32::min(codes.length(), 8)] {
    if i > 0 && code % 11 == 0 {
      out.write_string("|")
    }
    if code % 5 == 0 {
      out.write_string(pick(assertions, code / 5))
    } else {
      out.write_string(pick(atoms, code))
      out.write_string(pick(quantifiers, code / 7))
    }
  }
  out.to_string()
}

///|
fn text_of(codes : Array[Int32]) -> String {
  codes.map(code => pick(letters, code)).join("")
}

///|
fn core_matches(pattern : String, text : String) -> Bool? {
  let regex = @string.Regex(pattern) catch { _ => return None }
  Some(regex.execute(text) is Some(_))
}

///|
test "law: the metered matcher agrees with core on the portable profile" {
  @quickcheck.check(
    (input : (Array[Int32], Array[Array[Int32]])) => {
      let pattern = pattern_of(input.0)
      let regex = @regex.Regex::compile(pattern) catch {
        _ => return core_matches(pattern, "") is None
      }
      for codes in input.1 {
        let text = text_of(codes)
        // A search that runs out of work leaves no partial state behind.
        ignore(regex.matches(text, work=text.length() + 3))
        guard regex.matches(text, work=0x7fffffff) is Some((matched, _)) else {
          return false
        }
        if core_matches(pattern, text) != Some(matched) {
          return false
        }
      }
      true
    },
    count=400,
    max_size=12,
    seed=4113,
  )
}

///|
test "a search spends one unit for each code unit and stops when it needs more" {
  let regex = @regex.Regex::compile("^a+$")
  ignore(regex.matches("aaaa", work=1000))
  assert_eq(regex.matches("aaaa", work=1000), Some((true, 5)))
  assert_eq(regex.matches("aaaa", work=5), Some((true, 5)))
  assert_eq(regex.matches("aaaa", work=4), None)
  assert_eq(regex.matches("aaaa", work=1000), Some((true, 5)))
}

///|
test "building a state spends the nodes and threads it visits" {
  let regex = @regex.Regex::compile("^(?:a?){150}a{150}$")
  // One state of this pattern visits about 50,000 expression nodes.
  assert_eq(regex.matches("a", work=10000), None)
  guard regex.matches("a", work=0x7fffffff) is Some((false, spent)) else {
    fail("expected a completed search")
  }
  assert_true(spent > 40000)
}

///|
test "a chain of 200 optional items stops at the default work limit" {
  let regex = @regex.Regex::compile("^(?:a?){200}a{200}$")
  // One derivative of this pattern visits about 100,000 expression nodes.
  assert_eq(regex.matches("a".repeat(10), work=100000), None)
  assert_eq(regex.matches("a".repeat(200), work=100000), None)
}
