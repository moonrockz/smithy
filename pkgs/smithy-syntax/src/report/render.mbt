///|
/// The sink of a render: any core `Logger` (a `StringBuilder`, a
/// `@buffer.Buffer`, or the caller's own), plus the color switch.
priv struct Out {
  logger : &Logger
  color : Bool
  severity : @diagnostic.Severity
}

///|
fn Out::write(self : Out, s : String) -> Unit {
  self.logger.write_string(s)
}

///|
fn Out::code(self : Out, code : String) -> Unit {
  if self.color {
    self.logger.write_string("\u{1b}[\{code}m")
  }
}

///|
fn Out::header(self : Out) -> Unit {
  self.primary()
}

///|
fn Out::bold(self : Out) -> Unit {
  self.code("1")
}

///|
fn Out::border(self : Out) -> Unit {
  self.code("1;34")
}

///|
fn Out::primary(self : Out) -> Unit {
  self.code(if self.severity is Error { "1;91" } else { "1;93" })
}

///|
fn Out::secondary(self : Out) -> Unit {
  self.code("1;34")
}

///|
fn Out::reset(self : Out) -> Unit {
  self.code("0")
}

///|
let width : Int32 = 80

///|
/// Reflow `text` into lines of at most `max` columns, breaking at spaces.
/// A single word wider than `max` is hard-broken into `max`-sized chunks;
/// the chunk left over after that starts the next line's accumulation.
fn reflow(text : String, max : Int32) -> Array[String] {
  let lines : Array[String] = []
  let mut current = ""
  for word in text.split(" ") {
    let mut w = word.to_owned()
    while w.length() > max {
      if current.length() > 0 {
        lines.push(current)
        current = ""
      }
      lines.push(w.unsafe_substring(start=0, end=max))
      w = w.unsafe_substring(start=max, end=w.length())
    }
    if current.length() == 0 {
      current = w
    } else if current.length() + 1 + w.length() <= max {
      current = current + " " + w
    } else {
      lines.push(current)
      current = w
    }
  }
  if current.length() > 0 || lines.is_empty() {
    lines.push(current)
  }
  lines
}

///|
/// `source.position(span.start)`, except an empty span sitting at the very
/// end of a text that ends with a line break is anchored on the last line
/// that has content, one column past its last character, rather than on
/// the synthetic empty line after the final break.
fn anchor(source : @span.SourceText, span : @span.Span) -> @span.Position {
  let pos = source.position(span.start)
  guard span.is_empty() &&
    span.start == source.end() &&
    source.line_text(pos.line).unwrap_or("").length() == 0 else {
    return pos
  }
  let mut line = pos.line
  while line.0 > 1 && source.line_text(line).unwrap_or("").length() == 0 {
    line = @span.Line::new(line.0 - 1).unwrap_or(line)
  }
  let len = source.line_text(line).unwrap_or("").length()
  @span.Position::new(
    line,
    @span.Column::new(len + 1).unwrap_or(@span.Column::first()),
  )
}

///|
/// A label on one line of the excerpt.
priv struct LineLabel {
  line : @span.Line
  start_col : @span.Column
  end_col : @span.Column
  text : String
  primary : Bool
}

///|
fn label_for(
  source : @span.SourceText,
  span : @span.Span,
  text : String,
  primary : Bool,
) -> LineLabel {
  let start = anchor(source, span)
  let line_span = source
    .line_span(start.line)
    .unwrap_or(@span.Offset::zero().to(@span.Offset::zero()))
  let end_offset = if span.end() > line_span.end() {
    line_span.end()
  } else {
    span.end()
  }
  let end_col = @span.Column::new(end_offset.0 - line_span.start.0 + 1).unwrap_or(
    @span.Column::first(),
  )
  let end_col = if end_col <= start.column {
    start.column.next()
  } else {
    end_col
  }
  { line: start.line, start_col: start.column, end_col, text, primary, }
}

///|
/// `file:line:col: severity[code]: message`.
pub fn render_short(
  d : @diagnostic.Diagnostic,
  source : @span.SourceText,
) -> String {
  let p = anchor(source, d.span)
  let sev = if d.severity is Error { "error" } else { "warning" }
  "\{source.name().unwrap_or("<input>")}:\{p.line.0}:\{p.column.0}: \{sev}[\{d.code}]: \{d.message}"
}

