///|
fn first_error(
  text : String,
) -> (@diagnostic.Diagnostic, @span.SourceText) raise {
  let source = @span.SourceText::new(text, name="model.smithy")
  let r = @parser.parse(source)
  guard r.diagnostics.length() > 0 else { fail("no diagnostics") }
  (r.diagnostics[0], source)
}

///|
test "render_short is one line" {
  let (d, source) = first_error(
    (
      #|namespace a use b#C
      #|
    ),
  )
  inspect(
    @report.render_short(d, source),
    content="model.smithy:1:13: error[SM-PARSE-003]: I was expecting a line break here but found `use`",
  )
}

///|
test "render_plain shows the excerpt, labels, notes and hint" {
  let (d, source) = first_error(
    (
      #|$version: "2"
      #|namespace com.foo
      #|
      #|structure S {
      #|    a String
      #|}
      #|
    ),
  )
  inspect(
    @report.render_plain(d, source),
    content=(
      #|error[SM-PARSE-001]: UNEXPECTED TOKEN
      #| --> model.smithy:5:7
      #|  |
      #|4 | structure S {
      #|  | --------- the structure `S` started here
      #|5 |     a String
      #|  |       ^^^^^^ I was expecting `:` after the member name `a` but found `String`
      #|  |
      #|  = I was parsing the structure `S` when I got stuck.
      #|  = example:
      #|      a: String
      #|
    ),
  )
}

///|
test "a warning renders with the warning header" {
  let (d, source) = first_error(
    (
      #|namespace a
      #|/// lost
      #|
    ),
  )
  let out = @report.render_plain(d, source)
  inspect(
    out.has_prefix(
      (
        #|warning[SM-PARSE-009]: DETACHED DOC COMMENT
        #|
      ),
    ),
    content="true",
  )
  inspect(out.contains("= hint: Move it right before"), content="true")
}

///|
test "render_terminal adds colors and render_plain does not" {
  let (d, source) = first_error(
    (
      #|namespace a use b#C
      #|
    ),
  )
  inspect(
    @report.render_terminal(d, source).contains("\u{1b}["),
    content="true",
  )
  inspect(
    @report.render_terminal(d, source, color=false) ==
    @report.render_plain(d, source),
    content="true",
  )
  inspect(@report.render_plain(d, source).contains("\u{1b}["), content="false")
}

///|
test "a span at the end of the file renders a caret after the last character" {
  let (d, source) = first_error(
    (
      #|namespace a
      #|string
      #|
    ),
  )
  let out = @report.render_plain(d, source)
  inspect(
    out.contains(
      (
        #|2 | string
        #|  |       ^ 
      ),
    ),
    content="true",
  )
}

///|
test "a two-digit line number widens the gutter and right-aligns the numbers" {
  let (d, source) = first_error(
    (
      #|$version: "2"
      #|namespace com.foo
      #|
      #|
      #|
      #|
      #|
      #|
      #|structure S {
      #|    a String
      #|}
      #|
    ),
  )
  inspect(
    @report.render_plain(d, source),
    content=(
      #|error[SM-PARSE-001]: UNEXPECTED TOKEN
      #|  --> model.smithy:10:7
      #|   |
      #| 9 | structure S {
      #|   | --------- the structure `S` started here
      #|10 |     a String
      #|   |       ^^^^^^ I was expecting `:` after the member name `a` but found `String`
      #|   |
      #|   = I was parsing the structure `S` when I got stuck.
      #|   = example:
      #|       a: String
      #|
    ),
  )
}

///|
test "a primary and a secondary label on the same line each sit under their columns" {
  let source = @span.SourceText::new("structure Foo String\n", name="m.smithy")
  let at = (start : Int32, len : Int32) => {
    @span.Span::new(
      @span.Offset::new(start).unwrap(),
      @span.Length::new(len).unwrap(),
    )
  }
  let d = @diagnostic.Diagnostic::new(
    code="SM-TEST-000",
    severity=Error,
    title="TEST",
    message="the primary label",
    span=at(14, 6),
    labels=[{ span: at(10, 3), text: "the secondary label", }],
  )
  inspect(
    @report.render_plain(d, source),
    content=(
      #|error[SM-TEST-000]: TEST
      #| --> m.smithy:1:15
      #|  |
      #|1 | structure Foo String
      #|  |               ^^^^^^ the primary label
      #|  |           --- the secondary label
      #|  |
      #|
    ),
  )
}

