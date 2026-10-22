///|
/// How the lines of a JSONL log become transcript entries. The peer names are
/// checked against the protocol after the model is loaded.
priv enum LogChoice {
  /// `--log-preset raw --sender <peer>`: each JSON-RPC line comes from one peer.
  RawLog(@rpc.PeerName)
  /// `--log-preset dir-message`, the default: `{"dir", "message"}` records.
  /// The `--direction` map, or `None` for request = the first peer and
  /// response = the second.
  DirMessageLog(Map[String, @rpc.PeerName]?)
  /// `--log-mapping <file>`: a mapping in the `LogMapping::from_json` form.
  MappingFile(String)
}

///|
/// Reads --log-preset, --log-mapping, --sender and --direction. A mapping file
/// names its own senders, raw takes only --sender, and dir-message takes only
/// --direction.
fn log_choice(
  preset : String?,
  mapping : String?,
  sender : String?,
  directions : Array[String],
) -> LogChoice raise CliError {
  fn peer(text : String, option : String) -> @rpc.PeerName raise CliError {
    guard @rpc.PeerName::parse(text) is Some(peer) else {
      raise CliError("expected a peer name after \{option}, found '\{text}'", 2)
    }
    peer
  }

  match (preset, mapping) {
    (Some(_), Some(_)) =>
      raise CliError("use only one of --log-preset and --log-mapping", 2)
    (None, Some(file)) => {
      if sender is Some(_) || !directions.is_empty() {
        raise CliError(
          "--log-mapping names the senders; do not use --sender or --direction with it",
          2,
        )
      }
      MappingFile(file)
    }
    (Some("raw"), None) => {
      if !directions.is_empty() {
        raise CliError("--direction requires --log-preset dir-message", 2)
      }
      guard sender is Some(name) else {
        raise CliError("--log-preset raw requires --sender <peer>", 2)
      }
      RawLog(peer(name, "--sender"))
    }
    (Some("dir-message") | None, None) => {
      if sender is Some(_) {
        raise CliError("--sender requires --log-preset raw", 2)
      }
      if directions.is_empty() {
        return DirMessageLog(None)
      }
      let map : Map[String, @rpc.PeerName] = Map([])
      for direction in directions {
        guard direction.rev_find("=") is Some(at) &&
          at > 0 &&
          at < direction.length() - 1 else {
          raise CliError(
            "expected value=peer after --direction, found '\{direction}'",
            2,
          )
        }
        let name = direction[:at].to_owned()
        if map.contains(name) {
          raise CliError("--direction gives the value '\{name}' twice", 2)
        }
        map[name] = peer(direction[at + 1:].to_owned(), "--direction \{name}=")
      }
      DirMessageLog(Some(map))
    }
    (Some(other), None) =>
      raise CliError(
        "expected raw or dir-message after --log-preset, found '\{other}'",
        2,
      )
  }
}

///|
/// Builds the log mapping of `choice`. Every peer it names must be a peer of
/// the protocol.
fn log_mapping(
  choice : LogChoice,
  protocol : @rpc.ProtocolDescription,
) -> @rpc.LogMapping raise CliError {
  let peers = protocol.peers()
  let names = peers.map(p => p.to_string()).join(", ")
  fn known(peer : @rpc.PeerName, option : String) -> Unit raise CliError {
    if !peers.contains(peer) {
      raise CliError(
        "\{option} names \{peer.to_string()}, which is not a peer of \{protocol.protocol().to_string()} (\{names})",
        2,
      )
    }
  }

  match choice {
    RawLog(sender) => {
      known(sender, "--sender")
      @rpc.LogMapping::raw(sender)
    }
    DirMessageLog(None) =>
      @rpc.LogMapping::dir_message({ "request": peers[0], "response": peers[1] })
    DirMessageLog(Some(directions)) => {
      for value, peer in directions {
        known(peer, "--direction \{value}=")
      }
      @rpc.LogMapping::dir_message(directions)
    }
    MappingFile(file) => {
      let text = @fs.read_file_to_string(file) catch {
        _ => raise CliError("could not read the --log-mapping file \{file}", 2)
      }
      @rpc.LogMapping::from_json(text, peers) catch {
        @validation.ConfigurationError(message) =>
          raise CliError("\{file}: \{message}", 2)
      }
    }
  }
}

///|
/// Checks a JSONL log as it is read, and writes each finding when it is known:
/// one line per finding, then a summary line. With `expected`, the summary
/// also gives the expectation match, and the exit status follows it.
fn run_log_transcript(
  opts : ValueOptions,
  transcript : TranscriptOptions,
  protocol : @rpc.ProtocolDescription,
  choice : LogChoice,
  expected : Array[@rpc.ExpectedFinding]?,
) -> Int32 raise {
  let reader = @rpc.LogReader::new(log_mapping(choice, protocol))
  // A log with one sender has no replies to correlate.
  let checker = @rpc.TranscriptChecker::new(
    protocol,
    completeness=transcript.completeness.unwrap_or(@rpc.Partial),
    correlation=!reader.single_sender(),
    legacy_errors=transcript.legacy_errors.unwrap_or(@rpc.Opaque),
  )
  let source = chunk_source(transcript.file) catch {
    _ =>
      return value_problem(
        opts, "InputRead", "I could not read the JSON-RPC transcript input.", 1,
      )
  }
  stream_log(
    source,
    reader,
    checker,
    FindingStream::new(opts, finding_sink(opts), expected),
  )
}

