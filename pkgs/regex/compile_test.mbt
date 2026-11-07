///|
test "compilation accepts runtime data and erases grouping" {
  for pattern in ["abc", "(a|b)+", "(?<name>a)+", "[a-z]+", "", "😀"] {
    ignore(@regex.Regex::compile(pattern))
  }
}

///|
test "compilation stops before counted expansion and recursion" {
  for
    (pattern, limits, expected) in [
      ("(?:a{256}){256}", @regex.CompileLimits::new(), @regex.Expansion),
      ("abcd", @regex.CompileLimits::new(source_units=3), @regex.SourceLength),
      ("((a))", @regex.CompileLimits::new(nesting=1), @regex.Nesting),
      (
        "a{256}",
        @regex.CompileLimits::new(expanded_units=257),
        @regex.Expansion,
      ),
    ] {
    let actual = try {
      ignore(@regex.Regex::compile(pattern, limits~))
      None
    } catch {
      @regex.CompilationLimit(reason) => Some(reason)
      _ => fail("Expected a compilation-limit error")
    }
    assert_eq(actual, Some(expected))
  }
  ignore(
    @regex.Regex::compile(
      "a{256}",
      limits=@regex.CompileLimits::new(expanded_units=258),
    ),
  )
}

///|
test "limits validate without integer wrap and zero work is representable" {
  assert_eq(@regex.WorkLimit::new(0).units(), 0)
  assert_eq(@regex.WorkLimit::new(10000000).units(), 10000000)
  for units in [-1, 10000001, 0x7fffffff] {
    let rejected = try {
      ignore(@regex.WorkLimit::new(units))
      false
    } catch {
      @regex.ConfigurationError(_) => true
    }
    assert_true(rejected)
  }
  let rejected = try {
    ignore(@regex.CompileLimits::new(expanded_units=0x7fffffff))
    false
  } catch {
    @regex.ConfigurationError(_) => true
  }
  assert_true(rejected)
}

///|
test "invalid and unsupported syntax are compilation errors" {
  for pattern in ["[", "a(?=b)", "(a)\\1", "\\d"] {
    let rejected = try {
      ignore(@regex.Regex::compile(pattern))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
