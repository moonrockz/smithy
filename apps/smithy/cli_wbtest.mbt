///|
test "RPC options belong to the nested command scope" {
  let opts = options([
    "validate", "rpc", "--version", "2.0", "--service", "example#Api", "--message",
    "message.json", "model.smithy",
  ])
  assert_eq(opts.rpc_version, Some(@rpc.V2_0))
  let code = try
    options([
      "validate", "--from", "json", "rpc", "--version", "2.0", "--service", "example#Api",
      "--message", "message.json", "model.smithy",
    ])
  catch {
    CliError(_, code) => code
  } noraise {
    _ => 0
  }
  assert_eq(code, 2)
}

///|
test "invalid command options fail with usage status" {
  for
    args in [
      ["wat"],
      ["validate-value"],
      ["validate-rpc"],
      ["diff"],
      ["diff", "--old", "a.smithy"],
      ["diff", "--new", "b.smithy"],
      ["diff", "--old", "a.smithy", "--new", "b.smithy", "extra.smithy"],
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
      ["select", "a.smithy"],
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
test "value validation options select typed policies and permit stdin once" {
  let opts = options([
    "validate", "value", "--shape", "example#Input", "--value", "-", "--unknown-members",
    "ignore", "--member-names", "json", "--diagnostics", "json", "model.smithy",
  ])
  assert_eq(opts.command, "validate")
  assert_eq(opts.rpc_version, None)
  assert_eq(opts.value_validation.unwrap().target.to_string(), "example#Input")
  let stdin_model = options([
    "validate", "value", "--shape", "example#Input", "--value", "x.json", "--from",
    "json", "-",
  ])
  assert_eq(stdin_model.from, Some("json"))
  assert_eq(stdin_model.files, ["-"])
  for
    args in [
      [
        "validate", "--from", "json", "value", "--shape", "example#Input", "--value",
        "x.json", "m.smithy",
      ],
      [
        "validate", "before.smithy", "value", "--shape", "example#Input", "--value",
        "x.json", "m.smithy",
      ],
      ["validate", "value", "--shape", "bad", "--value", "x.json", "m.smithy"],
      [
        "validate", "value", "--shape", "example#Input", "--value", "-", "--from",
        "idl", "-",
      ],
      [
        "validate", "value", "--shape", "example#Input", "--value", "x.json", "--diagnostics",
        "xml", "m.smithy",
      ],
      [
        "validate", "value", "--shape", "example#Input", "--value", "x.json", "--unknown-members",
        "guess", "m.smithy",
      ],
    ] {
    let code = try options(args) catch {
      CliError(_, code) => code
    } noraise {
      _ => 0
    }
    assert_eq(code, 2)
  }
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

///|
test "response CLI contexts and input scopes reject contradictory usage" {
  let base = ["validate", "rpc", "--version", "2.0", "--service", "example#Api"]
  for
    tail in [
      ["--response", "r.json", "m.smithy", "--message", "q.json"],
      ["m.smithy"],
      ["--message", "q.json", "--method", "op", "m.smithy"],
      ["--response", "r.json", "--method", "op", "--envelope-only", "m.smithy"],
      ["--response", "r.json", "--operation", "bad", "m.smithy"],
      ["--response", "r.json", "--operation", "example#Op$x", "m.smithy"],
      ["--response", "r.json", "--method", "rpc.internal", "m.smithy"],
      [
        "--response", "r.json", "--request", "q.json", "--method", "op", "m.smithy",
      ],
      ["--response", "r.json", "--legacy-errors", "opaque", "m.smithy"],
      ["--response", "-", "--request", "-", "m.smithy"],
      ["--response", "r.json", "--request", "-", "--from", "idl", "-"],
      ["--response", "-", "--method", "op", "--from", "idl", "-"],
    ] {
    let code = try options(base + tail) catch {
      CliError(_, code) => code
    } noraise {
      _ => 0
    }
    assert_eq(code, 2, msg=tail.join(" "))
  }
  let opts = options(
    base + ["--response", "r.json", "--operation", "example#Op", "m.smithy"],
  )
  assert_eq(
    opts.rpc_options.unwrap().context,
    Some(@rpc.Operation(@smithy.ShapeId::parse("example#Op").unwrap())),
  )
  assert_true(opts.rpc_options.unwrap().response)
  assert_eq(
    options(base + ["--response", "r.json", "m.smithy"]).rpc_options.unwrap().context,
    None,
  )
}

///|
test "batch CLI selects request response and absent-response modes" {
  let base = [
    "validate", "rpc", "--version", "2.0", "--service", "example#Api", "--batch",
  ]
  let request = options(base + ["--message", "q.json", "m.smithy"])
  assert_true(request.rpc_options.unwrap().batch)
  assert_false(request.rpc_options.unwrap().response)
  let absent = options(
    base + ["--no-response", "--request", "q.json", "m.smithy"],
  )
  assert_true(absent.rpc_options.unwrap().response)
  assert_true(absent.rpc_options.unwrap().no_response)
  for
    tail in [
      ["--no-response", "m.smithy"],
      [
        "--no-response", "--request", "q.json", "--response", "r.json", "m.smithy",
      ],
      [
        "--no-response", "--request", "q.json", "--message", "r.json", "m.smithy",
      ],
      ["--no-response", "--request", "-", "--from", "idl", "-"],
    ] {
    let code = try options(base + tail) catch {
      CliError(_, code) => code
    } noraise {
      _ => 0
    }
    assert_eq(code, 2, msg=tail.join(" "))
  }
  let code = try
    options([
      "validate", "rpc", "--version", "2.0", "--service", "example#Api", "--no-response",
      "--request", "q.json", "m.smithy",
    ])
  catch {
    CliError(_, code) => code
  } noraise {
    _ => 0
  }
  assert_eq(code, 2)
}
