///|
suberror CliError {
  CliError(String, Int32)
} derive(Debug)

///|
fn version_text() -> String {
  "smithy \{@smithy.version()} (Smithy \{@smithy.SMITHY_VERSION})"
}

///|
fn input_command(
  name : String,
  about : String,
  options~ : Array[@argparse.OptionArg] = [],
  flags~ : Array[@argparse.FlagArg] = [],
  subcommands~ : Array[@argparse.Command] = [],
  files_about~ : String = "Input files; use '-' once to read stdin with --from. Use '--' before paths beginning with '-'.",
) -> @argparse.Command {
  @argparse.Command(
    name,
    about~,
    flags~,
    options=[
        @argparse.OptionArg(
          "from",
          about="Input format: idl or json. Required for stdin; otherwise inferred from .smithy or .json.",
        ),
      ] +
      options,
    positionals=[
      @argparse.PositionArg(
        "file",
        about=files_about,
        // A nested command does not satisfy its parent's inputs, so a parent
        // with subcommands checks its own inputs after parsing.
        num_args=@argparse.ValueRange(
          lower=if subcommands.is_empty() { 1 } else { 0 },
        ),
      ),
    ],
    subcommands~,
  )
}

///|
fn command_line() -> @argparse.Command {
  let output = @argparse.OptionArg(
    "output",
    short='o',
    about="Write output to a file instead of stdout.",
  )
  @argparse.Command(
    "smithy",
    about="A Smithy toolchain for MoonBit: assemble, validate, select, diff, format and convert models.",
    version=version_text(),
    arg_required_else_help=true,
    subcommand_required=true,
    subcommands=[
      input_command(
        "ast",
        "Assemble IDL/JSON files and print the Smithy JSON AST.",
        options=[output],
      ),
      @argparse.Command(
        "validate",
        about="Validate model definitions, JSON or Ion values, or JSON-RPC messages.",
        flags=[
          @argparse.FlagArg(
            "protocol-tests",
            about="Load the bundled smithy.test protocol-test traits.",
          ),
        ],
        options=[
          @argparse.OptionArg("from", about="Model format: idl or json."),
        ],
        positionals=[
          @argparse.PositionArg("file", num_args=@argparse.ValueRange(lower=0)),
        ],
        subcommands=[
          input_command(
            "value",
            "Validate a JSON or Ion value against a selected Smithy data shape.",
            options=[
              @argparse.OptionArg(
                "shape",
                about="Absolute Smithy data shape or member ID.",
                required=true,
              ),
              @argparse.OptionArg(
                "value",
                about="Value file, or '-' for stdin.",
                required=true,
              ),
              @argparse.OptionArg(
                "input-format",
                about="Value encoding: json, ion-text or ion-binary; default json.",
              ),
              @argparse.OptionArg(
                "ion-index",
                about="Select a zero-based Ion datagram value; otherwise require exactly one value.",
              ),
              @argparse.OptionArg(
                "diagnostics",
                about="Findings format: text or json; default text.",
              ),
              @argparse.OptionArg(
                "unknown-members",
                about="Unknown structure member policy: reject or ignore; default reject.",
              ),
              @argparse.OptionArg(
                "member-names",
                about="Member naming: smithy or json; default smithy.",
              ),
            ],
          ),
          input_command(
            "rpc",
            "Validate JSON-RPC requests, notifications, responses or explicit 2.0 batches.",
            subcommands=[transcript_command()],
            options=[
              // argparse checks a parent's required options even when a
              // subcommand is named, so options() checks these two instead.
              @argparse.OptionArg(
                "version",
                about="Explicit JSON-RPC version: 1.0 or 2.0. Required.",
              ),
              @argparse.OptionArg(
                "service",
                about="Absolute Smithy service ID. Required.",
              ),
              @argparse.OptionArg(
                "message",
                about="Request/notification JSON file, or '-' for stdin.",
              ),
              @argparse.OptionArg(
                "response",
                about="Response JSON file, or '-' for stdin; replaces --message.",
              ),
              @argparse.OptionArg(
                "request",
                about="Original request JSON file, or '-' for stdin; response context.",
              ),
              @argparse.OptionArg(
                "method",
                about="Explicit wire method for response payload validation.",
              ),
              @argparse.OptionArg(
                "operation",
                about="Explicit Smithy operation ID for response payload validation.",
              ),
              @argparse.OptionArg(
                "legacy-errors",
                about="1.0 response error mapping: opaque or code-message-data; default opaque.",
              ),
              @argparse.OptionArg(
                "diagnostics",
                about="Findings format: text or json; default text.",
              ),
              @argparse.OptionArg(
                "unknown-members",
                about="Payload unknown members: reject or ignore; default reject.",
              ),
              @argparse.OptionArg(
                "member-names",
                about="Payload member names: smithy or json; default smithy.",
              ),
            ],
            flags=[
              @argparse.FlagArg(
                "batch",
                about="Validate a complete JSON-RPC 2.0 request or response batch.",
              ),
              @argparse.FlagArg(
                "no-response",
                about="Validate absent batch response; requires --batch and --request.",
              ),
              @argparse.FlagArg(
                "envelope-only",
                about="Check response envelope only; no modeled payload or ID correlation.",
              ),
            ],
          ),
        ],
      ),
      @argparse.Command(
        "diff",
        about="Compare two model files or directories and report compatibility changes.",
        options=[
          @argparse.OptionArg(
            "old",
            about="Old Smithy model file or directory.",
            required=true,
          ),
          @argparse.OptionArg(
            "new",
            about="New Smithy model file or directory.",
            required=true,
          ),
          @argparse.OptionArg(
            "format",
            about="Output format: text (default) or jsonl. JSONL flushes each stdout record after comparison.",
          ),
          output,
        ],
      ),
      @argparse.Command(
        "build",
        about="Run projections from smithy-build.json.",
        flags=[
          @argparse.FlagArg(
            "offline",
            about="Use only verified cached remote artifacts.",
          ),
        ],
        options=[
          @argparse.OptionArg(
            "cache-dir",
            about="Artifact cache directory, relative to the configuration file.",
          ),
          @argparse.OptionArg(
            "config",
            short='c',
            about="Build configuration file.",
          ),
        ],
      ),
      @argparse.Command(
        "clean",
        about="Remove the configured build output directory.",
        options=[
          @argparse.OptionArg(
            "config",
            short='c',
            about="Build configuration file.",
          ),
        ],
      ),
      input_command(
        "select",
        "Print matching absolute shape IDs, one per line.",
        options=[
          @argparse.OptionArg(
            "selector",
            about="Smithy selector expression.",
            required=true,
          ),
        ],
      ),
      input_command(
        "format",
        "Format IDL/JSON files. By default, print one file to stdout.",
        options=[output],
        flags=[
          @argparse.FlagArg(
            "check",
            about="Check formatting without writing; exit 1 if changed.",
            conflicts_with=["write", "output"],
          ),
          @argparse.FlagArg("write", about="Format files in place.", conflicts_with=[
            "output",
          ]),
        ],
      ),
      input_command(
        "convert",
        "Convert a model to JSON or flattened Smithy 2 IDL. IDL conversion does not retain comments.",
        options=[
          @argparse.OptionArg(
            "to",
            about="Output format: idl or json.",
            required=true,
          ),
          output,
          @argparse.OptionArg(
            "output-dir",
            about="Write IDL files named <namespace>.smithy; requires --to idl.",
            conflicts_with=["output"],
          ),
        ],
      ),
      @argparse.Command("version", about="Print the version."),
    ],
  )
}

