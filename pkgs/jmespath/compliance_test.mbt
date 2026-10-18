///|
test "official JMESPath compliance corpus" {
  let failures : Array[String] = []
  let grammar_overrides : Set[String] = Set([])
  let mut count = 0
  for (file, text) in compliance_corpus() {
    guard @json.parse(text) is Array(suites) else {
      fail("invalid suite " + file)
    }
    for suite in suites {
      guard suite is { "given": given, "cases": Array(cases), .. } else {
        fail("invalid suite " + file)
      }
      for case_ in cases {
        guard case_ is { "expression": String(expression), .. } else {
          fail("invalid case " + file)
        }
        // Benchmarks have no correctness oracle and are not compliance cases.
        if case_ is { "bench": _, .. } {
          continue
        }
        // These two upstream fixtures accept raw newlines, contradicting the
        // raw-string ABNF's U+0020 lower bound. Exercise them as syntax errors
        // without modifying the vendored data. See README.mbt.md, Conformance.
        let case_ = if file == "literal.json" &&
          (
            (
              expression == "'newline\n'" &&
              case_ is { "result": String("newline\n"), .. }
            ) ||
            (expression == "'\n'" && case_ is { "result": String("\n"), .. })
          ) {
          grammar_overrides.add(expression)
          Json::object({
            "expression": Json::string(expression),
            "error": "syntax",
          })
        } else {
          case_
        }
        count += 1
        try {
          let actual = @jmespath.search(expression, given)
          match case_ {
            { "result": expected, .. } =>
              if actual != expected {
                failures.push(
                  "\{file}: \{expression}: expected \{expected.stringify()}, found \{actual.stringify()}",
                )
              }
            { "error": String(error), .. } =>
              failures.push(
                "\{file}: \{expression}: expected \{error}, found \{actual.stringify()}",
              )
            _ => fail("missing oracle " + file)
          }
        } catch {
          @jmespath.JmespathError(diagnostic) =>
            match case_ {
              { "error": String(expected), .. } if expected ==
                diagnostic.code.to_string() => ()
              _ =>
                failures.push(
                  "\{file}: \{expression}: unexpected \{diagnostic.code.to_string()}: \{diagnostic.message}",
                )
            }
          error => failures.push("\{file}: \{expression}: unexpected \{error}")
        }
      }
    }
  }
  assert_true(count > 800)
  assert_eq(grammar_overrides.length(), 2)
  if !failures.is_empty() {
    fail(
      "\{failures.length()} of \{count} compliance cases failed:\n" +
      failures.join("\n"),
    )
  }
}

///|
test "law: arbitrary expression text never panics" {
  @quickcheck.check(
    (source : String) => {
      try {
        @jmespath.search(source, Json::null()) |> ignore
        true
      } catch {
        @jmespath.JmespathError(_) => true
      }
    },
    count=1000,
    max_size=80,
    seed=5124,
  )
}
