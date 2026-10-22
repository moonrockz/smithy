///|
/// The encoding of a transcript input.
priv enum TranscriptFormat {
  JsonTranscript
  MarkdownTranscript
  JsonlTranscript
}

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
priv struct TranscriptOptions {
  /// The transcript file, or "-" for stdin.
  file : String
  format : TranscriptFormat
  /// The --version flag; the document can also give the version.
  version : @rpc.ProtocolVersion?
  /// The --complete or --partial flag; it overrides the document.
  completeness : @rpc.Completeness?
  /// The log mapping for JSONL input; `None` for JSON and Markdown.
  log : LogChoice?
}

///|
fn transcript_command() -> @argparse.Command {
  input_command(
    "transcript",
    "Validate a JSON-RPC transcript between the two peers of a protocol: a JSON or Markdown document, or a JSONL log. Findings of a log are written as each line is read. The native and WASI binaries read stdin as it arrives; the js and wasm-gc binaries read all of stdin first and give the same findings.",
    files_about="Model files, then the transcript file or '-' for stdin. Use '--' before paths beginning with '-'.",
    options=[
      @argparse.OptionArg(
        "protocol",
        about="Absolute ID of the @jsonRpcProtocol structure.",
        required=true,
      ),
      @argparse.OptionArg(
        "version",
        about="JSON-RPC version: 1.0 or 2.0. Required when the transcript does not give it, and always for JSONL.",
      ),
      @argparse.OptionArg(
        "input-format",
        about="Transcript format: json, markdown or jsonl; default from .json, .md, .jsonl or .ndjson, and jsonl for stdin.",
      ),
      @argparse.OptionArg(
        "log-preset",
        about="JSONL lines: raw (JSON-RPC messages from --sender) or dir-message ({\"dir\", \"message\"} records); default dir-message.",
      ),
      @argparse.OptionArg(
        "log-mapping",
        about="JSONL mapping file: prefix, selector, message and sender. Conflicts with --log-preset.",
      ),
      @argparse.OptionArg(
        "sender",
        about="The peer that sends every message of a raw log. Required for --log-preset raw; correlation is then off.",
      ),
      @argparse.OptionArg(
        "direction",
        about="value=peer: the sender of dir-message records with that dir value. Repeat it for each value; default request=<first peer> and response=<second peer>.",
        action=@argparse.Append,
      ),
      @argparse.OptionArg(
        "diagnostics",
        about="Findings format: text or json; default text. For JSONL, json writes one finding per line and then a summary line.",
      ),
    ],
    flags=[
      @argparse.FlagArg(
        "complete",
        about="The transcript is complete: an unanswered call is an error.",
        conflicts_with=["partial"],
      ),
      @argparse.FlagArg(
        "partial",
        about="The transcript is partial: an unanswered call is an advisory. The default.",
      ),
    ],
  )
}

///|
/// Selects the transcript format from the --input-format value, or else from
/// the file extension. Stdin defaults to JSONL.
fn transcript_format(
  file : String,
  flag : String?,
) -> TranscriptFormat raise CliError {
  match flag {
    Some("json") => JsonTranscript
    Some("markdown") => MarkdownTranscript
    Some("jsonl") => JsonlTranscript
    Some(other) =>
      raise CliError(
        "expected json, markdown or jsonl after --input-format, found '\{other}'",
        2,
      )
    None =>
      if file == "-" || file.has_suffix(".jsonl") || file.has_suffix(".ndjson") {
        JsonlTranscript
      } else if file.has_suffix(".json") {
        JsonTranscript
      } else if file.has_suffix(".md") {
        MarkdownTranscript
      } else {
        raise CliError(
          "cannot infer the transcript format of '\{file}'; use --input-format json, markdown or jsonl",
          2,
        )
      }
  }
}