///|
struct Options {
  command : String
  files : Array[String]
  from : String?
  to : String?
  selector : String?
  old_model : String?
  new_model : String?
  diff_format : DiffFormat
  value_validation : ValueOptions?
  rpc_version : @rpc.ProtocolVersion?
  protocol_tests : Bool
  rpc_options : RpcOptions?
  transcript : TranscriptOptions?
  offline : Bool
  cache_dir : String?
  config : String?
  output : String?
  output_dir : String?
  check : Bool
  write : Bool
}

///|
fn options(args : Array[String]) -> Options raise CliError {
  let parsed = command_line().parse(argv=args) catch {
    error => raise CliError(error.to_string(), 2)
  }
  guard parsed.subcommand is Some((command, matches)) else {
    raise CliError("expected a command; use --help", 2)
  }
  let validation_command = if command == "validate" {
    matches.subcommand
  } else {
    None
  }
  let transcript_mode = validation_command
    is Some(("rpc", { subcommand: Some(("transcript", _)), .. }))
  let rpc_mode = validation_command is Some(("rpc", _)) && !transcript_mode
  let value_mode = validation_command is Some(("value", _))
  // Model inputs belong to the selected validation command's argparse scope.
  if validation_command is Some((name, _)) &&
    (
      !matches.values.get("file").unwrap_or([]).is_empty() ||
      matches.values.contains("from") ||
      matches.flags.get("protocol-tests") == Some(true)
    ) {
    raise CliError("place model inputs and options after validate " + name, 2)
  }
  let matches = match validation_command {
    Some((_, nested)) => nested
    None => matches
  }
  let matches = match matches.subcommand {
    Some(("transcript", nested)) if transcript_mode => {
      if !matches.values.is_empty() || matches.flags.values().any(set => set) {
        raise CliError(
          "place model inputs and options after validate rpc transcript", 2,
        )
      }
      nested
    }
    _ => matches
  }
  fn value(name : String) -> String? {
    match matches.values.get(name) {
      Some([value, ..]) => Some(value)
      _ => None
    }
  }
  let (files, transcript) = if transcript_mode {
    let inputs = matches.values.get("file").unwrap_or([])
    guard inputs.length() >= 2 else {
      raise CliError(
        "validate rpc transcript requires model inputs and then a transcript file or '-'",
        2,
      )
    }
    let file = inputs[inputs.length() - 1]
    (
      inputs[:inputs.length() - 1].to_owned(),
      Some(
        transcript_options(
          file,
          value,
          matches.flags,
          directions=matches.values.get("direction").unwrap_or([]),
        ),
      ),
    )
  } else {
    (matches.values.get("file").unwrap_or([]), None)
  }
  if command == "validate" && files.is_empty() {
    raise CliError("validate requires model inputs; use validate --help", 2)
  }
  let from = value("from")
  let to = value("to")
  let selector = value("selector")
  let config = value("config")
  let output = value("output")
  let output_dir = value("output-dir")
  let diff_format = DiffFormat::parse(value("format").unwrap_or("text"))
  let check = matches.flags.get("check") == Some(true)
  let write = matches.flags.get("write") == Some(true)
  if rpc_mode {
    for name in ["version", "service"] {
      if value(name) is None {
        raise CliError("validate rpc requires --" + name, 2)
      }
    }
  }
  let rpc_version = if rpc_mode {
    guard @rpc.ProtocolVersion::parse(value("version").unwrap())
      is Some(version) else {
      raise CliError("expected 1.0 or 2.0 after --version", 2)
    }
    Some(version)
  } else {
    None
  }
  let rpc_options = if rpc_mode {
    let response = value("response")
    let request = value("request")
    let method_ = value("method")
    let operation = value("operation")
    let envelope = matches.flags.get("envelope-only") == Some(true)
    let batch = matches.flags.get("batch") == Some(true)
    let no_response = matches.flags.get("no-response") == Some(true)
    if no_response && (!batch || request is None) {
      raise CliError("--no-response requires --batch and --request", 2)
    }
    let inputs = (if value("message") is Some(_) { 1 } else { 0 }) +
      (if response is Some(_) { 1 } else { 0 }) +
      (if no_response { 1 } else { 0 })
    if inputs != 1 {
      raise CliError(
        "use exactly one of --message, --response and --no-response", 2,
      )
    }
    let contexts = (if request is Some(_) { 1 } else { 0 }) +
      (if method_ is Some(_) { 1 } else { 0 }) +
      (if operation is Some(_) { 1 } else { 0 }) +
      (if envelope { 1 } else { 0 })
    if contexts > 1 {
      raise CliError(
        "use only one response context: --request, --method, --operation or --envelope-only",
        2,
      )
    }
    if response is None &&
      !no_response &&
      (contexts > 0 || value("legacy-errors") is Some(_)) {
      raise CliError(
        "response context and --legacy-errors require --response", 2,
      )
    }
    let legacy_errors = match value("legacy-errors").unwrap_or("opaque") {
      "opaque" => @rpc.Opaque
      "code-message-data" => @rpc.CodeMessageData
      _ =>
        raise CliError(
          "expected opaque or code-message-data after --legacy-errors", 2,
        )
    }
    if value("legacy-errors") is Some(_) && rpc_version != Some(@rpc.V1_0) {
      raise CliError("--legacy-errors requires version 1.0", 2)
    }
    let context = if method_ is Some(name) {
      guard @rpc.MethodName::parse(name) is Some(name) else {
        raise CliError("expected an application method name after --method", 2)
      }
      Some(@rpc.Method(name))
    } else if operation is Some(id) {
      guard @smithy.ShapeId::parse(id) is Some(id) && id.member_name() is None else {
        raise CliError("expected an absolute operation ID after --operation", 2)
      }
      Some(@rpc.Operation(id))
    } else if envelope {
      Some(@rpc.EnvelopeOnly)
    } else {
      None
    }
    if request == Some("-") && (response == Some("-") || files.contains("-")) {
      raise CliError(
        "stdin '-' may only be read once across model, response and request inputs",
        2,
      )
    }
    Some(RpcOptions::{
      response: response is Some(_) || no_response,
      batch,
      no_response,
      request,
      context,
      legacy_errors,
    })
  } else {
    None
  }
  let value_validation = if value_mode || rpc_mode || transcript_mode {
    let selector = if rpc_mode {
      "service"
    } else if transcript_mode {
      "protocol"
    } else {
      "shape"
    }
    let raw_shape = value(selector).unwrap()
    guard @smithy.ShapeId::parse(raw_shape) is Some(target) &&
      (!transcript_mode || target.member_name() is None) else {
      raise CliError(
        "expected an absolute Smithy shape ID after --" + selector,
        2,
      )
    }
    let file = if rpc_mode {
      match value("response") {
        Some(file) => file
        None => value("message").unwrap_or("<no response>")
      }
    } else if transcript is Some(transcript) {
      transcript.file
    } else {
      value("value").unwrap()
    }
    let diagnostics = match value("diagnostics").unwrap_or("text") {
      "text" => TextFindings
      "json" => JsonFindings
      _ => raise CliError("expected text or json after --diagnostics", 2)
    }
    let unknown_members = match value("unknown-members").unwrap_or("reject") {
      "reject" => @validation.Reject
      "ignore" => @validation.Ignore
      _ =>
        raise CliError("expected reject or ignore after --unknown-members", 2)
    }
    let member_names = match value("member-names").unwrap_or("smithy") {
      "smithy" => @validation.Smithy
      "json" => @validation.JsonName
      _ => raise CliError("expected smithy or json after --member-names", 2)
    }
    if file == "-" && files.contains("-") {
      raise CliError(
        "stdin '-' may only be read once across model and value inputs", 2,
      )
    }
    // The transcript command reads --input-format in transcript_options.
    let value_format = if transcript_mode {
      None
    } else {
      value("input-format")
    }
    let input_format = match value_format.unwrap_or("json") {
      "json" => JsonInput
      "ion-text" => IonTextInput
      "ion-binary" => IonBinaryInput
      _ =>
        raise CliError(
          "expected json, ion-text or ion-binary after --input-format", 2,
        )
    }
    let ion_index = match value("ion-index") {
      None => None
      Some(text) => {
        guard input_format != JsonInput else {
          raise CliError("--ion-index requires an Ion --input-format", 2)
        }
        guard !text.is_empty() && text.iter().all(c => c >= '0' && c <= '9') else {
          raise CliError("expected a nonnegative integer after --ion-index", 2)
        }
        let index = @string.parse_int(text) catch {
          _ =>
            raise CliError(
              "expected a nonnegative integer after --ion-index", 2,
            )
        }
        Some(index)
      }
    }
    Some(ValueOptions::{
      target,
      file,
      diagnostics,
      input_format,
      ion_index,
      config: @validation.Config::new(unknown_members~, member_names~),
    })
  } else {
    None
  }
  for (name, format) in [("--from", from), ("--to", to)] {
    if format is Some(format) && format != "idl" && format != "json" {
      raise CliError("expected idl or json after \{name}, found '\{format}'", 2)
    }
  }
  guard files.iter().filter(f => f == "-").count() <= 1 else {
    raise CliError("stdin '-' may only be read once", 2)
  }
  if files.contains("-") && from is None {
    raise CliError("use --from idl or --from json with stdin '-'", 2)
  }
  if write && files.contains("-") {
    raise CliError("--write requires file inputs", 2)
  }
  if output_dir is Some(_) && to != Some("idl") {
    raise CliError("--output-dir requires convert --to idl", 2)
  }
  if command == "format" && files.length() > 1 && !check && !write {
    raise CliError("use --check or --write when formatting multiple files", 2)
  }
  {
    offline: matches.flags.get("offline") == Some(true),
    cache_dir: value("cache-dir"),
    old_model: value("old"),
    new_model: value("new"),
    diff_format,
    value_validation,
    rpc_version,
    protocol_tests: matches.flags.get("protocol-tests") == Some(true),
    rpc_options,
    transcript,
    command,
    files,
    from,
    to,
    selector,
    config,
    output,
    output_dir,
    check,
    write,
  }
}

