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
        about="Input files; use '-' once to read stdin with --from. Use '--' before paths beginning with '-'.",
        num_args=@argparse.ValueRange(lower=1),
      ),
    ],
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
        about="Validate model definitions or JSON-RPC messages with the rpc subcommand.",
        options=[
          @argparse.OptionArg("from", about="Model format: idl or json."),
        ],
        positionals=[
          @argparse.PositionArg("file", num_args=@argparse.ValueRange(lower=0)),
        ],
        subcommands=[
          input_command(
            "rpc",
            "Validate one JSON-RPC 1.0 or 2.0 request or notification.",
            options=[
              @argparse.OptionArg(
                "version",
                required=true,
                about="Explicit JSON-RPC version: 1.0 or 2.0.",
              ),
              @argparse.OptionArg(
                "service",
                required=true,
                about="Absolute Smithy service ID.",
              ),
              @argparse.OptionArg(
                "message",
                required=true,
                about="JSON message file, or '-' for stdin.",
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
          ),
        ],
      ),
      input_command(
        "validate-value",
        "Validate a JSON value against a selected Smithy data shape.",
        options=[
          @argparse.OptionArg(
            "shape",
            about="Absolute Smithy data shape or member ID.",
            required=true,
          ),
          @argparse.OptionArg(
            "value",
            about="JSON value file, or '-' for stdin.",
            required=true,
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
  let rpc_mode = command == "validate" && matches.subcommand is Some(("rpc", _))
  // Model inputs and RPC inputs belong to distinct argparse scopes.
  if rpc_mode && !matches.values.get("file").unwrap_or([]).is_empty() {
    raise CliError("place model inputs after validate rpc", 2)
  }
  let matches = if rpc_mode { matches.subcommand.unwrap().1 } else { matches }
  fn value(name : String) -> String? {
    match matches.values.get(name) {
      Some([value, ..]) => Some(value)
      _ => None
    }
  }
  let files = matches.values.get("file").unwrap_or([])
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
  let rpc_version = if rpc_mode {
    guard @rpc.ProtocolVersion::parse(value("version").unwrap())
      is Some(version) else {
      raise CliError("expected 1.0 or 2.0 after --version", 2)
    }
    Some(version)
  } else {
    None
  }
  let value_validation = if command == "validate-value" || rpc_mode {
    let selector = if rpc_mode { "service" } else { "shape" }
    let raw_shape = value(selector).unwrap()
    guard @smithy.ShapeId::parse(raw_shape) is Some(target) else {
      raise CliError(
        "expected an absolute Smithy shape ID after --" + selector,
        2,
      )
    }
    let file = value(if rpc_mode { "message" } else { "value" }).unwrap()
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
    Some(ValueOptions::{
      target,
      file,
      diagnostics,
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
  let loader = if opts.rpc_version is Some(_) {
    @rpc.loader()
  } else {
    @smithy.Loader::new()
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
    if opts.rpc_version is Some(version) {
      return run_rpc_validation(value_opts, version, result)
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
