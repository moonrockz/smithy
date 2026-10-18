# moonrockz/jmespath

A standalone JMESPath parser and JSON evaluator for MoonBit. The module uses
only the core library and runs on Wasm, Wasm GC, JavaScript and native targets.
It has no dependency on Smithy.

## Query JSON

```mbt check
///|
test {
  let input = @json.parse(
    (
      #|{"items":[{"name":"Zoe","active":true},{"name":"Ada","active":true},{"name":"Bob","active":false}]}
    ),
  )
  let result = @jmespath.search("items[?active].name | sort(@)", input)
  assert_eq(result, @json.parse("[\"Ada\",\"Zoe\"]"))
}
```

Install with `moon add moonrockz/jmespath` and import the module in `moon.pkg`.
`search(source, input)` parses and evaluates once. Parse an expression separately
to reuse it with different inputs:

```mbt check
///|
test {
  let expression = @jmespath.parse("length(@)")
  assert_eq(expression.evaluate(@json.parse("[1,2,3]")), Json::number(3))
  assert_eq(expression.evaluate(Json::string("hello")), Json::number(5))
}
```

Neither parsing nor evaluation changes caller-owned JSON. Function arguments
evaluate eagerly; logical `&&` and `||` short-circuit. Projections omit null
results; `map` retains them. Strings use Unicode code points for length, reverse
and ordering. Object iteration order is unspecified, as in JMESPath.

## Inspect expressions and errors

`Expression` retains the original `source` and an inspectable `root: Node`.
Each node has a `kind: NodeKind` and a half-open UTF-16 `Span`. Node kinds keep
projection inputs, predicates, function arguments and expression references
separate so downstream tools can analyze them without reparsing source text.

`parse`, `search` and `Expression::evaluate` raise `JmespathError(Diagnostic)`.
Diagnostics contain an `ErrorCode`, a message and a source span.
`ErrorCode::to_string()` returns the standard names `syntax`, `invalid-type`,
`invalid-value`, `invalid-arity` and `unknown-function`.
`Diagnostic::line_column(source)` returns one-based line and UTF-16 column.

```mbt check
///|
test {
  let source = "items["
  try {
    @jmespath.parse(source) |> ignore
    fail("expected an incomplete expression")
  } catch {
    @jmespath.JmespathError(diagnostic) => {
      assert_eq(diagnostic.code, @jmespath.Syntax)
      assert_eq(diagnostic.line_column(source), (1, 7))
    }
    error => raise error
  }
}
```

Parsing allows up to 256 nested expression calls. Evaluation uses its own stack
and allows up to 256 nested AST levels, including function callbacks. It also
limits expression visits to 1,000,000 by default; `max_steps` overrides that limit
on `search` or `evaluate`. Exceeding an evaluation limit raises `invalid-value`.
Exceeding the parser nesting limit raises `syntax`. JSON literals must be valid
JSON; use single quotes for raw string literals.
Raw strings reject U+0000 through U+001F, including controls after a backslash.
Textual escapes such as `\n` remain literal backslash-plus-letter sequences.

## Conformance

The module implements the [JMESPath specification](https://jmespath.org/specification.html)
and its standard functions. Tests run the vendored
[official compliance suite](https://github.com/jmespath/jmespath.test) on every
supported target. Benchmark-only cases are excluded from correctness checks.
Two `literal.json` cases, `'newline\n'` and `'\n'` with actual newline characters,
contradict the specification's raw-string ABNF. The runner explicitly expects
`syntax` for those cases and checks that exactly two overrides are applied.
All 892 cases still run; the other 890 retain their upstream expectations.
The vendored JSON and generated embedded corpus remain unchanged.
`COMPLIANCE_SHA` records the revision; `mise run jmespath:vendor -- <git-ref>`
refreshes the JSON corpus and its embedded test data for offline test runs.

Smithy contract analysis will consume this public module in a separate change.
