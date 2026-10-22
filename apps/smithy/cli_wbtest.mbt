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

///|
fn transcript_usage_status(args : Array[String]) -> Int32 {
  try options(["validate", "rpc", "transcript"] + args) catch {
    CliError(_, code) => code
  } noraise {
    _ => 0
  }
}

///|
test "JSONL transcripts read the log options" {
  let base = [
    "--protocol", "example.peers#Editor", "--version", "2.0", "peers.smithy",
  ]
  let log = options(["validate", "rpc", "transcript"] + base + ["log.jsonl"]).transcript.unwrap().log
  // Without a preset or a mapping file, a log is dir-message with the default map.
  assert_true(log is Some(DirMessageLog(None)))
  let log = options(
      ["validate", "rpc", "transcript"] +
      base +
      [
        "--log-preset", "dir-message", "--direction", "in=client", "--direction",
        "out=server", "-",
      ],
    ).transcript.unwrap().log
  guard log is Some(DirMessageLog(Some(directions))) else {
    fail("expected the --direction map")
  }
  assert_eq(directions.to_array().map(pair => (pair.0, pair.1.to_string())), [
    ("in", "client"),
    ("out", "server"),
  ])
  let log = options(
      ["validate", "rpc", "transcript"] +
      base +
      ["--log-preset", "raw", "--sender", "client", "log.jsonl"],
    ).transcript.unwrap().log
  guard log is Some(RawLog(sender)) else { fail("expected the raw preset") }
  assert_eq(sender.to_string(), "client")
  let log = options(
      ["validate", "rpc", "transcript"] +
      base +
      ["--log-mapping", "log.mapping.json", "log.ndjson"],
    ).transcript.unwrap().log
  assert_true(log is Some(MappingFile("log.mapping.json")))
  // JSON and Markdown documents take no log options.
  let document = options(["validate", "rpc", "transcript"] + base + ["t.json"])
  assert_true(document.transcript.unwrap().log is None)
}

///|
test "JSONL log option conflicts and a raw preset without --sender exit 2" {
  let base = ["--protocol", "example.peers#Editor", "peers.smithy"]
  let version = ["--version", "2.0"]
  for
    args in [
      // JSONL has no document header, so the version is required.
      ["log.jsonl"],
      ["--log-preset", "raw", "--sender", "client", "-"],
      // The preset and the mapping file conflict.
      version + ["--log-preset", "raw", "--log-mapping", "m.json", "log.jsonl"],
      version +
      ["--log-preset", "dir-message", "--log-mapping", "m.json", "log.jsonl"],
      // raw needs a sender, and only raw takes one.
      version + ["--log-preset", "raw", "log.jsonl"],
      version + ["--sender", "client", "log.jsonl"],
      version +
      ["--log-preset", "dir-message", "--sender", "client", "log.jsonl"],
      version + ["--log-mapping", "m.json", "--sender", "client", "log.jsonl"],
      // Only dir-message takes directions.
      version +
      [
        "--log-preset", "raw", "--sender", "client", "--direction", "in=client",
        "log.jsonl",
      ],
      version +
      ["--log-mapping", "m.json", "--direction", "in=client", "log.jsonl"],
      // A direction is value=peer, once per value.
      version + ["--direction", "in", "log.jsonl"],
      version + ["--direction", "=client", "log.jsonl"],
      version + ["--direction", "in=", "log.jsonl"],
      version + ["--direction", "in=not a peer", "log.jsonl"],
      version +
      ["--direction", "in=client", "--direction", "in=server", "log.jsonl"],
      version + ["--log-preset", "xml", "log.jsonl"],
      version + ["--log-preset", "raw", "--sender", "not a peer", "log.jsonl"],
      // Log options need JSONL input.
      version + ["--log-preset", "dir-message", "t.json"],
      version + ["--direction", "in=client", "t.md"],
      version + ["--log-mapping", "m.json", "t.json"],
      version + ["--sender", "client", "--input-format", "json", "-"],
    ] {
    assert_eq(transcript_usage_status(base + args), 2, msg=args.join(" "))
  }
}

