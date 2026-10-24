///|
let fqname_pattern = "^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*:([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*#([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*$"

///|
fn BoundedPattern::execute(self : BoundedPattern, text : String) -> Bool {
  self.matches(text, work=0x7fffffff) is Some((true, _))
}

///|
test "portable patterns translate escapes without changing literals or classes" {
  let id = @smithy.ShapeId::parse("example#String").unwrap()
  for
    (pattern, good, bad) in [
      ("^\\d+$", "123", "x123"),
      ("^[\\w\\d]+$", "a_9", "a-9"),
      ("^\\\\d$", "\\d", "7"),
      ("^a.b$", "acb", "a\nb"),
      ("^\\s+$", "\u{00a0}\t", "x"),
      ("a+", "xxaaa", "xyz"),
      ("^(?:a|b){1,3}$", "aba", "abab"),
    ] {
    let compiled = compile_pattern(pattern, id)
    assert_true(compiled.execute(good), msg=pattern)
    assert_false(compiled.execute(bad), msg=pattern)
  }
}

///|
test "pattern size counts the copies the automaton builds" {
  let id = @smithy.ShapeId::parse("example#String").unwrap()
  let nested = "^" + "(?:".repeat(8) + "a" + ")*".repeat(8) + "$"
  for
    (pattern, size) in [
      ("^[a-z]$", 3),
      ("^[a-z0-9]+$", 8), // a class counts its members
      ("^a?$", 6), // ? counts two copies: the automaton follows optional chains
      ("^(?:a*)*$", 8),
      ("^(?:a+)+$", 14), // control: + still counts two copies
      ("^[^a]$", 6), // control: a negated class keeps its source length
      (nested, 27), // 8 nested stars: linear, not exponential
      (fqname_pattern, 172),
      ("^[\\d_]$", 4), // class escape counts its expanded members
      ("^[\\w]$", 6),
      ("^[\\s]$", 17),
      ("^[😀]$", 6), // literal astral character: source length
      ("^[\\u00e9a-z]$", 4),
    ] {
    assert_eq(
      pattern_size(translate_pattern(pattern, id), id),
      size,
      msg=pattern,
    )
  }
}

///|
test "class dashes follow ECMA-262 ClassRanges" {
  let id = @smithy.ShapeId::parse("example#String").unwrap()
  for
    (pattern, good, bad) in [
      ("^[a-]$", ["a", "-"], ["b"]), // last in class
      ("^[-a]$", ["a", "-"], ["b"]), // first in class
      ("^[a\\-]$", ["a", "-"], ["\\"]), // escaped
      ("^[^-a]$", ["b", "z"], ["-", "a"]), // negated, first
      ("^[a-c]$", ["b"], ["-", "d"]), // a real range
      ("^[a-c-e]$", ["a", "-", "e"], ["d"]), // dash after a range
      ("^[!--]$", ["!", ",", "-"], ["a"]), // dash as the high end
      ("^[\\d-a]$", ["5", "-", "a"], ["b"]), // dash after a class escape
      ("^[\\u0041-\\u005a]$", ["M"], ["a", "-"]), // \u escapes as range ends
      ("^[\\d-a-c]$", ["a", "c", "-", "5"], ["b"]), // Annex B pseudo-range
      ("^[\\d--a]$", ["-", "a", "5"], ["A", "."]),
      ("^[\\d-\\w]$", ["5", "a", "_", "-"], ["."]), // union of two class escapes
      ("^[0-9/-]+$", ["12/3-4"], ["a"]),
      (
        "^[A-Za-z0-9/-]+:[A-Za-z0-9/-]+#[A-Za-z0-9-]+$",
        ["morphir/SDK:basics#int", "finos-x/a-b:c/d-e#f-g"],
        ["a:b#c!", "a:b:c#d"],
      ),
    ] {
    let compiled = compile_pattern(pattern, id)
    for text in good {
      assert_true(compiled.execute(text), msg=pattern + " / " + text)
    }
    for text in bad {
      assert_false(compiled.execute(text), msg=pattern + " / " + text)
    }
  }
}

///|
test "a braced unicode escape is rejected" {
  let id = @smithy.ShapeId::parse("example#String").unwrap()
  for pattern in ["^[\\u{41}]$", "^\\u{41}$"] {
    let mut message = ""
    ignore(compile_pattern(pattern, id)) catch {
      UnsupportedConstraint(_, text) => message = text
      _ => fail("Expected UnsupportedConstraint")
    }
    assert_true(message.contains("\\u{"), msg=pattern)
  }
}

///|
test "vertical tab matches \\s and \\v, and the letter v and a backslash do not" {
  let id = @smithy.ShapeId::parse("example#String").unwrap()
  for
    (pattern, good, bad) in [
      ("^\\s$", "\u{0b}", "v"),
      ("^\\s$", "\u{0b}", "\\"),
      ("^\\S$", "v", "\u{0b}"),
      ("^\\S$", "\\", "\u{0b}"),
      ("^[\\s]$", "\u{0b}", "v"),
      ("^[\\s]$", "\u{0b}", "\\"),
      ("^\\S+$", "value", "a\u{0b}b"),
      ("^\\v$", "\u{0b}", "v"),
      ("^[\\v]$", "\u{0b}", "v"),
    ] {
    let compiled = compile_pattern(pattern, id)
    assert_true(compiled.execute(good), msg=pattern + " good")
    assert_false(compiled.execute(bad), msg=pattern + " bad")
  }
}
