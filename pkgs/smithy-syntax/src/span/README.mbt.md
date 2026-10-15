# span

Typed positions: `Offset` (a UTF-16 unit index), `Length`, `Line` and
`Column` are never negative or zero where that makes no sense, because
their constructors are the only way in. A `Span` is a start and a length.
`SourceText` maps offsets to positions and lines.

```mbt check
///|
test {
  let st = @span.SourceText::new("string Foo\nstring Bar\n", name="a.smithy")
  let at = @span.Offset::new(11).unwrap()
  debug_inspect(st.position(at), content="{ line: Line(2), column: Column(1) }")
  debug_inspect(
    st.line_text(@span.Line::first().next()),
    content="Some(\"string Bar\")",
  )
}
```