///|
test "UTF-8 split between stdin chunks decodes once" {
  let whole = b"a\xc3\xa9\xe2\x82\xac\xf0\x9f\x98\x80\n\xff\xc3(\xe2\x82\n\xef\xbb\xbfz\xf0\x9f"
  let expected = @utf8.decode_lossy(whole)
  for split in 0..<=whole.length() {
    let chunks = Utf8Chunks::new()
    let text = chunks.push(whole[:split].to_owned()) +
      chunks.push(whole[split:].to_owned()) +
      chunks.end()
    assert_eq(text, expected, msg="split at \{split}")
  }
  // One byte per chunk also decodes each character once.
  let chunks = Utf8Chunks::new()
  let text = StringBuilder()
  for byte in whole {
    text.write_string(chunks.push(Bytes::from_array([byte])))
  }
  text.write_string(chunks.end())
  assert_eq(text.to_string(), expected)
  assert_true(expected.contains("\u{FFFD}"))
  assert_true(expected.has_prefix("aé€😀\n"))
}

///|
test "transcript CLI reads --expect and --legacy-errors" {
  let base = [
    "validate", "rpc", "transcript", "--protocol", "example.peers#EchoChat",
  ]
  let transcript = options(
    base + ["--expect", "expected.json", "peers.smithy", "chat.json"],
  ).transcript.unwrap()
  assert_eq(transcript.expect, Some("expected.json"))
  assert_true(transcript.legacy_errors is None)
  // The document can give the version, so 1.0 is checked after it is read.
  let transcript = options(
    base + ["--legacy-errors", "code-message-data", "peers.smithy", "chat.json"],
  ).transcript.unwrap()
  assert_true(transcript.legacy_errors is Some(@rpc.CodeMessageData))
  let transcript = options(
    base +
    [
      "--legacy-errors", "opaque", "--version", "1.0", "peers.smithy", "chat.jsonl",
    ],
  ).transcript.unwrap()
  assert_true(transcript.legacy_errors is Some(@rpc.Opaque))
  for
    args in [
      ["--legacy-errors", "verbose", "peers.smithy", "chat.json"],
      [
        "--legacy-errors", "opaque", "--version", "2.0", "peers.smithy", "chat.json",
      ],
      [
        "--legacy-errors", "code-message-data", "--version", "2.0", "peers.smithy",
        "chat.jsonl",
      ],
    ] {
    let message = try options(base + args) catch {
      CliError(message, 2) => message
      _ => "other error"
    } noraise {
      _ => "accepted"
    }
    assert_true(
      message == "expected opaque or code-message-data after --legacy-errors" ||
      message == "--legacy-errors requires version 1.0",
      msg=args.join(" ") + ": " + message,
    )
  }
}

///|
/// An input source over `chunks`, then end of input or `error`. It counts
/// the reads and the closes.
priv struct FakeInput {
  chunks : Array[Bytes]
  error : Error?
  mut reads : Int32
  mut closes : Int32
}

///|
fn FakeInput::source(self : FakeInput) -> InputSource {
  {
    read: requested => {
      assert_eq(requested, INPUT_CHUNK_BYTES)
      let index = self.reads
      self.reads += 1
      if index < self.chunks.length() {
        self.chunks[index]
      } else if self.error is Some(error) {
        raise error
      } else {
        b""
      }
    },
    close: () => self.closes += 1,
  }
}