///|
fn input_format(name : String, override_ : String?) -> String raise CliError {
  if override_ is Some(format) {
    return format
  }
  if name.has_suffix(".smithy") {
    "idl"
  } else if name.has_suffix(".json") {
    "json"
  } else {
    raise CliError(
      "cannot infer the format of '\{name}'; use --from idl or --from json",
      2,
    )
  }
}

///|
fn diagnostic(
  d : @smithy.ModelDiagnostic,
  inputs : Map[String, String],
) -> String {
  let severity = if d.severity == Error { "error" } else { "warning" }
  let source = d.source
  let location = if source.span is Some(span) &&
    inputs.get(source.file) is Some(text) {
    let position = @syntax.SourceText::new(text).position(span.start)
    "\{source.file}:\{position.line.0}:\{position.column.0}"
  } else {
    source.file + source.path
  }
  "\{location}: \{severity}[\{d.code}]: \{d.message}"
}

///|
fn validation_event_text(event : @smithy.ValidationEvent) -> String {
  let shape = match event.shape {
    Some(id) => id.to_string()
    None => "-"
  }
  "[\{event.severity}] \{shape}: \{event.message} | \{event.id}"
}

///|
fn json_output(model : @smithy.Model) -> String raise {
  @syntax.encode_json_ast(model.to_json_ast()).stringify(indent=4) + "\n"
}

