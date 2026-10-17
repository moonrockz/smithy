///|
suberror CliError {
  CliError(String, Int32)
} derive(Debug)

///|
let usage : String =
  #|smithy: a Smithy toolchain for MoonBit
  #|
  #|Usage: smithy <command> [options] <file>...
  #|
  #|Commands:
  #|  ast         Assemble IDL/JSON files and print the Smithy JSON AST
  #|  validate    Assemble files and report model diagnostics
  #|  format      Format one IDL or JSON file to stdout
  #|  convert     Convert a model with --to json or --to idl
  #|  version     Print the version
  #|
  #|Options:
  #|  --from idl|json     Override input format (required for stdin '-')
  #|  --to idl|json       Output format for convert
  #|  -o, --output FILE   Write output to a file instead of stdout
  #|  --output-dir DIR    Write IDL files named <namespace>.smithy
  #|  --check             Check formatting without writing; exit 1 if changed
  #|  --write             Format files in place
  #|  -h, --help          Print help
  #|  --                  End options
  #|
  #|Inputs may mix .smithy and .json files. Use '-' once to read stdin.
  #|IDL conversion emits flattened Smithy 2 models; comments are not retained.

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
  guard args.length() > 0 else {
    raise CliError("expected a command; use --help", 2)
  }
  let command = args[0]
  guard ["ast", "validate", "format", "convert"].contains(command) else {
    raise CliError("unknown command '\{command}'; use --help", 2)
  }
  let files = []
  let mut from = None
  let mut to = None
  let mut output = None
  let mut output_dir = None
  let mut check = false
  let mut write = false
  let mut positional = false
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if !positional && arg == "--" {
      positional = true
    } else if !positional &&
      ["--from", "--to", "-o", "--output", "--output-dir"].contains(arg) {
      i += 1
      guard i < args.length() else {
        raise CliError("expected a value after \{arg}", 2)
      }
      let value = args[i]
      match arg {
        "--from" | "--to" => {
          guard value == "idl" || value == "json" else {
            raise CliError(
              "expected idl or json after \{arg}, found '\{value}'",
              2,
            )
          }
          if arg == "--from" {
            from = Some(value)
          } else {
            to = Some(value)
          }
        }
        "--output-dir" => output_dir = Some(value)
        _ => output = Some(value)
      }
    } else if !positional && (arg == "--help" || arg == "-h") {
      return {
        command: "help",
        files: [],
        from: None,
        to: None,
        output: None,
        output_dir: None,
        check: false,
        write: false,
      }
    } else if !positional && arg == "--check" {
      check = true
    } else if !positional && arg == "--write" {
      write = true
    } else if !positional && arg.has_prefix("-") && arg != "-" {
      raise CliError("unknown option '\{arg}'", 2)
    } else {
      files.push(arg)
    }
    i += 1
  }
  guard !files.is_empty() else {
    raise CliError("expected at least one input file", 2)
  }
  guard files.iter().filter(f => f == "-").count() <= 1 else {
    raise CliError("stdin '-' may only be read once", 2)
  }
  if files.contains("-") && from is None {
    raise CliError("use --from idl or --from json with stdin '-'", 2)
  }
  if command == "convert" && to is None {
    raise CliError("convert requires --to idl or --to json", 2)
  }
  if command != "convert" && to is Some(_) {
    raise CliError("--to requires convert", 2)
  }
  if (check || write) && command != "format" {
    raise CliError("--check and --write require format", 2)
  }
  if check && write {
    raise CliError("--check and --write cannot be combined", 2)
  }
  if (check || write) && output is Some(_) {
    raise CliError("--output cannot be combined with --check or --write", 2)
  }
  if write && files.contains("-") {
    raise CliError("--write requires file inputs", 2)
  }
  if command == "validate" && output is Some(_) {
    raise CliError("validate does not write output files", 2)
  }
  if output_dir is Some(_) &&
    (command != "convert" || to != Some("idl") || output is Some(_)) {
    raise CliError(
      "--output-dir requires convert --to idl and cannot be combined with --output",
      2,
    )
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
  if args.is_empty() || args == ["help"] || args == ["--help"] || args == ["-h"] {
    println(usage)
    return 0
  }
  if args == ["version"] || args == ["--version"] {
    println("smithy \{@smithy.version()} (Smithy \{@smithy.SMITHY_VERSION})")
    return 0
  }
  let opts = options(args)
  if opts.command == "help" {
    println(usage)
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
