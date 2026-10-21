///|
fn output_event(
  message : String,
  severity~ : String = "NOTE",
) -> @smithy.ValidationEvent {
  {
    id: "Example",
    severity,
    shape: None,
    message,
    source: None,
    suppression_reason: None,
  }
}

///|
test "diff format is validated at the CLI boundary" {
  for
    (flags, expected) in [
      ([], Text),
      (["--format", "text"], Text),
      (["--format=jsonl"], Jsonl),
      (["--format", "jsonl"], Jsonl),
    ] {
    let opts = options(["diff", "--old", "missing", "--new", "missing"] + flags)
    assert_eq(opts.diff_format, expected)
  }
  for
    flags in [
      ["--format", "json"],
      ["--format"],
      ["--format="],
      ["--stream"],
      ["-p"],
    ] {
    let code = try
      options(["diff", "--old", "missing", "--new", "missing"] + flags)
    catch {
      CliError(_, code) => code
    } noraise {
      _ => 0
    }
    assert_eq(code, 2)
  }
}

///|
test "JSONL preserves structured values, nulls and UTF-16 source offsets" {
  let message = "line\nreturn\rtab\tquote\"slash\\nul\u0000雪🐟\u2028\u2029"
  let event = output_event(message)
  let expected : Json = {
    "id": "Example",
    "severity": "NOTE",
    "shape": null,
    "message": message,
    "source": null,
  }
  assert_eq(diff_event_json(event), expected)
  let shape = @smithy.ShapeId::parse("example#Value$name").unwrap()
  let source : @smithy.SourceLocation = {
    file: "models.jar!/模型.smithy",
    path: "",
    span: Some(
      @syntax.Span::new(
        @syntax.Offset::new(42).unwrap(),
        @syntax.Length::new(12).unwrap(),
      ),
    ),
  }
  let sourced = { ..event, shape: Some(shape), source: Some(source), }
  let expected : Json = {
    "id": "Example",
    "severity": "NOTE",
    "shape": "example#Value$name",
    "message": message,
    "source": {
      "file": source.file,
      "path": "",
      "span": { "start": 42, "length": 12 },
    },
  }
  assert_eq(diff_event_json(sourced), expected)
  let json_source : @smithy.SourceLocation = {
    file: "model.json",
    path: "/shapes/example#Value/members/name",
    span: None,
  }
  let expected : Json = {
    "file": "model.json",
    "path": json_source.path,
    "span": null,
  }
  guard diff_event_json({ ..sourced, source: Some(json_source), })
    is { "source": actual, .. } else {
    fail("missing source")
  }
  assert_eq(actual, expected)
}

///|
test "JSONL writes and flushes records individually, filtering suppressions" {
  let messages = ["first\n\"\\🐟", "last\r\t雪"]
  let events = [
    output_event(messages[0]),
    output_event("hidden", severity="SUPPRESSED"),
    output_event(messages[1], severity="WARNING"),
  ]
  let operations : Array[String] = []
  let records : Array[Json] = []
  let sink : OutputSink = {
    write: bytes => {
      let text = @utf8.decode(bytes)
      assert_true(text.has_suffix("\n"))
      assert_eq(text.split("\n").count(), 2)
      // Requiring a previous flush before accepting another record makes the
      // timing contract observable without depending on process scheduling.
      assert_eq(
        operations.filter(op => op == "flush").length(),
        records.length(),
      )
      records.push(@json.parse(text))
      operations.push("write")
    },
    flush: () => operations.push("flush"),
    close: () => operations.push("close"),
    flush_records: true,
  }
  write_diff_jsonl(events, sink)
  assert_eq(operations, ["write", "flush", "write", "flush", "close"])
  assert_eq(records, [diff_event_json(events[0]), diff_event_json(events[2])])
}

///|
test "later records are serialized only after earlier delivery completes" {
  let events = [output_event("first"), output_event("before delivery")]
  let messages : Array[String] = []
  let sink : OutputSink = {
    write: bytes => {
      guard @json.parse(@utf8.decode(bytes))
        is { "message": String(message), .. } else {
        fail("missing message")
      }
      messages.push(message)
    },
    flush: () => events[1] = output_event("after delivery"),
    close: () => (),
    flush_records: true,
  }
  write_diff_jsonl(events, sink)
  assert_eq(messages, ["first", "after delivery"])
}

///|
test "file delivery flushes once, closes, and handles empty output" {
  for
    events in [
      [],
      [output_event("one"), output_event("two")],
      [output_event("hidden", severity="SUPPRESSED")],
    ] {
    let operations : Array[String] = []
    let sink : OutputSink = {
      write: _ => operations.push("write"),
      flush: () => operations.push("flush"),
      close: () => operations.push("close"),
      flush_records: false,
    }
    write_diff_jsonl(events, sink)
    let expected = events
      .filter(e => e.severity != "SUPPRESSED")
      .map(_ => "write")
    expected.append(["flush", "close"])
    assert_eq(operations, expected)
  }
}

///|
test "output failure stops delivery and closes the sink once" {
  for stage in ["write", "flush", "close"] {
    let operations : Array[String] = []
    let sink : OutputSink = {
      write: _ => {
        operations.push("write")
        if stage == "write" {
          raise CliError("write", 1)
        }
      },
      flush: () => {
        operations.push("flush")
        if stage == "flush" {
          raise CliError("flush", 1)
        }
      },
      close: () => {
        operations.push("close")
        if stage == "close" {
          raise CliError("close", 1)
        }
      },
      flush_records: true,
    }
    let failure = try
      write_diff_jsonl([output_event("one"), output_event("two")], sink)
    catch {
      CliError(message, code) => {
        assert_eq(code, 1)
        message
      }
      error => fail("unexpected error: \{error}")
    } noraise {
      _ => "no failure"
    }
    assert_eq(failure, stage)
    assert_eq(operations.filter(op => op == "close").length(), 1)
    if stage != "close" {
      assert_eq(operations.filter(op => op == "write").length(), 1)
    }
  }
}

///|
test "cleanup failure preserves the original output failure" {
  let sink : OutputSink = {
    write: _ => raise CliError("original", 1),
    flush: () => (),
    close: () => raise CliError("cleanup", 1),
    flush_records: false,
  }
  let failure = try write_diff_jsonl([output_event("one")], sink) catch {
    CliError(message, _) => message
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => "no failure"
  }
  assert_eq(failure, "original")
}