///|
/// The Rust and codespan layout: header, location, excerpt with labels,
/// notes, hint and example, written into `logger`. The gutter is as wide
/// as the largest line number shown; numbered lines are `N | text` and
/// every other excerpt line is `<gutter> | ...`, so a label's first
/// caret sits exactly under its column.
pub fn render_terminal_to(
  d : @diagnostic.Diagnostic,
  source : @span.SourceText,
  logger : &Logger,
  color~ : Bool = true,
) -> Unit {
  let out = { logger, color, severity: d.severity, }
  let sev = if d.severity is Error { "error" } else { "warning" }
  out.header()
  out.write("\{sev}[\{d.code}]")
  out.reset()
  out.bold()
  out.write(
    (
      $|: \{d.title}
      $|
    ),
  )
  out.reset()
  let labels = [label_for(source, d.span, d.message, true)]
  for l in d.labels {
    labels.push(label_for(source, l.span, l.text, false))
  }
  let indexed = labels.mapi((i, l) => (i, l))
  indexed.sort_by((a, b) => {
    let order = a.1.line.compare(b.1.line)
    if order == 0 {
      a.0.compare(b.0)
    } else {
      order
    }
  })
  let labels = indexed.map(e => e.1)
  let max_line = labels
    .iter()
    .map(l => l.line.0)
    .fold(init=1, (a, b) => if a > b { a } else { b })
  let gutter = max_line.to_string().length()
  let pad = " ".repeat(gutter)
  let p = anchor(source, d.span)
  out.border()
  out.write("\{pad}--> ")
  out.reset()
  out.write("\{source.name().unwrap_or("<input>")}:\{p.line.0}:\{p.column.0}\n")
  out.border()
  out.write(
    (
      $|\{pad} |
      $|
    ),
  )
  out.reset()
  let mut last_line : @span.Line? = None
  for l in labels {
    if last_line != Some(l.line) {
      if last_line is Some(prev) && l.line.0 > prev.0 + 1 {
        out.border()
        out.write(
          (
            $|\{pad} ...
            $|
          ),
        )
        out.reset()
      }
      let number = l.line.0.to_string()
      let num_pad = " ".repeat(gutter - number.length())
      out.border()
      out.write("\{num_pad}\{number} | ")
      out.reset()
      out.write(
        source.line_text(l.line).unwrap_or("").replace_all(old="\r", new=" "),
      )
      out.write(
        (
          #|
          #|
        ),
      )
      last_line = Some(l.line)
    }
    out.border()
    out.write("\{pad} | ")
    out.reset()
    out.write(" ".repeat(l.start_col.0 - 1))
    if l.primary {
      out.primary()
    } else {
      out.secondary()
    }
    out.write(
      (if l.primary { "^" } else { "-" }).repeat(l.end_col.0 - l.start_col.0),
    )
    out.write(" \{l.text}")
    out.reset()
    out.write(
      (
        #|
        #|
      ),
    )
  }
  out.border()
  out.write(
    (
      $|\{pad} |
      $|
    ),
  )
  out.reset()
  let body_width = width - gutter - 3
  for note in d.notes {
    for i, line in reflow(note, body_width) {
      out.border()
      out.write(if i == 0 { "\{pad} = " } else { "\{pad}   " })
      out.reset()
      out.write(
        (
          $|\{line}
          $|
        ),
      )
    }
  }
  match d.hint {
    Some(h) =>
      for i, line in reflow(h, body_width - 6) {
        out.border()
        out.write(if i == 0 { "\{pad} = " } else { "\{pad}   " })
        out.reset()
        if i == 0 {
          out.bold()
          out.write("hint: ")
          out.reset()
        } else {
          out.write("      ")
        }
        out.write(
          (
            $|\{line}
            $|
          ),
        )
      }
    None => ()
  }
  match d.example {
    Some(ex) => {
      out.border()
      out.write("\{pad} = ")
      out.reset()
      out.bold()
      out.write(
        (
          #|example:
          #|
        ),
      )
      out.reset()
      for
        line in ex.split(
          (
            #|
            #|
          ),
        ) {
        out.write(
          (
            $|\{pad}     \{line}
            $|
          ),
        )
      }
    }
    None => ()
  }
}

///|
/// `render_terminal_to` into a fresh string.
pub fn render_terminal(
  d : @diagnostic.Diagnostic,
  source : @span.SourceText,
  color~ : Bool = true,
) -> String {
  let sb = StringBuilder()
  render_terminal_to(d, source, sb, color~)
  sb.to_string()
}

///|
/// `render_terminal` without colors.
pub fn render_plain(
  d : @diagnostic.Diagnostic,
  source : @span.SourceText,
) -> String {
  render_terminal(d, source, color=false)
}

///|
/// Every diagnostic, a blank line between them, then a summary line,
/// written into `logger`.
pub fn render_all_to(
  ds : ArrayView[@diagnostic.Diagnostic],
  source : @span.SourceText,
  logger : &Logger,
  color~ : Bool = true,
) -> Unit {
  let mut errors = 0
  let mut warnings = 0
  for d in ds {
    render_terminal_to(d, source, logger, color~)
    logger.write_string(
      (
        #|
        #|
      ),
    )
    if d.is_error() {
      errors += 1
    } else {
      warnings += 1
    }
  }
  let plural = (n : Int32, word : String) => {
    if n == 1 {
      "1 \{word}"
    } else {
      "\{n} \{word}s"
    }
  }
  logger.write_string(
    "\{plural(errors, "error")}, \{plural(warnings, "warning")}\n",
  )
}

///|
/// `render_all_to` into a fresh string.
pub fn render_all(
  ds : ArrayView[@diagnostic.Diagnostic],
  source : @span.SourceText,
  color~ : Bool = true,
) -> String {
  let sb = StringBuilder()
  render_all_to(ds, source, sb, color~)
  sb.to_string()
}