///|
fn emit(text : String, path : String?) -> Unit raise {
  match path {
    Some(path) => @fs.write_string_to_file(path, text)
    None =>
      if !text.is_empty() {
        println(
          if text.has_suffix("\n") {
            text[:text.length() - 1]
          } else {
            text[:]
          },
        )
      }
  }
}

///|
fn run(args : Array[String]) -> Int32 raise {
  let opts = options(args)
  if opts.command == "version" {
    println(version_text())
    return 0
  }
  if opts.command == "diff" {
    return run_diff(
      opts.old_model.unwrap(),
      opts.new_model.unwrap(),
      opts.output,
      opts.diff_format,
    )
  }
  if opts.command == "build" || opts.command == "clean" {
    return run_build(
      opts.config.unwrap_or("smithy-build.json"),
      opts.command == "clean",
      offline=opts.offline,
      cache_dir=opts.cache_dir,
    ) catch {
      @build.InvalidBuildConfig(message) => raise CliError(message, 1)
      error => raise error
    }
  }
  let loader = if opts.rpc_version is Some(_) || opts.transcript is Some(_) {
    @rpc.loader()
  } else {
    @smithy.Loader::new(protocol_tests=opts.protocol_tests)
  }
  let inputs : Map[String, String] = Map([])
  let formatted : Array[(String, String)] = []
  let mut failed = false
  for name in opts.files {
    let format = input_format(name, opts.from)
    let text = if opts.value_validation is Some(value_opts) {
      try {
        if name == "-" {
          read_stdin()
        } else {
          @fs.read_file_to_string(name)
        }
      } catch {
        _ =>
          return value_problem(
            value_opts,
            "InputRead",
            "I could not read the model input.",
            1,
            source=Some(name),
          )
      }
    } else if name == "-" {
      read_stdin()
    } else {
      @fs.read_file_to_string(name)
    }
    inputs[name] = text
    if opts.command == "format" {
      let result = format_text(text, name, format) catch {
        CliError(message, _) => {
          eprintln(message)
          failed = true
          continue
        }
      }
      formatted.push((name, result))
    } else if format == "idl" {
      ignore(loader.add_idl(name, text))
    } else {
      ignore(loader.add_json(name, text))
    }
  }
  if opts.command == "format" {
    // Validate every input before changing any file.
    if failed {
      return 1
    }
    for (name, result) in formatted {
      if opts.check {
        if inputs.get(name) != Some(result) {
          eprintln("\{name}: formatting differs")
          failed = true
        }
      } else if opts.write {
        @fs.write_string_to_file(name, result)
      } else {
        emit(result, opts.output)
      }
    }
    return if failed { 1 } else { 0 }
  }
  let result = loader.assemble()
  if opts.value_validation is Some(value_opts) {
    if opts.transcript is Some(transcript) {
      return run_transcript_validation(value_opts, transcript, result)
    }
    if opts.rpc_version is Some(version) {
      return run_rpc_validation(
        value_opts,
        version,
        opts.rpc_options.unwrap(),
        result,
      )
    }
    return run_value_validation(value_opts, result)
  }
  if opts.command == "validate" {
    let mut failed = result.model is None
    for event in result.validation_events() {
      if event.severity == "DANGER" || event.severity == "ERROR" {
        failed = true
      }
      if event.severity == "WARNING" ||
        event.severity == "DANGER" ||
        event.severity == "ERROR" {
        eprintln(validation_event_text(event))
      }
    }
    return if failed { 1 } else { 0 }
  }
  for d in result.diagnostics {
    eprintln(diagnostic(d, inputs))
  }
  guard result.model is Some(model) else { return 1 }
  if opts.command == "select" {
    guard opts.selector is Some(expression) else {
      raise CliError("select requires --selector", 2)
    }
    let selector = @smithy.Selector::parse(expression) catch {
      @smithy.InvalidSelector(message) => raise CliError(message, 2)
    }
    let ids = selector.select_ids(model)
    emit(if ids.is_empty() { "" } else { ids.join("\n") + "\n" }, None)
    return 0
  }
  if opts.to != Some("idl") {
    emit(json_output(model), opts.output)
    return 0
  }
  let files = model.to_idl()
  if opts.output_dir is Some(dir) {
    if !@fs.path_exists(dir) {
      @fs.create_dir(dir)
    }
    let namespaces = files.keys().to_array()
    namespaces.sort()
    for ns in namespaces {
      let filename = if ns == "" { "model" } else { ns }
      @fs.write_string_to_file(
        "\{dir}/\{filename}.smithy",
        files.get(ns).unwrap(),
      )
    }
  } else {
    guard files.length() == 1 else {
      raise CliError("model has multiple namespaces; use --output-dir DIR", 2)
    }
    for _, text in files {
      emit(text, opts.output)
    }
  }
  0
}

