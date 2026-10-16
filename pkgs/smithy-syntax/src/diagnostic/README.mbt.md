# diagnostic

A `Diagnostic` is a code (`SM-SCAN-nnn`, `SM-PARSE-nnn`), a severity, a
title, a message under its primary span, secondary labels, notes, and an
optional hint and example. It is a value: `with_context` returns a copy.
`codes()` lists every code.

```mbt check
///|
test {
  debug_inspect(
    @diagnostic.description("SM-PARSE-003"),
    content="Some(\"Missing line break between statements\")",
  )
}
```
