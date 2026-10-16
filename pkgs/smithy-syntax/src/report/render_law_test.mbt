///|
test "law: every caret sits under its column and the render never panics" {
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
        // The location line is `<gutter>--> file:line:col`, so the gutter
        // width is where `-->` starts.
        let gutter = lines[1].find("--> ").unwrap_or(0)
        let caret_prefix = " ".repeat(gutter) + " | "
        let mut current_line = 0
        let mut current_text = ""
        let mut primary_seen = false
        for line in lines {
          // A numbered source line: `N | text`, `N` right-aligned.
          if line.length() >= gutter + 3 &&
            line.unsafe_substring(start=gutter, end=gutter + 3) == " | " {
            let number = line
              .unsafe_substring(start=0, end=gutter)
              .trim(chars=" ")
            if number.length() > 0 &&
              number.iter().all(c => c >= '0' && c <= '9') {
              current_line = number
                .iter()
                .fold(init=0, (n, c) => n * 10 + (c.to_int() - '0'.to_int()))
              current_text = line.unsafe_substring(
                start=gutter + 3,
                end=line.length(),
              )
              continue
            }
          }
          // A caret line: `<gutter> | <spaces><marks> <text>`.
          guard line.has_prefix(caret_prefix) else { continue }
          let rest = line.unsafe_substring(
            start=caret_prefix.length(),
            end=line.length(),
          )
          let marks = rest.trim_start(chars=" ")
          let spaces = rest.length() - marks.length()
          guard marks.has_prefix("^") || marks.has_prefix("-") else { continue }
          // Every label fits its source line: at most past its end and a
          // hidden `\r` (a span on the `\n` of a CRLF, or after a final CR).
          ok = ok && spaces <= current_text.length() + 1
          guard marks.has_prefix("^") && !primary_seen else { continue }
          primary_seen = true
          // The primary caret starts exactly at the span's column. An
          // empty span at the end of a text that ends with a line break is
          // anchored one past the last line with content instead.
          let pos = source.position(d.span.start)
          let anchored = d.span.is_empty() &&
            d.span.start == source.end() &&
            source.line_text(pos.line).unwrap_or("").length() == 0
          if anchored {
            ok = ok && spaces + 1 == current_text.length() + 1
          } else {
            ok = ok && current_line == pos.line.0 && spaces + 1 == pos.column.0
          }
        }
        ok = ok && primary_seen
      }
      ok
    },
    count=200,
    max_size=12,
    seed=4031,
  )
}