///|
fn read_stdin() -> String raise {
  @utf8.decode(stdin_bytes())
}

///|
/// Decodes UTF-8 that arrives in chunks. An incomplete sequence at the end of a
/// chunk waits for the next chunk, so a character split between two reads
/// decodes once. Invalid bytes become U+FFFD; nothing panics.
priv struct Utf8Chunks {
  /// The start of a sequence that the last chunk did not finish: 0 to 3 bytes.
  mut held : Bytes
}

///|
fn Utf8Chunks::new() -> Utf8Chunks {
  { held: b"", }
}

///|
/// Gives the text of every sequence that is complete after `chunk`.
fn Utf8Chunks::push(self : Utf8Chunks, chunk : Bytes) -> String {
  let bytes = if self.held.length() == 0 { chunk } else { self.held + chunk }
  let keep = incomplete_utf8_tail(bytes)
  let end = bytes.length() - keep
  self.held = bytes[end:].to_owned()
  @utf8.decode_lossy(bytes[:end])
}

///|
/// Gives the held bytes at end of input, as U+FFFD.
fn Utf8Chunks::end(self : Utf8Chunks) -> String {
  let held = self.held
  self.held = b""
  @utf8.decode_lossy(held)
}

///|
/// The number of bytes at the end of `bytes` that start a UTF-8 sequence but do
/// not finish it. Earlier bytes end on a sequence boundary, so they decode the
/// same alone as with the bytes that follow.
fn incomplete_utf8_tail(bytes : Bytes) -> Int32 {
  let n = bytes.length()
  for back in 1..<=3 {
    if back > n {
      return 0
    }
    let lead = bytes[n - back].to_int()
    if (lead & 0xC0) == 0x80 {
      // A continuation byte: look further back for its lead byte.
      continue
    }
    let length = if lead >= 0xC2 && lead <= 0xDF {
      2
    } else if lead >= 0xE0 && lead <= 0xEF {
      3
    } else if lead >= 0xF0 && lead <= 0xF4 {
      4
    } else {
      1
    }
    return if back < length { back } else { 0 }
  }
  0
}