///|
test "read_chunks gives each chunk, closes once and returns a read error" {
  let input = FakeInput::{
    chunks: [b"ab", b"c"],
    error: None,
    reads: 0,
    closes: 0,
  }
  let seen = []
  assert_true(read_chunks(input.source(), chunk => seen.push(chunk)) is Ended)
  assert_eq(seen, [b"ab", b"c"])
  assert_eq(input.reads, 3)
  assert_eq(input.closes, 1)
  // A read error is given back after the chunks before it.
  let input = FakeInput::{
    chunks: [b"ab"],
    error: Some(CliError("could not read stdin", 1)),
    reads: 0,
    closes: 0,
  }
  let seen = []
  let failure = read_chunks(input.source(), chunk => seen.push(chunk))
  assert_true(failure is Failed(CliError("could not read stdin", 1)))
  assert_eq(seen, [b"ab"])
  assert_eq(input.closes, 1)
  // A read error before any byte arrived means the input was never readable.
  let input = FakeInput::{
    chunks: [],
    error: Some(CliError("could not read 'dir.jsonl'", 1)),
    reads: 0,
    closes: 0,
  }
  let failure = read_chunks(input.source(), _ => fail("expected no chunk"))
  assert_true(failure is Unreadable(CliError("could not read 'dir.jsonl'", 1)))
  assert_eq(input.reads, 1)
  assert_eq(input.closes, 1)
  // An error of the consumer closes the source and propagates.
  let input = FakeInput::{
    chunks: [b"ab", b"c"],
    error: None,
    reads: 0,
    closes: 0,
  }
  let raised = try
    read_chunks(input.source(), _ => raise CliError("could not write", 1))
  catch {
    CliError("could not write", 1) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(raised)
  assert_eq(input.reads, 1)
  assert_eq(input.closes, 1)
}

///|
fn link_protocol() -> @rpc.ProtocolDescription raise {
  let source =
    #|$version: "2"
    #|namespace example
    #|use smithy.rpc#jsonRpc
    #|use smithy.rpc#jsonRpcProtocol
    #|use smithy.rpc#method
    #|@jsonRpcProtocol(versions: ["2.0"], peers: [
    #|    { name: "client", accepts: Client }
    #|    { name: "server", accepts: Server }
    #|])
    #|structure Link {}
    #|@jsonRpc(versions: ["2.0"])
    #|service Server { version: "1", operations: [Ping] }
    #|@jsonRpc(versions: ["2.0"])
    #|service Client { version: "1" }
    #|@method(name: "ping", params: "named", nullResult: true)
    #|operation Ping {}
  let loaded = @rpc.loader().add_idl("link.smithy", source).assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  @rpc.ProtocolDescription::from_smithy(
    model,
    @smithy.ShapeId::parse("example#Link").unwrap(),
    @rpc.V2_0,
  )
}

///|
/// Streams `input` as a dir-message log through a sink in memory, and gives
/// the status, or the CliError raised, and the JSON Lines written.
fn stream_lines(
  input : FakeInput,
  expected : Array[@rpc.ExpectedFinding]?,
) -> (String, Array[Json]) raise {
  stream_opened(() => input.source(), expected)
}

///|
/// Streams the input that `open` gives, like `stream_lines`. The status is
/// "unreadable" when `stream_log` found no readable input.
fn stream_opened(
  open : () -> InputSource raise,
  expected : Array[@rpc.ExpectedFinding]?,
) -> (String, Array[Json]) raise {
  let protocol = link_protocol()
  let peers = protocol.peers()
  let reader = @rpc.LogReader::new(
    @rpc.LogMapping::dir_message({ "request": peers[0], "response": peers[1] }),
  )
  let checker = @rpc.TranscriptChecker::new(protocol)
  let written : Array[Byte] = []
  let sink : OutputSink = {
    write: bytes => {
      for byte in bytes {
        written.push(byte)
      }
    },
    flush: () => (),
    close: () => (),
    flush_records: true,
  }
  let opts : ValueOptions = {
    target: protocol.protocol(),
    file: "log.jsonl",
    diagnostics: JsonFindings,
    config: @validation.Config::new(),
    input_format: JsonInput,
    ion_index: None,
  }
  let status = try
    stream_log(open, reader, checker, FindingStream::new(opts, sink, expected))
  catch {
    CliError(message, code) => "raised \{code}: \{message}"
    _ => "raised another error"
  } noraise {
    Checked(status) => "status \{status}"
    Unreadable => "unreadable"
  }
  let text = @utf8.decode(Bytes::from_array(written))
  let lines = []
  for line in text.split("\n") {
    if !line.is_empty() {
      lines.push(@json.parse(line))
    }
  }
  (status, lines)
}

///|
test "a log mapping that the library rejects exits 2" {
  let protocol = link_protocol()
  let status = try log_mapping(DirMessageLog(Some({})), protocol) catch {
    CliError(message, code) => "raised \{code}: \{message}"
  } noraise {
    _ => "accepted"
  }
  assert_eq(
    status, "raised 2: --direction: I expected at least one dir value in the dir-message map; directions was empty.",
  )
}

///|
test "a read error part-way through a log still writes the summary" {
  let unsolicited = b"{\"dir\":\"response\",\"message\":{\"jsonrpc\":\"2.0\",\"id\":9,\"result\":null}}\n{\"dir\":\"req"
  let input = FakeInput::{
    chunks: [unsolicited],
    error: Some(CliError("could not read stdin", 1)),
    reads: 0,
    closes: 0,
  }
  let (status, lines) = stream_lines(input, None)
  assert_eq(status, "raised 1: could not read stdin")
  assert_eq(input.closes, 1)
  guard lines
    is [
      { "code": "UnsolicitedResponse", "line": Number(1.0, ..), .. },
      // The cut line that was read is not JSON.
      {
        "summary": {
          "valid": False,
          "lines": Number(2.0, ..),
          "not_json": Number(1.0, ..),
          ..
        },
        ..
      },
    ] else {
    fail(
      "expected the findings and then the summary: \{Json::array(lines).stringify()}",
    )
  }
}

///|
test "a log that fails on its first read is unreadable like a missing file" {
  // A path that opens but gives a read error at once, such as a directory
  // on POSIX, writes no findings and no summary.
  let input = FakeInput::{
    chunks: [],
    error: Some(CliError("could not read 'dir.jsonl'", 1)),
    reads: 0,
    closes: 0,
  }
  let unreadable = stream_lines(input, None)
  assert_eq(unreadable, ("unreadable", []))
  assert_eq(input.reads, 1)
  assert_eq(input.closes, 1)
  // A path that does not open gives the same outcome.
  let missing = stream_opened(
    () => raise CliError("could not open 'missing.jsonl'", 1),
    None,
  )
  assert_eq(missing, unreadable)
}

///|
test "a log matches --expect at the end and the status follows the match" {
  let log = b"{\"dir\":\"response\",\"message\":{\"jsonrpc\":\"2.0\",\"id\":9,\"result\":null}}\n"
  fn input() -> FakeInput {
    { chunks: [log], error: None, reads: 0, closes: 0, }
  }

  let unsolicited = @rpc.ExpectedFinding::new(
    "UnsolicitedResponse",
    entry=Some(0),
  ).unwrap()
  let (status, lines) = stream_lines(input(), Some([unsolicited]))
  assert_eq(status, "status 0")
  guard lines
    is [
      { "code": "UnsolicitedResponse", .. },
      {
        "summary": {
          "valid": False,
          "expectations": {
            "matched": True,
            "missing": [],
            "unexpected": [],
            ..
          },
          ..
        },
        ..
      },
    ] else {
    fail("expected a matched expectation: \{Json::array(lines).stringify()}")
  }
  let duplicate = @rpc.ExpectedFinding::new("DuplicateResponse").unwrap()
  let (status, lines) = stream_lines(input(), Some([duplicate]))
  assert_eq(status, "status 1")
  guard lines
    is [
      _,
      {
        "summary": {
          "expectations": {
            "matched": False,
            "missing": [{ "code": "DuplicateResponse", .. }],
            "unexpected": [{ "code": "UnsolicitedResponse", .. }],
            ..
          },
          ..
        },
        ..
      },
    ] else {
    fail("expected a failed expectation: \{Json::array(lines).stringify()}")
  }
  // Without an expect list, the summary has no expectations.
  let (status, lines) = stream_lines(input(), None)
  assert_eq(status, "status 1")
  guard lines is [_, { "summary": summary, .. }] && summary is Object(fields) else {
    fail("expected a summary: \{Json::array(lines).stringify()}")
  }
  assert_false(fields.contains("expectations"))
}
