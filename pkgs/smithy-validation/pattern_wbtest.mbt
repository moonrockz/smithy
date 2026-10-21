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
