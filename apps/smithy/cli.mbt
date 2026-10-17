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
    about="A Smithy toolchain for MoonBit: assemble, validate, format and convert models.",
    version=version_text(),
    arg_required_else_help=true,
    subcommand_required=true,
    subcommands=[
      input_command(
        "ast",
        "Assemble IDL/JSON files and print the Smithy JSON AST.",
        options=[output],
      ),
      input_command("validate", "Assemble files and report model diagnostics."),
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
  fn value(name : String) -> String? {
    match matches.values.get(name) {
      Some([value, ..]) => Some(value)
      _ => None
    }
  }
  let files = matches.values.get("file").unwrap_or([])
  let from = value("from")
  let to = value("to")
  let output = value("output")
  let output_dir = value("output-dir")
  let check = matches.flags.get("check") == Some(true)
  let write = matches.flags.get("write") == Some(true)
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
  { command, files, from, to, output, output_dir, check, write, }
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
  let loader = @smithy.Loader::new()
  let inputs : Map[String, String] = Map([])
  let formatted : Array[(String, String)] = []
  let mut failed = false
  for name in opts.files {
    let format = input_format(name, opts.from)
    let text = if name == "-" {
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
  for d in result.diagnostics {
    eprintln(diagnostic(d, inputs))
  }
  guard result.model is Some(model) else { return 1 }
  if opts.command == "validate" {
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
