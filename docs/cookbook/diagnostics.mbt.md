# Report problems

Each diagnostic has a code, a title, a message under its span, labels,
notes and a hint. Render them for a terminal, for a log, or as one line
for an editor.

```mbt check
///|
test "render for a terminal and for an editor" {
  let source = @syntax.SourceText::new(
    (
      #|namespace a
      #|structure S {
      #|    a String
      #|}
      #|
    ),
    name="s.smithy",
  )
  let r = @syntax.parse(source)
  let d = r.diagnostics[0]
  inspect(d.code, content="SM-PARSE-001")
  inspect(d.title, content="UNEXPECTED TOKEN")
  inspect(
    @syntax.render_short(d, source),
    content="s.smithy:3:7: error[SM-PARSE-001]: I was expecting `:` after the member name `a` but found `String`",
  )
  let plain = @syntax.render_plain(d, source)
  inspect(plain.contains("the structure `S` started here"), content="true")
  inspect(
    @syntax.render_all(r.diagnostics, source, color=false).has_suffix(
      "1 error, 0 warnings\n",
    ),
    content="true",
  )
}
```
