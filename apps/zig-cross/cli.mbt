///|
pub(all) enum Command {
  Build(target_dir~ : String, targets~ : Array[Target], paths~ : Array[String])
  Exec(target~ : Target, argv~ : Array[String])
  Help
  Version
} derive(Eq, Debug)

///|
/// The default value of `--target-dir`.
pub let default_target_dir : String = "_build/cross"

///|
pub fn help_text() -> String {
  (
    #|Usage:
    #|  zig-cross build [--target-dir DIR] <target>... [-- <path>...]
    #|  zig-cross exec <target> -- <command> <arg>...
    #|  zig-cross --help | --version
    #|
    #|build  Build the native release binaries for each target with `moon build`, check the
    #|       header of each executable, and print a summary. The wrappers go to DIR/zig/<target>.
    #|       DIR is "_build/cross" by default. The output of a target goes to DIR/<target>.
    #|exec   Run the command with MOON_CC and MOON_AR set to the wrappers of one target.
    #|
    #|Targets: linux-x64, linux-arm64, darwin-arm64, darwin-x64, windows-x64, host
    #|Zig 0.17.0 must be on PATH. zig-cross runs on Linux and macOS only.
  )
}

///|
fn parse_target(text : String) -> Result[Target, String] {
  match Target::parse(text) {
    Some(target) => Ok(target)
    None =>
      Err(
        "unknown target: \{text} (expected one of \{all_target_names().join(", ")})",
      )
  }
}

///|
fn parse_build(args : ArrayView[String]) -> Result[Command, String] {
  let mut target_dir = default_target_dir
  let targets : Array[Target] = []
  let paths : Array[String] = []
  let mut in_paths = false
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if in_paths {
      paths.push(arg)
    } else if arg == "--" {
      in_paths = true
    } else if arg == "--target-dir" {
      i += 1
      if i >= args.length() {
        return Err("give a directory after --target-dir")
      }
      target_dir = args[i]
    } else if arg.has_prefix("--target-dir=") {
      target_dir = arg[13:].to_owned()
    } else if arg.has_prefix("-") {
      return Err("unknown option: \{arg}")
    } else {
      match parse_target(arg) {
        Ok(target) => targets.push(target)
        Err(message) => return Err(message)
      }
    }
    i += 1
  }
  if targets.is_empty() {
    return Err("give at least one target")
  }
  Ok(Build(target_dir~, targets~, paths~))
}

///|
fn parse_exec(args : ArrayView[String]) -> Result[Command, String] {
  if args.is_empty() {
    return Err("give a target")
  }
  let target = match parse_target(args[0]) {
    Ok(target) => target
    Err(message) => return Err(message)
  }
  if args.length() < 3 || args[1] != "--" {
    return Err("give a command after --")
  }
  Ok(Exec(target~, argv=args[2:].to_owned()))
}

///|
/// Parse the arguments, without `argv[0]`.
pub fn parse_args(args : Array[String]) -> Result[Command, String] {
  if args.is_empty() {
    return Ok(Help)
  }
  match args[0] {
    "--help" | "-h" => Ok(Help)
    "--version" => Ok(Version)
    "build" => parse_build(args[1:])
    "exec" => parse_exec(args[1:])
    other => Err("unknown command: \{other} (expected build or exec)")
  }
}
