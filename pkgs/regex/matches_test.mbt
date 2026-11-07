///|
test "portable work-count fixtures" {
  debug_inspect(
    @regex.Regex::compile("^a+$").matches(
      "aaaa",
      work=@regex.WorkLimit::new(100000),
    ),
    content=(
      #|Complete(true, 123)
    ),
  )
  debug_inspect(
    @regex.Regex::compile("\\bfoo\\b").matches(
      "!foo!",
      work=@regex.WorkLimit::new(100000),
    ),
    content=(
      #|Complete(true, 336)
    ),
  )
}

///|
fn completed(pattern : String, input : String) -> (Bool, Int32) raise {
  match
    @regex.Regex::compile(pattern).matches(
      input,
      work=@regex.WorkLimit::new(10000000),
    ) {
    Complete(matched, used) => (matched, used)
    Exhausted(_) => fail("Expected a completed search")
  }
}

///|
test "Boolean search agrees with core for anchors grouping Unicode and nullable loops" {
  for
    pattern in [
      "abc", "^abc$", "(a|b)+", "(?<name>a)*", "(?:a?)*b", "(?:|a)+$", "^.$", "^..$",
      "[a-z]+", "[^é]", "😀", "[😀a]", "\\bfoo\\b", "\\B", "^(?:a?){150}a{150}$",
      "(?:a|aa)+$", "^(?:a+)+$", "", "$", "^",
    ] {
    let core = @string.Regex(pattern)
    for
      input in [
        "",
        "abc",
        "!abc!",
        "abba",
        "aaaa!",
        "b",
        "foo",
        "é",
        "😀",
        "\n",
        "!foo!",
        "a".repeat(150),
      ] {
      assert_eq(
        completed(pattern, input).0,
        core.execute(input) is Some(_),
        msg=pattern + " on " + input,
      )
    }
  }
}

///|
test "exact budgets and recovery are independent of earlier calls" {
  let regex = @regex.Regex::compile("a(?:a|b){10}c")
  let value = "ababbaaabbabbababababa"
  let expected = regex.matches(value, work=@regex.WorkLimit::new(10000000))
  guard expected is Complete(false, used) else {
    fail("Expected a completed non-match")
  }
  assert_true(used > value.length() + 1)
  assert_eq(regex.matches(value, work=@regex.WorkLimit::new(0)), Exhausted(0))
  assert_eq(regex.matches(value, work=@regex.WorkLimit::new(used)), expected)
  for limit in [value.length() + 1, used / 2, used - 1] {
    let result = regex.matches(value, work=@regex.WorkLimit::new(limit))
    guard result is Exhausted(spent) else { fail("Expected exhaustion") }
    assert_true(spent <= limit)
    assert_eq(
      regex.matches(value, work=@regex.WorkLimit::new(10000000)),
      expected,
    )
  }
  for input in ["", "aaac", "ababababababac", value] {
    assert_eq(
      regex.matches(input, work=@regex.WorkLimit::new(100000)),
      @regex.Regex::compile("a(?:a|b){10}c").matches(
        input,
        work=@regex.WorkLimit::new(100000),
      ),
    )
  }
}

///|
test "law: runtime Boolean matches and budget boundaries agree with core" {
  let atoms = [
    "a", "b", "(?:a|b)", "(?:|a)", "(?:a?)*", "[ab]", "[^b]", ".", "😀", "\\b",
    "\\B", "^", "$",
  ]
  @quickcheck.check(
    (input : (Array[Int32], Array[Int32])) => {
      let pattern = input.0[:Int32::min(12, input.0.length())]
        .map(x => atoms[(x & 0x7fffffff) % atoms.length()])
        .join("")
      let regex = @regex.Regex::compile(pattern) catch { _ => return true }
      let core = @string.Regex(pattern) catch { _ => return false }
      let letters = [
        "a",
        "b",
        " ",
        "\n",
        "😀",
        "😀".view(end_offset=1).to_owned(),
        "😀".view(start_offset=1).to_owned(),
      ]
      let text = input.1[:Int32::min(30, input.1.length())]
        .map(x => letters[(x & 0x7fffffff) % letters.length()])
        .join("")
      let result = regex.matches(
        text,
        work=try! @regex.WorkLimit::new(10000000),
      )
      guard result is Complete(matched, used) else { return false }
      if matched != (core.execute(text) is Some(_)) {
        return false
      }
      let at = regex.matches(text, work=try! @regex.WorkLimit::new(used))
      let below = regex.matches(text, work=try! @regex.WorkLimit::new(used - 1))
      at == result && below is Exhausted(_)
    },
    count=500,
    max_size=24,
    seed=602,
  )
}
