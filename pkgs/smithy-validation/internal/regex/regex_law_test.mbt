///|
let atoms : Array[String] = [
  "a", "b", "-", "[ab]", "[^a]", "[a-z0-9]", "[A-Z]", "[^\\n\\r\\u2028\\u2029]",
  "(?:a|b)", "(?:ab|a)", "\\u00e9", "😀", "[😀a]", "[^😀]", "[\\u0000-\\uFFFF]",
  "[\\-a]", "(?:|a)", "(?:(?:a*b)+)", "(?:(?:(?:a|b)?)*)",
]

///|
/// Assertions, which take no quantifier.
let assertions : Array[String] = ["\\b", "\\B", "^", "$"]

///|
let quantifiers : Array[String] = [
  "", "", "", "*", "+", "?", "{2}", "{1,3}", "{0,}", "{0}", "{0,1}", "*?", "+?",
  "??", "{1,3}?", "{2}?",
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
/// A pattern of the engine syntax without captures, built from `codes`. Some
/// pieces are groups of an inner pattern under a quantifier, two levels deep.
fn pattern_of(codes : ArrayView[Int32], depth~ : Int32 = 0) -> String {
  let out = StringBuilder()
  let count = Int32::min(codes.length(), 8)
  let mut i = 0
  while i < count {
    let code = codes[i]
    if i > 0 && code % 11 == 0 {
      out.write_string("|")
    }
    if code % 5 == 0 {
      out.write_string(pick(assertions, code / 5))
    } else if code % 13 == 0 && depth < 2 && i + 1 < codes.length() {
      let inner = codes[i + 1:Int32::min(codes.length(), i + 4)]
      out.write_string("(?:" + pattern_of(inner, depth=depth + 1) + ")")
      out.write_string(pick(quantifiers, code / 7))
      i += inner.length()
    } else {
      out.write_string(pick(atoms, code))
      out.write_string(pick(quantifiers, code / 7))
    }
    i += 1
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
test "law: the metered matcher agrees with core and spends the same on every search" {
  @quickcheck.check(
    (input : (Array[Int32], Array[Array[Int32]])) => {
      let pattern = pattern_of(input.0[:])
      let regex = @regex.Regex::compile(pattern) catch {
        _ => return core_matches(pattern, "") is None
      }
      // `warm` has seen every earlier text; `regex` sees each text first.
      let warm = @regex.Regex::compile(pattern)
      for codes in input.1 {
        let text = text_of(codes)
        let cold = @regex.Regex::compile(pattern)
        guard cold.matches(text, work=0x7fffffff) is Some((matched, spent)) else {
          return false
        }
        if core_matches(pattern, text) != Some(matched) ||
          spent < text.length() + 1 {
          return false
        }
        // Stop the search at a point between the first step and the end; it
        // keeps no partial state, and the next searches spend the same.
        let total = codes.fold(init=0, (sum, code) => sum + (code & 0xffff))
        let stop = text.length() +
          1 +
          total % Int32::max(1, spent - text.length() - 1)
        if stop < spent && regex.matches(text, work=stop) is Some(_) {
          return false
        }
        if regex.matches(text, work=spent) != Some((matched, spent)) ||
          regex.matches(text, work=spent - 1) is Some(_) ||
          warm.matches(text, work=0x7fffffff) != Some((matched, spent)) {
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
test "a search spends the same units on a new and on a used automaton" {
  let regex = @regex.Regex::compile("^a+$")
  guard regex.matches("aaaa", work=1000) is Some((true, spent)) else {
    fail("expected a match")
  }
  assert_eq(regex.matches("aaaa", work=1000), Some((true, spent)))
  assert_eq(regex.matches("aaaa", work=spent), Some((true, spent)))
  assert_eq(regex.matches("aaaa", work=spent - 1), None)
  assert_eq(regex.matches("aaaa", work=1000), Some((true, spent)))
  // The second `a` takes the same transition as the third and the fourth.
  guard regex.matches("aaaaaaaa", work=1000) is Some((true, longer)) else {
    fail("expected a match")
  }
  assert_eq(longer, spent + 4)
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

///|
test "a capturing group fails compilation" {
  let mut rejected = false
  ignore(@regex.Regex::compile("^(a)$")) catch {
    @regex.CapturingGroup => rejected = true
    _ => fail("expected CapturingGroup")
  }
  assert_true(rejected)
  ignore(@regex.Regex::compile("^(?:a)$"))
}
