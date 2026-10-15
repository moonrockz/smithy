///|
test "law: every caret line fits its source line and the render never panics" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let source = @span.SourceText::new(t.text(), name="x.smithy")
      let r = @parser.parse(source)
      let mut ok = true
      for d in r.diagnostics {
        let out = @report.render_plain(d, source)
        ok = ok && out.length() > 0 && !out.contains("\u{1b}[")
        let lines : Array[String] = out
          .split(
            (
              #|
              #|
            ),
          )
          .map(x => x.to_owned())
          .collect()
        for i, line in lines {
          // A caret line follows a numbered source line.
          guard line.contains("| ") &&
            (line.contains("^") || line.contains("-")) &&
            i > 0 else {
            continue
          }
          let prev = lines[i - 1]
          guard prev.contains(" | ") && !prev.contains("  | ") else { continue }
          let bar = prev.find(" | ").unwrap_or(0)
          let src_len = prev.length() - (bar + 3)
          let cbar = line.find("| ").unwrap_or(0)
          let caret_start = line.length() -
            line
            .unsafe_substring(start=cbar + 2, end=line.length())
            .trim_start(chars=" ")
            .length() -
            (cbar + 2)
          ok = ok && caret_start <= src_len + 1
        }
      }
      ok
    },
    count=200,
    max_size=12,
    seed=4031,
  )
}
