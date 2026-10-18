///|
fn error_of(source : String, input : Json) -> @jmespath.Diagnostic raise {
  try {
    @jmespath.search(source, input) |> ignore
    fail("expected an error for " + source)
  } catch {
    @jmespath.JmespathError(diagnostic) => diagnostic
    error => raise error
  }
}

///|
test "raw strings reject every C0 control with or without a preceding backslash" {
  for code in 0..<32 {
    let control = String::from_array([code.to_char().unwrap()])
    for escape in ["", "\\"] {
      let source = "'𝄞" + escape + control + "tail'"
      let diagnostic = try {
        @jmespath.parse(source) |> ignore
        fail("expected a syntax error for " + Json::string(source).stringify())
      } catch {
        @jmespath.JmespathError(diagnostic) => diagnostic
        error => raise error
      }
      assert_eq(diagnostic.code, @jmespath.Syntax)
      let start = 3 + escape.length()
      assert_eq(diagnostic.span, { start, end: start + 1, })
      assert_true(diagnostic.message.contains("raw string"))
    }
  }
}

///|
test "raw string boundaries and textual escapes remain literal" {
  for
    value in [
      "", " ", "\u007f", "\u0085", "\u2028", "𝄞", "line\\nbreak", "\\t", "\\u000a",
    ] {
    assert_eq(
      @jmespath.search("'" + value + "'", Json::null()),
      Json::string(value),
    )
  }
  assert_eq(@jmespath.search("'it\\'s'", Json::null()), Json::string("it's"))
  assert_eq(
    @jmespath.search("`\"line\\nbreak\"`", Json::null()),
    Json::string("line\nbreak"),
  )
  assert_eq(@jmespath.search("`\n123\n`", Json::null()), Json::number(123))
  assert_eq(
    @jmespath.search("\"line\\nbreak\"", @json.parse("{\"line\\nbreak\":true}")),
    Json::boolean(true),
  )
}

///|
test "public AST retains source spans and expression reference arguments" {
  let source = "sort_by(items, &name)"
  let expression = @jmespath.parse(source)
  assert_eq(expression.source, source)
  assert_eq(expression.root.span, { start: 0, end: source.length(), })
  guard expression.root.kind is Function("sort_by", args) else {
    fail("expected function")
  }
  assert_eq(args.length(), 2)
  assert_eq(args[0].kind, @jmespath.Field("items"))
  assert_eq(args[0].span, { start: 8, end: 13, })
  guard args[1].kind is ExpressionRef(field) else {
    fail("expected expression reference")
  }
  assert_eq(field.kind, @jmespath.Field("name"))
  assert_eq(args[1].span, { start: 15, end: 20, })
  assert_eq(field.span, { start: 16, end: 20, })
}

///|
test "parse errors and evaluation errors identify the failing construct" {
  let diagnostic = error_of("items[\n", Json::null())
  assert_eq(diagnostic.code, @jmespath.Syntax)
  assert_eq(diagnostic.line_column("items[\n"), (2, 1))
  assert_eq(error_of("items[\r", Json::null()).line_column("items[\r"), (2, 1))
  assert_eq(
    error_of("items[\r\n", Json::null()).line_column("items[\r\n"),
    (2, 1),
  )
  let astral = error_of("𝄞", Json::null())
  assert_eq(astral.span, { start: 0, end: 2, })
  assert_true(astral.message.contains("𝄞"))
  assert_eq(error_of("\"foo\"(@)", Json::null()).span, { start: 0, end: 5, })
  let diagnostic = error_of("length('𝄞') | unknown(@)", Json::null())
  assert_eq(diagnostic.code, @jmespath.UnknownFunction)
  assert_eq(diagnostic.span, { start: 15, end: 25, })
  assert_eq(error_of("length()", Json::null()).code, @jmespath.InvalidArity)
  assert_eq(error_of("length(`1`)", Json::null()).code, @jmespath.InvalidType)
  assert_eq(
    error_of("@[::0]", @json.parse("[1,2]")).code,
    @jmespath.InvalidValue,
  )
  assert_eq(
    error_of("sum(`[1e308,1e308]`)", Json::null()).code,
    @jmespath.InvalidValue,
  )
}

