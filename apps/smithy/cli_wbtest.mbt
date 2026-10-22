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
test "Ion value inputs require explicit format and datagram selection" {
  let args = [
    "validate", "value", "--shape", "example#Input", "--value", "values.ion", "--input-format",
    "ion-text", "--ion-index", "1", "model.smithy",
  ]
  assert_eq(options(args).files, ["model.smithy"])
  let selected = options(args).value_validation.unwrap()
  assert_true(selected.input_format == IonTextInput)
  assert_eq(selected.ion_index, Some(1))
  for
    suffix in [
      ["--input-format", "xml"],
      ["--ion-index", "0"],
      ["--input-format", "ion-text", "--ion-index", "-1"],
      ["--input-format", "ion-binary", "--ion-index", "x"],
    ] {
    let code = try
      options(args[:6].to_owned() + ["values.ion", "model.smithy"] + suffix)
    catch {
      CliError(_, code) => code
    } noraise {
      _ => 0
    }
    assert_eq(code, 2)
  }
}

///|
test "Ion input decoders enforce selection and source limits" {
  let values = "{count: 0} {count: 2}"
  let selected = parse_ion_input(@utf8.encode(values), IonTextInput, Some(1))
  assert_true(selected.equals(@ion_text.read_ion("{count: 2}")))
  let binary = @ion_binary.write_binary(@ion_text.read_ion_datagram(values))
  assert_true(parse_ion_input(binary, IonBinaryInput, Some(1)).equals(selected))
  for
    (bytes, format, index, expected) in [
      (b"", IonTextInput, None, "IonSelection"),
      (@utf8.encode(values), IonTextInput, None, "IonSelection"),
      (@utf8.encode(values), IonTextInput, Some(2), "IonSelection"),
      (b"{", IonTextInput, None, "InvalidIon"),
      (b"\xff", IonTextInput, None, "InvalidIon"),
      (b"\xe0\x01\x00\xea\xde", IonBinaryInput, None, "InvalidIon"),
      (
        @utf8.encode("[".repeat(140) + "0" + "]".repeat(140)),
        IonTextInput,
        None,
        "IonInputLimit",
      ),
      (
        Bytes::make(16 * 1024 * 1024 + 1, b' '),
        IonBinaryInput,
        None,
        "IonInputLimit",
      ),
    ] {
    let code = try parse_ion_input(bytes, format, index) catch {
      IonInputError(code, _, _) => code
    } noraise {
      _ => "accepted"
    }
    assert_eq(code, expected)
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

///|
test "transcript CLI reads the protocol, flags and the last positional" {
  let opts = options([
    "validate", "rpc", "transcript", "--protocol", "example.peers#Editor", "peers.smithy",
    "extra.json", "editor.json",
  ])
  assert_eq(opts.files, ["peers.smithy", "extra.json"])
  assert_eq(opts.rpc_version, None)
  assert_eq(opts.rpc_options is None, true)
  let transcript = opts.transcript.unwrap()
  assert_eq(transcript.file, "editor.json")
  assert_eq(transcript.version, None)
  assert_eq(transcript.completeness, None)
  let value_opts = opts.value_validation.unwrap()
  assert_eq(value_opts.target.to_string(), "example.peers#Editor")
  assert_eq(value_opts.file, "editor.json")
  assert_true(value_opts.diagnostics == TextFindings)
  let opts = options([
    "validate", "rpc", "transcript", "--protocol", "example.peers#Editor", "--version",
    "2.0", "--complete", "--diagnostics", "json", "--input-format", "json", "--from",
    "idl", "-", "log.txt",
  ])
  let transcript = opts.transcript.unwrap()
  assert_eq(opts.files, ["-"])
  assert_eq(transcript.version, Some(@rpc.V2_0))
  assert_eq(transcript.completeness, Some(@rpc.Complete))
  assert_true(opts.value_validation.unwrap().diagnostics == JsonFindings)
  let partial = options([
    "validate", "rpc", "transcript", "--protocol", "example.peers#Editor", "--partial",
    "--input-format=json", "peers.smithy", "-",
  ])
  assert_eq(partial.transcript.unwrap().completeness, Some(@rpc.Partial))
  assert_eq(partial.transcript.unwrap().file, "-")
}

///|
test "transcript input formats follow the extension, and stdin defaults to JSONL" {
  assert_true(transcript_format("t.json", None) is JsonTranscript)
  assert_true(transcript_format("t.md", None) is MarkdownTranscript)
  assert_true(transcript_format("t.jsonl", None) is JsonlTranscript)
  assert_true(transcript_format("t.ndjson", None) is JsonlTranscript)
  assert_true(transcript_format("-", None) is JsonlTranscript)
  assert_true(transcript_format("-", Some("json")) is JsonTranscript)
  assert_true(
    transcript_format("t.json", Some("markdown")) is MarkdownTranscript,
  )
  for args in [["t.txt", ""], ["t.json", "xml"]] {
    let format = if args[1] == "" { None } else { Some(args[1]) }
    let code = try transcript_format(args[0], format) catch {
      CliError(_, code) => code
    } noraise {
      _ => 0
    }
    assert_eq(code, 2, msg=args.join(" "))
  }
}

///|
test "transcript CLI usage and contract errors exit 2" {
  let base = ["validate", "rpc", "transcript"]
  for
    tail in [
      ["peers.smithy", "editor.json"],
      ["--protocol", "example.peers#Editor", "editor.json"],
      ["--protocol", "Editor", "peers.smithy", "editor.json"],
      ["--protocol", "example.peers#Editor$x", "peers.smithy", "editor.json"],
      [
        "--protocol", "example.peers#Editor", "--version", "1.1", "peers.smithy",
        "editor.json",
      ],
      [
        "--protocol", "example.peers#Editor", "--complete", "--partial", "peers.smithy",
        "editor.json",
      ],
      [
        "--protocol", "example.peers#Editor", "--input-format", "xml", "peers.smithy",
        "editor.json",
      ],
      ["--protocol", "example.peers#Editor", "peers.smithy", "editor.txt"],
      ["--protocol", "example.peers#Editor", "peers.smithy", "editor.jsonl"],
      ["--protocol", "example.peers#Editor", "peers.smithy", "-"],
      [
        "--protocol", "example.peers#Editor", "--input-format", "json", "--from",
        "idl", "-", "-",
      ],
      [
        "--protocol", "example.peers#Editor", "--diagnostics", "xml", "peers.smithy",
        "editor.json",
      ],
      [
        "--protocol", "example.peers#Editor", "--service", "example#Api", "peers.smithy",
        "editor.json",
      ],
    ] {
    let code = try options(base + tail) catch {
      CliError(_, code) => code
    } noraise {
      _ => 0
    }
    assert_eq(code, 2, msg=tail.join(" "))
  }
  // Options and inputs of `rpc` do not reach the nested transcript command.
  for
    args in [
      [
        "validate", "rpc", "--version", "2.0", "transcript", "--protocol", "example.peers#Editor",
        "peers.smithy", "editor.json",
      ],
      [
        "validate", "rpc", "--diagnostics", "json", "transcript", "--protocol", "example.peers#Editor",
        "peers.smithy", "editor.json",
      ],
    ] {
    let code = try options(args) catch {
      CliError(_, code) => code
    } noraise {
      _ => 0
    }
    assert_eq(code, 2, msg=args.join(" "))
  }
}

///|
test "rpc keeps its required options when no transcript is named" {
  for
    tail in [
      ["--service", "example#Api", "--message", "m.json", "m.smithy"],
      ["--version", "2.0", "--message", "m.json", "m.smithy"],
      ["--version", "2.0", "--service", "example#Api", "--message", "m.json"],
    ] {
    let code = try options(["validate", "rpc"] + tail) catch {
      CliError(_, code) => code
    } noraise {
      _ => 0
    }
    assert_eq(code, 2, msg=tail.join(" "))
  }
}

///|
test "transcript version comes from the flag or the document and must agree" {
  assert_eq(
    transcript_version(Some(@rpc.V2_0), None, "t.json"),
    Some(@rpc.V2_0),
  )
  assert_eq(
    transcript_version(None, Some(@rpc.V1_0), "t.json"),
    Some(@rpc.V1_0),
  )
  assert_eq(
    transcript_version(Some(@rpc.V1_0), Some(@rpc.V1_0), "t.json"),
    Some(@rpc.V1_0),
  )
  assert_eq(transcript_version(None, None, "t.json"), None)
  let code = try
    transcript_version(Some(@rpc.V1_0), Some(@rpc.V2_0), "t.json")
  catch {
    CliError(_, code) => code
  } noraise {
    _ => 0
  }
  assert_eq(code, 2)
}
