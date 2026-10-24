///|
let fqname_pattern = "^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*:([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*#([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*$"

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
test "pattern weight counts the copies the automaton builds" {
  let id = @smithy.ShapeId::parse("example#String").unwrap()
  let nested = "^" + "(?:".repeat(8) + "a" + ")*".repeat(8) + "$"
  for
    (pattern, weight) in [
      ("^[a-z]$", 24),
      ("^[a-z0-9]+$", 64), // a class counts its members
      ("^a?$", 48), // ? counts two copies: core follows optional chains
      ("^(?:a*)*$", 64),
      ("^(?:a+)+$", 112), // control: + still counts two copies
      ("^[^a]$", 48), // control: a negated class keeps its source length
      (nested, 216), // 8 nested stars: linear, not 1276 units
      (fqname_pattern, 1376),
      ("^[\\d_]$", 32), // class escape counts its expanded members
      ("^[\\w]$", 48),
      ("^[\\s]$", 136),
      ("^[😀]$", 48), // literal astral character: source length
      ("^[\\u00e9a-z]$", 32),
    ] {
    assert_eq(compile_pattern(pattern, id).weight, weight, msg=pattern)
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