///|
test "compiled expressions are reusable and functions do not mutate input" {
  let input = @json.parse(
    "{\"items\":[3,1,2],\"objects\":[{\"k\":2},{\"k\":1},{\"k\":2}]}",
  )
  let before = input.stringify()
  for
    source in [
      "sort(items)", "reverse(items)", "sort_by(objects, &k)", "merge(@, `{\"extra\":true}`)",
    ] {
    let expression = @jmespath.parse(source)
    assert_eq(expression.evaluate(input), expression.evaluate(input))
    assert_eq(input.stringify(), before)
  }
  let expression = @jmespath.parse("sort_by(@, &k)[*].id")
  assert_eq(
    expression.evaluate(@json.parse("[{\"id\":1,\"k\":0},{\"id\":2,\"k\":0}]")),
    @json.parse("[1,2]"),
  )
}

///|
test "Unicode functions operate on code points including astral characters" {
  assert_eq(@jmespath.search("length('a𝄞b')", Json::null()), Json::number(3))
  assert_eq(
    @jmespath.search("reverse('a𝄞b')", Json::null()),
    Json::string("b𝄞a"),
  )
  assert_eq(
    @jmespath.search("sort(@)", @json.parse("[\"𝄞\",\"\",\"a\"]")),
    @json.parse("[\"a\",\"\",\"𝄞\"]"),
  )
}

///|
test "short circuits avoid function errors and map retains null results" {
  assert_eq(
    @jmespath.search("`true` || unknown()", Json::null()),
    Json::boolean(true),
  )
  assert_eq(
    @jmespath.search("`false` && unknown()", Json::null()),
    Json::boolean(false),
  )
  assert_eq(
    @jmespath.search("map(&a, @)", @json.parse("[{\"a\":1},{}]")),
    @json.parse("[1,null]"),
  )
  assert_eq(
    @jmespath.search("[*].a", @json.parse("[{\"a\":1},{}]")),
    @json.parse("[1]"),
  )
}

///|
test "deep expressions and evaluation budgets fail without panicking" {
  assert_eq(
    error_of("(".repeat(300) + "@" + ")".repeat(300), Json::null()).code,
    @jmespath.Syntax,
  )
  assert_eq(
    error_of("length(".repeat(300) + "@" + ")".repeat(300), Json::null()).code,
    @jmespath.Syntax,
  )
  // A long left-associated expression has shallow parsing but deep evaluation.
  assert_eq(
    error_of("@" + " || @".repeat(400), Json::null()).code,
    @jmespath.InvalidValue,
  )
  let expression = @jmespath.parse("[*].name")
  let input = @json.parse("[{\"name\":\"a\"},{\"name\":\"b\"}]")
  try {
    expression.evaluate(input, max_steps=2) |> ignore
    fail("expected budget exhaustion")
  } catch {
    @jmespath.JmespathError(diagnostic) =>
      assert_eq(diagnostic.code, @jmespath.InvalidValue)
    error => raise error
  }
  assert_eq(expression.evaluate(input), @json.parse("[\"a\",\"b\"]"))
}

///|
test "nested function callbacks use the evaluation stack" {
  let expression = @jmespath.parse(
    "map(&".repeat(100) + "@" + ", @)".repeat(100),
  )
  let mut input = Json::number(7)
  for _ in 0..<100 {
    input = Json::array([input])
  }
  let mut result = expression.evaluate(input)
  for _ in 0..<100 {
    guard result is Array(xs) && xs.length() == 1 else {
      fail("expected a singleton array")
    }
    result = xs[0]
  }
  assert_eq(result, Json::number(7))
}

///|
test "extreme indices and slice bounds do not overflow" {
  let input = @json.parse("[0,1,2]")
  for source in ["[99999999999999999999999]", "[-99999999999999999999999]"] {
    assert_eq(@jmespath.search(source, input), Json::null())
  }
  assert_eq(@jmespath.search("[::99999999999999]", input), @json.parse("[0]"))
  assert_eq(@jmespath.search("[::-99999999999999]", input), @json.parse("[2]"))
  assert_eq(@jmespath.search("[-99999999999999:99999999999999]", input), input)
}

///|
test "law: malformed combinations of grammar tokens never panic" {
  let tokens = [
    "a", "0", "-1", ".", "[", "]", "?", "{", "}", "(", ")", "&", "!", "*", "==",
    "||", "&&", "|", ",", ":", "@", "'", "\"", "`", "𝄞", "\\", "\n",
  ]
  @quickcheck.check(
    (indices : Array[Int32]) => {
      let source = indices
        .map(i => {
          tokens[(i.reinterpret_as_uint() %
          tokens.length().reinterpret_as_uint()).reinterpret_as_int()]
        })
        .join("")
      try {
        @jmespath.search(source, Json::null()) |> ignore
        true
      } catch {
        @jmespath.JmespathError(_) => true
      }
    },
    count=1000,
    max_size=80,
    seed=1582,
  )
}
