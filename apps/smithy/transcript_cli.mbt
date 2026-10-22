///|
/// The encoding of a transcript input.
priv enum TranscriptFormat {
  JsonTranscript
  MarkdownTranscript
  JsonlTranscript
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
}

///|
fn transcript_command() -> @argparse.Command {
  input_command(
    "transcript",
    "Validate a JSON-RPC transcript between the two peers of a protocol. JSON and Markdown documents; JSONL is not supported yet.",
    files_about="Model files, then the transcript file or '-' for stdin. Use '--' before paths beginning with '-'.",
    options=[
      @argparse.OptionArg(
        "protocol",
        about="Absolute ID of the @jsonRpcProtocol structure.",
        required=true,
      ),
      @argparse.OptionArg(
        "version",
        about="JSON-RPC version: 1.0 or 2.0. Required when the transcript does not give it.",
      ),
      @argparse.OptionArg(
        "input-format",
        about="Transcript format: json, markdown or jsonl; default from .json, .md, .jsonl or .ndjson, and jsonl for stdin. Only json and markdown are supported now.",
      ),
      @argparse.OptionArg(
        "diagnostics",
        about="Findings format: text or json; default text.",
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
  match format {
    JsonTranscript | MarkdownTranscript => ()
    JsonlTranscript =>
      raise CliError(
        "I cannot read JSONL transcripts yet; use JSON, with --input-format json for stdin",
        2,
      )
  }
  { file, format, version, completeness, }
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
) -> Int32 raise CliError {
  if !validation_model_ok(opts, assembled) {
    return 1
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
    // A document that I could not read may have lost its version; its
    // findings explain the problem better than a usage error.
    if !read_findings.is_empty() {
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
  let protocol = @rpc.ProtocolDescription::from_smithy(
    assembled.model.unwrap(),
    opts.target,
    version,
    config=opts.config,
  ) catch {
    @rpc.InvalidContract(id, message) =>
      return value_problem(
        opts,
        "InvalidContract",
        id.to_string() + ": " + message,
        2,
        source=Some("--protocol"),
      )
    @validation.UnsupportedConstraint(id, message) =>
      return value_problem(
        opts,
        "UnsupportedConstraint",
        id.to_string() + ": " + message,
        2,
      )
    error =>
      return value_problem(opts, "InvalidConfiguration", error.to_string(), 2)
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
