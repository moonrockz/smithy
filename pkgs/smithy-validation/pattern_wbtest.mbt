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
      ("^[\\u{1F600}]$", 104), // astral: source length
      ("^[😀]$", 48), // literal astral character: source length
      ("^[\\u00e9a-z]$", 32),
    ] {
    assert_eq(compile_pattern(pattern, id).weight, weight, msg=pattern)
  }
}