///|
// `@buffer.Buffer` is a `&Logger`, but its impl is deprecated (UTF-16LE
// bytes); this test proves `render_terminal_to` still accepts it.
#warnings("-deprecated")
test "render_terminal_to writes into any Logger" {
  let (d, source) = first_error(
    (
      #|namespace a use b#C
      #|
    ),
  )
  let sb = StringBuilder()
  @report.render_terminal_to(d, source, sb, color=false)
  let buf = @buffer.Buffer()
  @report.render_terminal_to(d, source, buf, color=false)
  inspect(sb.to_string() == @report.render_plain(d, source), content="true")
  inspect(buf.to_string() == @report.render_plain(d, source), content="true")
}

///|
test "render_all ends with a summary" {
  let source = @span.SourceText::new(
    (
      #|namespace a
      #|use Foo
      #|/// x
      #|
    ),
    name="m.smithy",
  )
  let r = @parser.parse(source)
  let out = @report.render_all(r.diagnostics, source, color=false)
  inspect(
    out.has_suffix(
      (
        #|1 error, 1 warning
        #|
      ),
    ),
    content="true",
  )
}

///|
test "long notes reflow at 80 columns" {
  let source = @span.SourceText::new(
    (
      #|namespace a
      #|metadata x = "y"
      #|
    ),
    name="m.smithy",
  )
  let r = @parser.parse(source)
  let out = @report.render_plain(r.diagnostics[0], source)
  inspect(
    out,
    content=(
      #|error[SM-PARSE-004]: EXPECTED A STATEMENT
      #| --> m.smithy:2:1
      #|  |
      #|2 | metadata x = "y"
      #|  | ^^^^^^^^ I was expecting `use`, a shape statement, or `apply` but found `metadata`
      #|  |
      #|  = Control statements (`$...`) come first, then `metadata`, then `namespace`.
      #|
    ),
  )
  for
    line in out.split(
      (
        #|
        #|
      ),
    ) {
    // Caret/label lines carry an unwrapped message after the underline;
    // only notes and hints are reflowed at 80 columns.
    guard !(line.contains("^") || line.contains("---")) else { continue }
    @expect.expect(line.length() <= 80).because(line.to_owned()).to_be_true()
  }
}

///|
test "reflow hard-breaks a word wider than 80 columns" {
  let source = @span.SourceText::new("namespace a\n", name="m.smithy")
  let long = "x".repeat(120)
  let d = @diagnostic.Diagnostic::new(
    code="SM-TEST-000",
    severity=Error,
    title="TEST",
    message="test",
    span=@span.Offset::zero().to(@span.Offset::zero()),
    notes=[long],
  )
  let out = @report.render_plain(d, source)
  for
    line in out.split(
      (
        #|
        #|
      ),
    ) {
    // Only the note lines (no "|") carry the 120-char unbroken token.
    guard !line.contains("|") && line.length() > 0 else { continue }
    @expect.expect(line.length() <= 80).because(line.to_owned()).to_be_true()
  }
}

///|
test "lone carriage returns render as spaces without shifting columns" {
  let (d, source) = first_error("namespace a\nstructure S { a\r String }")
  let out = @report.render_plain(d, source)
  assert_false(out.contains("\r"))
  assert_true(out.contains("structure S { a  String }"))
  assert_true(out.contains("                ^^^^^^"))
  assert_eq(
    source.line_text(@span.Line::new(2).unwrap()),
    Some("structure S { a\r String }"),
  )
  assert_eq(
    @span.SourceText::new("a\r").line_text(@span.Line::first()),
    Some("a\r"),
  )
}

///|
test "labels on the same line retain primary then caller order" {
  let source = @span.SourceText::new("x")
  let span = @span.Offset::zero().to(source.end())
  let labels = Array::makei(64, i => @diagnostic.Label::{
    span,
    text: "label-\{i}",
  })
  let d = @diagnostic.Diagnostic::new(
    code="SM-PARSE-001",
    severity=Error,
    title="ORDER",
    message="primary",
    span~,
    labels~,
  )
  let out = @report.render_plain(d, source)
  let mut last = out.find("^ primary").unwrap()
  for i in 0..<64 {
    let at = out.find("- label-\{i}\n").unwrap()
    assert_true(at > last)
    last = at
  }
}

///|
test "hint wrapping uses the available 80 columns" {
  let source = @span.SourceText::new("x")
  let span = @span.Offset::zero().to(source.end())
  let d = @diagnostic.Diagnostic::new(
    code="SM-PARSE-001",
    severity=Error,
    title="WRAP",
    message="primary",
    span~,
    hint="a ".repeat(100),
  )
  let out = @report.render_plain(d, source)
  for line in out.split("\n") {
    assert_true(line.length() <= 80)
  }
  assert_true(out.split("\n").any(line => line.length() >= 78))
}
