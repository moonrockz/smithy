///|
test "invalid command options fail with usage status" {
  for
    args in [
      ["wat"],
      ["convert", "a.smithy"],
      ["convert", "--to", "xml", "a.smithy"],
      ["format", "--check", "--write", "a.smithy"],
      ["format", "a.smithy", "b.smithy"],
      ["ast", "--check", "a.smithy"],
      ["ast", "--output"],
      ["ast"],
      ["ast", "--from=xml", "a.smithy"],
      ["ast", "-"],
      ["ast", "--from=idl", "-", "-"],
      ["format", "--check", "-o", "output", "a.smithy"],
      ["format", "-o", "output", "--write", "a.smithy"],
      ["convert", "--to=idl", "--output-dir=out", "-ooutput", "a.smithy"],
      ["convert", "--to", "json", "--output-dir", "out", "a.smithy"],
      ["validate", "-o", "output", "a.smithy"],
      ["format", "--write", "--from", "idl", "-"],
    ] {
    let code = try options(args) catch {
      CliError(_, code) => code
    } noraise {
      _ => 0
    }
    assert_eq(code, 2, msg=args.join(" "))
  }
  let opts = options(["ast", "--", "-h.smithy"])
  assert_eq(opts.files, ["-h.smithy"])
  assert_eq(input_format("model.json", None), "json")
  assert_eq(input_format("model", Some("idl")), "idl")
}

///|
test "argparse accepts standard option forms and interspersed inputs" {
  let opts = options([
    "convert", "one.smithy", "--from=idl", "--to=json", "-omodel.json", "two.smithy",
  ])
  assert_eq(opts.files, ["one.smithy", "two.smithy"])
  assert_eq(opts.from, Some("idl"))
  assert_eq(opts.to, Some("json"))
  assert_eq(opts.output, Some("model.json"))
  assert_eq(options(["ast", "--from=json", "-"]).files, ["-"])
}

///|
test "IDL formatting is idempotent and preserves literals and comments" {
  let text =
    #|$version :  "2"
    #|// model comment
    #|namespace example
    #|/// Shape docs
    #|structure  Example   {
    #|/// Member docs
    #|@default(9007199254740993)
    #|value : Long, // trailing comment
    #|@documentation("""
    #|    A text block.
    #|      Keep indentation.
    #|    """)
    #|@length(
    #|min : 0
    #|)
    #|name: String
    #|}
  let formatted = format_text(text, "input.smithy", "idl")
  assert_eq(format_text(formatted, "input.smithy", "idl"), formatted)
  let before = @syntax.parse_idl(text)
  let after = @syntax.parse_idl(formatted)
  assert_false(after.has_errors())
  assert_eq(
    before.cst.tokens.map(t => (t.kind, t.lexeme)),
    after.cst.tokens.map(t => (t.kind, t.lexeme)),
  )
  fn comments(parsed : @syntax.ParseResult) -> Array[String] {
    let out = []
    for token in parsed.cst.tokens {
      for t in token.trivia_before {
        if t.is_comment() {
          out.push(t.text())
        }
      }
      for t in token.trivia_after {
        if t.is_comment() {
          out.push(t.text())
        }
      }
    }
    out
  }
  assert_eq(comments(before), comments(after))
  assert_true(formatted.contains("    value: Long, // trailing comment\n"))
  assert_true(formatted.contains("    /// Member docs\n"))
  assert_true(formatted.contains("        min: 0\n    )\n"))
}

///|
test "format rejects invalid syntax and preserves exact JSON numbers" {
  let code = try format_text("structure {", "broken.smithy", "idl") catch {
    CliError(_, code) => code
  } noraise {
    _ => 0
  }
  assert_eq(code, 1)
  let text = "{\"smithy\":\"2\",\"metadata\":{\"big\":9007199254740993}}"
  let formatted = format_text(text, "input.json", "json")
  assert_true(formatted.contains("9007199254740993"))
  assert_eq(format_text(formatted, "input.json", "json"), formatted)
  assert_eq(format_text("", "empty.smithy", "idl"), "")
  assert_eq(
    format_text("// only a comment", "comments.smithy", "idl"),
    "// only a comment\n",
  )
}