///|
/// Feeds each chunk of `source` through the reader and the checker, and
/// writes the findings as they are known. A read error part-way through
/// still ends the log and writes the summary, which is then not valid; the
/// error is raised after it.
fn stream_log(
  source : InputSource,
  reader : @rpc.LogReader,
  checker : @rpc.TranscriptChecker,
  output : FindingStream,
) -> Int32 raise {
  let chunks = Utf8Chunks::new()
  fn check(text : String) -> Unit raise {
    output.write_all(check_lines(reader.push_text(text), checker))
  }

  let failure = read_chunks(source, bytes => check(chunks.push(bytes)))
  check(chunks.end())
  output.write_all(check_lines(reader.end(), checker))
  let summary = checker.finish()
  output.write_all(summary.findings)
  let status = output.finish(
    summary,
    reader.counts(),
    read_failed=failure is Some(_),
  )
  if failure is Some(error) {
    raise error
  }
  status
}

///|
/// Feeds the entries that a reader gave for some lines to the checker, and
/// gives the reader and checker findings in line order. A line has either an
/// entry or a reader finding, so the order does not depend on chunk sizes.
fn check_lines(
  read : (Array[@rpc.TranscriptEntry], Array[@rpc.TranscriptFinding]),
  checker : @rpc.TranscriptChecker,
) -> Array[@rpc.TranscriptFinding] {
  let (entries, problems) = read
  fn line(location : @rpc.SourceLocation?) -> Int32 {
    location.map(at => at.line).unwrap_or(0)
  }

  let out = []
  let mut problem = 0
  for entry in entries {
    while problem < problems.length() &&
          line(problems[problem].location) < line(entry.location) {
      out.push(problems[problem])
      problem += 1
    }
    out.append(checker.feed(entry))
  }
  out.append(problems[problem:].to_owned())
  out
}

///|
/// Writes streamed findings as they are known: text lines to stderr, or JSON
/// Lines to stdout. Each line is flushed. With an expect list, it keeps the
/// findings to match them at the end.
priv struct FindingStream {
  opts : ValueOptions
  sink : OutputSink
  expected : Array[@rpc.ExpectedFinding]?
  seen : Array[@rpc.TranscriptFinding]
  mut errors : Bool
}

///|
/// The sink of streamed findings: stdout for JSON, otherwise stderr.
fn finding_sink(opts : ValueOptions) -> OutputSink raise {
  if opts.diagnostics == JsonFindings {
    output_sink(None)
  } else {
    stderr_sink()
  }
}

///|
fn FindingStream::new(
  opts : ValueOptions,
  sink : OutputSink,
  expected : Array[@rpc.ExpectedFinding]?,
) -> FindingStream {
  { opts, sink, expected, seen: [], errors: false, }
}

///|
fn FindingStream::line(self : FindingStream, text : String) -> Unit raise {
  (self.sink.write)(@utf8.encode(text + "\n"))
  (self.sink.flush)()
}

///|
fn FindingStream::write_all(
  self : FindingStream,
  findings : Array[@rpc.TranscriptFinding],
) -> Unit raise {
  for finding in findings {
    if finding.severity == @validation.Error {
      self.errors = true
    }
    if self.expected is Some(_) {
      self.seen.push(finding)
    }
    self.line(
      if self.opts.diagnostics == JsonFindings {
        @json.to_json(finding).stringify()
      } else {
        transcript_finding_text(self.opts.file, finding)
      },
    )
  }
}

///|
/// Writes the summary line with the reader counts, and gives the exit status.
/// With an expect list, the summary has the match, and the status is 0 when
/// it matches. Otherwise the status is 0 when no finding is an error and no
/// limit stopped a check. A read error makes the summary not valid.
fn FindingStream::finish(
  self : FindingStream,
  summary : @rpc.TranscriptSummary,
  counts : @rpc.LogCounts,
  read_failed~ : Bool,
) -> Int32 raise {
  let valid = summary.complete && !self.errors && !read_failed
  let fields = summary_fields(valid, summary.complete, Some(summary), counts~)
  let expectations = self.expected.map(expected => {
    @rpc.match_expected(expected, self.seen)
  })
  if self.opts.diagnostics == JsonFindings {
    let record = Map::from_array(fields)
    if expectations is Some(result) {
      record["expectations"] = expectations_json(result)
    }
    self.line(Json::object({ "summary": Json::object(record) }).stringify())
  } else {
    if expectations is Some(result) {
      for line in expectation_lines(self.opts.file, result) {
        self.line(line)
      }
      fields.push(("matched", Json::boolean(result.is_match())))
    }
    let text = fields.map(field => "\{field.0}:\{field.1.stringify()}")
    self.line("\{self.opts.file}: summary: \{text.join(" ")}")
  }
  let passed = match expectations {
    Some(result) => result.is_match() && !read_failed
    None => valid
  }
  if passed {
    0
  } else {
    1
  }
}