///|
fn transcript_options(
  file : String,
  value : (String) -> String?,
  flags : Map[String, Bool],
  directions~ : Array[String] = [],
) -> TranscriptOptions raise CliError {
  let version = match value("version") {
    None => None
    Some(text) =>
      match @rpc.ProtocolVersion::parse(text) {
        Some(version) => Some(version)
        None => raise CliError("expected 1.0 or 2.0 after --version", 2)
      }
  }
  let complete = flags.get("complete") == Some(true)
  let partial = flags.get("partial") == Some(true)
  if complete && partial {
    raise CliError("use only one of --complete and --partial", 2)
  }
  let completeness = if complete {
    Some(@rpc.Complete)
  } else if partial {
    Some(@rpc.Partial)
  } else {
    None
  }
  let format = transcript_format(file, value("input-format"))
  let preset = value("log-preset")
  let mapping = value("log-mapping")
  let sender = value("sender")
  let log = match format {
    JsonTranscript | MarkdownTranscript => {
      if preset is Some(_) ||
        mapping is Some(_) ||
        sender is Some(_) ||
        !directions.is_empty() {
        raise CliError(
          "--log-preset, --log-mapping, --sender and --direction apply only to JSONL input",
          2,
        )
      }
      None
    }
    JsonlTranscript => {
      // A log has no document header to give the version.
      if version is None {
        raise CliError(
          "a JSONL log gives no JSON-RPC version; use --version 1.0 or --version 2.0",
          2,
        )
      }
      Some(log_choice(preset, mapping, sender, directions))
    }
  }
  { file, format, version, completeness, log, }
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
/// Gives the version from the --version flag or from the transcript document.
/// They must agree when both give it. `None` means neither gives it.
fn transcript_version(
  flag : @rpc.ProtocolVersion?,
  document : @rpc.ProtocolVersion?,
  file : String,
) -> @rpc.ProtocolVersion? raise CliError {
  match (flag, document) {
    (Some(chosen), Some(written)) if chosen != written =>
      raise CliError(
        "--version \{chosen.to_string()} conflicts with version \{written.to_string()} in \{file}",
        2,
      )
    (Some(version), _) | (None, Some(version)) => Some(version)
    (None, None) => None
  }
}

///|
fn run_transcript_validation(
  opts : ValueOptions,
  transcript : TranscriptOptions,
  assembled : @smithy.LoadResult,
) -> Int32 raise {
  if !validation_model_ok(opts, assembled) {
    return 1
  }
  if transcript.log is Some(log) {
    // transcript_options requires --version for a log.
    guard transcript_protocol(opts, assembled, transcript.version.unwrap())
      is Some(protocol) else {
      return 2
    }
    return run_log_transcript(opts, transcript, protocol, log)
  }
  let text = try {
    if transcript.file == "-" {
      read_stdin()
    } else {
      @fs.read_file_to_string(transcript.file)
    }
  } catch {
    _ =>
      return value_problem(
        opts, "InputRead", "I could not read the JSON-RPC transcript input.", 1,
      )
  }
  let (document, read_findings) = match transcript.format {
    MarkdownTranscript => @rpc.read_markdown_transcript(text)
    _ => @rpc.read_json_transcript(text)
  }
  guard transcript_version(
      transcript.version,
      document.version,
      transcript.file,
    )
    is Some(version) else {
    // A document that I could not read may have lost its version; its error
    // findings explain the problem better than a usage error. Advisories
    // alone do not, so they fall through to the usage error.
    if read_findings.any(f => f.severity == @validation.Error) {
      return print_transcript_report(
        opts,
        read_findings,
        None,
        None,
        complete=false,
      )
    }
    raise CliError(
      "\{transcript.file} gives no JSON-RPC version; use --version 1.0 or --version 2.0",
      2,
    )
  }
  guard transcript_protocol(opts, assembled, version) is Some(protocol) else {
    return 2
  }
  let run = @rpc.run_transcript(
    protocol,
    document,
    read_findings,
    completeness?=transcript.completeness,
  )
  print_transcript_report(
    opts,
    run.findings,
    Some(run.summary),
    run.expectations,
    complete=run.summary.complete,
  )
}

///|
/// Prepares the --protocol structure for `version`. On a contract error it
/// reports the problem and gives `None`; the exit status is then 2.
fn transcript_protocol(
  opts : ValueOptions,
  assembled : @smithy.LoadResult,
  version : @rpc.ProtocolVersion,
) -> @rpc.ProtocolDescription? {
  let protocol = @rpc.ProtocolDescription::from_smithy(
    assembled.model.unwrap(),
    opts.target,
    version,
    config=opts.config,
  ) catch {
    @rpc.InvalidContract(id, message) => {
      ignore(
        value_problem(
          opts,
          "InvalidContract",
          id.to_string() + ": " + message,
          2,
          source=Some("--protocol"),
        ),
      )
      return None
    }
    @validation.UnsupportedConstraint(id, message) => {
      ignore(
        value_problem(
          opts,
          "UnsupportedConstraint",
          id.to_string() + ": " + message,
          2,
        ),
      )
      return None
    }
    error => {
      ignore(value_problem(opts, "InvalidConfiguration", error.to_string(), 2))
      return None
    }
  }
  Some(protocol)
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
/// one line per finding, then a summary line. Stdin is read in chunks; a file
/// is read whole.
fn run_log_transcript(
  opts : ValueOptions,
  transcript : TranscriptOptions,
  protocol : @rpc.ProtocolDescription,
  choice : LogChoice,
) -> Int32 raise {
  let reader = @rpc.LogReader::new(log_mapping(choice, protocol))
  // A log with one sender has no replies to correlate.
  let checker = @rpc.TranscriptChecker::new(
    protocol,
    completeness=transcript.completeness.unwrap_or(@rpc.Partial),
    correlation=!reader.single_sender(),
  )
  let output = FindingStream::new(opts)
  let chunks = Utf8Chunks::new()
  fn check(text : String) -> Unit raise {
    output.write_all(check_lines(reader.push_text(text), checker))
  }

  if transcript.file == "-" {
    read_stdin_chunks(bytes => check(chunks.push(bytes)))
  } else {
    let bytes = @fs.read_file_to_bytes(transcript.file) catch {
      _ =>
        return value_problem(
          opts, "InputRead", "I could not read the JSON-RPC transcript input.", 1,
        )
    }
    check(chunks.push(bytes))
  }
  check(chunks.end())
  output.write_all(check_lines(reader.end(), checker))
  let summary = checker.finish()
  output.write_all(summary.findings)
  output.finish(summary, reader.counts())
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
/// Lines to stdout. Each line is flushed.
priv struct FindingStream {
  opts : ValueOptions
  sink : OutputSink
  mut errors : Bool
}

///|
fn FindingStream::new(opts : ValueOptions) -> FindingStream raise {
  let sink = if opts.diagnostics == JsonFindings {
    output_sink(None)
  } else {
    stderr_sink()
  }
  { opts, sink, errors: false, }
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
/// Writes the summary line with the reader counts, and gives the exit status:
/// 0 when no finding is an error and no limit stopped a check.
fn FindingStream::finish(
  self : FindingStream,
  summary : @rpc.TranscriptSummary,
  counts : @rpc.LogCounts,
) -> Int32 raise {
  let valid = summary.complete && !self.errors
  let fields : Array[(String, Json)] = [
    ("valid", Json::boolean(valid)),
    ("complete", Json::boolean(summary.complete)),
    ("entries", Json::number(summary.entries.to_double())),
    ("outstanding", Json::number(summary.outstanding.to_double())),
    ("correlation", Json::boolean(summary.correlation)),
    ("lines", Json::number(counts.lines.to_double())),
    ("not_json", Json::number(counts.not_json.to_double())),
    ("skipped", Json::number(counts.skipped.to_double())),
  ]
  if self.opts.diagnostics == JsonFindings {
    self.line(
      Json::object({ "summary": Json::object(Map::from_array(fields)) }).stringify(),
    )
  } else {
    let text = fields.map(field => "\{field.0}:\{field.1.stringify()}")
    self.line("\{self.opts.file}: summary: \{text.join(" ")}")
  }
  if valid {
    0
  } else {
    1
  }
}

///|
/// Prints the findings and the expectation result, and gives the exit status:
/// with an expect list, 0 when it matches; otherwise 0 when no finding is an
/// error.
fn print_transcript_report(
  opts : ValueOptions,
  findings : Array[@rpc.TranscriptFinding],
  summary : @rpc.TranscriptSummary?,
  expectations : @rpc.ExpectationResult?,
  complete~ : Bool,
) -> Int32 {
  let valid = complete &&
    !findings.any(finding => finding.severity == @validation.Error)
  if opts.diagnostics == JsonFindings {
    let report : Map[String, Json] = {
      "valid": Json::boolean(valid),
      "complete": Json::boolean(complete),
      "entries": Json::number(
        summary.map(s => s.entries).unwrap_or(0).to_double(),
      ),
      "outstanding": Json::number(
        summary.map(s => s.outstanding).unwrap_or(0).to_double(),
      ),
      "correlation": Json::boolean(
        summary.map(s => s.correlation).unwrap_or(true),
      ),
      "findings": Json::array(findings.map(finding => @json.to_json(finding))),
    }
    if expectations is Some(result) {
      report["expectations"] = Json::object({
        "matched": Json::boolean(result.is_match()),
        "missing": Json::array(result.missing.map(expected_json)),
        "unexpected": Json::array(
          unexpected_errors(result).map(finding => @json.to_json(finding)),
        ),
      })
    }
    println(Json::object(report).stringify())
  } else {
    for finding in findings {
      eprintln(transcript_finding_text(opts.file, finding))
    }
    if expectations is Some(result) {
      for expected in result.missing {
        eprintln(
          "\{opts.file}: expect: I expected \{expected_text(expected)}; no finding matches it.",
        )
      }
      for finding in unexpected_errors(result) {
        eprintln(
          "\{transcript_finding_place(opts.file, finding)}: expect: I did not expect error \{finding.code.to_string()}.",
        )
      }
    }
  }
  let passed = match expectations {
    Some(result) => result.is_match()
    None => valid
  }
  if passed {
    0
  } else {
    1
  }
}

///|
/// The unlisted error findings. An unlisted advisory does not break the match,
/// so the report leaves it out.
fn unexpected_errors(
  result : @rpc.ExpectationResult,
) -> Array[@rpc.TranscriptFinding] {
  result.unexpected.filter(finding => finding.severity == @validation.Error)
}

///|
/// Renders the location and subject of a finding:
/// `<file>:<line>:<column>: entry <n> <sender>`, leaving out the parts that the
/// finding does not have.
fn transcript_finding_place(
  file : String,
  finding : @rpc.TranscriptFinding,
) -> String {
  let location = match finding.location {
    Some(at) => "\{file}:\{at.line}:\{at.column}"
    None => file
  }
  let subject = []
  if finding.entry is Some(entry) {
    subject.push("entry \{entry}")
  }
  if finding.sender is Some(sender) {
    subject.push(sender.to_string())
  }
  if subject.is_empty() {
    location
  } else {
    "\{location}: \{subject.join(" ")}"
  }
}

///|
fn transcript_finding_text(
  file : String,
  finding : @rpc.TranscriptFinding,
) -> String {
  let severity = if finding.severity == @validation.Error {
    "error"
  } else {
    "advisory"
  }
  "\{transcript_finding_place(file, finding)}: \{severity} \{finding.code.to_string()}: \{finding.message}"
}

///|
fn expected_text(expected : @rpc.ExpectedFinding) -> String {
  let entry = expected.entry().map(n => " at entry \{n}").unwrap_or("")
  let related = expected
    .related()
    .map(n => " related to entry \{n}")
    .unwrap_or("")
  "\{expected.code()}\{entry}\{related}"
}

///|
fn expected_json(expected : @rpc.ExpectedFinding) -> Json {
  fn number(n : Int32) -> Json {
    Json::number(n.to_double())
  }

  Json::object({
    "code": Json::string(expected.code()),
    "entry": expected.entry().map(number).unwrap_or(Json::null()),
    "related": expected.related().map(number).unwrap_or(Json::null()),
  })
}
