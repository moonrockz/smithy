///|
fn join(left : String, right : String) -> String {
  left + "/" + right
}

///|
/// moon runs `MOON_CC` and `MOON_AR` from other directories, so the paths must be absolute.
fn absolute(path : String) -> String {
  if path.has_prefix("/") {
    return path
  }
  match @env.current_dir() {
    Some(cwd) => join(cwd, path)
    None => path
  }
}

///|
async fn fail(message : String) -> Unit {
  @stdio.stderr.write("❌ zig-cross: \{message}\n")
  @sys.exit(1)
}

///|
async fn write_script(path : String, text : String) -> Unit {
  @fs.write_file(path, text, permission=0o755)
  // write_file applies the permission only when it creates the file.
  @fs.chmod(path, 0o755)
}

///|
/// Write the `cc` and `ar` wrappers of one target to `<target_dir>/zig/<target>`, and return the
/// environment that makes moon use them.
async fn prepare(target : Target, target_dir : String) -> Map[String, String] {
  let dir = absolute(join(join(target_dir, "zig"), target.name()))
  @fs.mkdir(dir, recursive=true, allow_exist=true)
  let cc = join(dir, "cc")
  let ar = join(dir, "ar")
  write_script(cc, cc_wrapper(target))
  write_script(ar, ar_wrapper(target))
  { "MOON_CC": cc, "MOON_AR": ar }
}

///|
/// One line of the summary: an executable that a build produced, or why there is none.
priv struct Row {
  target : Target
  path : String
  size : Int64
  problem : String?
}

///|
async fn check_executable(target : Target, path : String) -> Row {
  let size = @fs.file_size(path)
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let header = file.read_some(max_len=4096).unwrap_or(b"")
  { target, path, size, problem: check_format(target, header), }
}

///|
/// Build one target. The rows are the executables found, or one row with the problem.
async fn build_target(
  target : Target,
  target_dir : String,
  paths : Array[String],
) -> Array[Row] {
  let env = prepare(target, target_dir)
  let out = join(target_dir, target.name())
  let args = ["build", "--target", "native", "--release", "--target-dir", out]
  args.append(paths)
  println("🔨 Building for \{target.name()}...")
  let code = @shell.Cmd("moon", args, env~, stdout=Inherit, stderr=Inherit).status()
  if code != 0 {
    return [
      {
        target,
        path: out,
        size: 0L,
        problem: Some(
          "\{target.name()}: moon build failed with exit code \{code}",
        ),
      },
    ]
  }
  let found = @shell.glob(join(out, "native/release/build/**/*.exe"))
  if found.is_empty() {
    return [
      {
        target,
        path: out,
        size: 0L,
        problem: Some(
          "\{target.name()}: no executable under \{out}/native/release/build",
        ),
      },
    ]
  }
  found.sort()
  let rows = []
  for path in found {
    rows.push(check_executable(target, path))
  }
  rows
}

///|
fn max_int(a : Int32, b : Int32) -> Int32 {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn pad(text : String, width : Int32) -> String {
  let mut result = text
  while result.length() < width {
    result += " "
  }
  result
}

///|
/// Print the table (target, path, size, result) and the problems. Return the number of failures.
fn print_summary(rows : Array[Row]) -> Int32 {
  let mut target_width = 6
  let mut path_width = 4
  for row in rows {
    target_width = max_int(target_width, row.target.name().length())
    path_width = max_int(path_width, row.path.length())
  }
  println(
    "\{pad("target", target_width)}  \{pad("path", path_width)}  size (bytes)  result",
  )
  let mut failures = 0
  for row in rows {
    let mark = if row.problem is None { "✅" } else { "❌" }
    println(
      "\{pad(row.target.name(), target_width)}  \{pad(row.path, path_width)}  \{pad(row.size.to_string(), 12)}  \{mark}",
    )
    if row.problem is Some(message) {
      failures += 1
      println("  \{message}")
    }
  }
  failures
}

///|
async fn run_build(
  target_dir : String,
  targets : Array[Target],
  paths : Array[String],
) -> Int32 {
  let rows = []
  for target in targets {
    rows.append(build_target(target, target_dir, paths))
  }
  if print_summary(rows) > 0 {
    1
  } else {
    0
  }
}

///|
/// Run a command with `MOON_CC` and `MOON_AR` set to the wrappers of `target`.
async fn run_exec(target : Target, argv : Array[String]) -> Int32 {
  let env = prepare(target, default_target_dir)
  let code = @shell.Cmd(
    argv[0],
    argv[1:].to_owned(),
    env~,
    stdin=Inherit,
    stdout=Inherit,
    stderr=Inherit,
  ).status()
  if code > 0 {
    code
  } else if code == 0 {
    0
  } else {
    1
  }
}

///|
async fn main {
  if @env.get_env_var("OS") == Some("Windows_NT") {
    fail("zig-cross runs on Linux or macOS only")
    return
  }
  match parse_args(@env.args()[1:].to_owned()) {
    Err(message) => {
      @stdio.stderr.write("❌ zig-cross: \{message}\n\n\{help_text()}\n")
      @sys.exit(2)
    }
    Ok(Help) => @stdio.stdout.write(help_text() + "\n")
    Ok(Version) => @stdio.stdout.write(version_text() + "\n")
    Ok(Build(target_dir~, targets~, paths~)) => {
      let code = run_build(target_dir, targets, paths)
      if code != 0 {
        @sys.exit(code)
      }
    }
    Ok(Exec(target~, argv~)) => {
      let code = run_exec(target, argv)
      if code != 0 {
        @sys.exit(code)
      }
    }
  }
}
