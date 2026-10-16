# report

Renders a `Diagnostic` with its source excerpt: `render_terminal` (ANSI
colors), `render_plain` (no colors), `render_short` (one line) and
`render_all` (a list with a summary).

```mbt check
///|
test {
  let source = @span.SourceText::new("namespace a use b#C\n", name="m.smithy")
  let r = @parser.parse(source)
  inspect(
    @report.render_short(r.diagnostics[0], source).has_prefix(
      "m.smithy:1:13: error[SM-PARSE-003]",
    ),
    content="true",
  )
}
```
