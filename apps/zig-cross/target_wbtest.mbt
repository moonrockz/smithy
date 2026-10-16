///|
test "zig_triple maps each target" {
  assert_eq(zig_triple(LinuxX64), Some("x86_64-linux-musl"))
  assert_eq(zig_triple(LinuxArm64), Some("aarch64-linux-musl"))
  assert_eq(zig_triple(DarwinArm64), Some("aarch64-macos"))
  assert_eq(zig_triple(DarwinX64), Some("x86_64-macos"))
  assert_eq(zig_triple(WindowsX64), Some("x86_64-windows-gnu"))
  assert_eq(zig_triple(Host), None)
}

///|
test "Target::parse accepts the six names and nothing else" {
  assert_eq(Target::parse("linux-x64"), Some(LinuxX64))
  assert_eq(Target::parse("linux-arm64"), Some(LinuxArm64))
  assert_eq(Target::parse("darwin-arm64"), Some(DarwinArm64))
  assert_eq(Target::parse("darwin-x64"), Some(DarwinX64))
  assert_eq(Target::parse("windows-x64"), Some(WindowsX64))
  assert_eq(Target::parse("host"), Some(Host))
  assert_eq(Target::parse("freebsd-x64"), None)
}

///|
test "Target::name is the inverse of parse" {
  for name in all_target_names() {
    assert_eq(Target::parse(name).map(fn(t) { t.name() }), Some(name))
  }
}

///|
test "cc_wrapper for a cross target sets the triple and the strip list" {
  let text = cc_wrapper(LinuxArm64)
  assert_true(text.has_prefix("#!/bin/sh\n"))
  assert_true(text.contains("zig cc -target aarch64-linux-musl -D_CRT_RAND_S"))
  assert_true(text.contains("-DMOONBIT_USE_SIMDUTF"))
  assert_true(text.contains("*/moonbit_simdutf.o"))
  assert_true(text.contains("*/simdutf.o"))
  assert_true(text.contains("*/libbacktrace.a"))
}

///|
test "cc_wrapper for the host strips nothing" {
  inspect(
    cc_wrapper(Host),
    content=(
      #|#!/bin/sh
      #|case "$(uname -s)" in Linux) unwind=-lunwind;; *) unwind=;; esac
      #|for a in "$@"; do case "$a" in -c) unwind=;; esac; done
      #|exec zig cc -D_CRT_RAND_S "$@" $unwind
      #|
    ),
  )
}

///|
test "ar_wrapper for a cross target strips the simdutf objects" {
  let text = ar_wrapper(DarwinX64)
  assert_true(text.has_prefix("#!/bin/sh\n"))
  assert_true(text.contains("*/moonbit_simdutf.o"))
  assert_true(text.contains("*/simdutf.o"))
  assert_true(text.contains("exec zig ar \"$@\""))
  assert_false(text.contains("libbacktrace"))
}

///|
test "ar_wrapper for the host strips nothing" {
  inspect(
    ar_wrapper(Host),
    content=(
      #|#!/bin/sh
      #|exec zig ar "$@"
      #|
    ),
  )
}

///|
/// Write `text` to `path`, replace `zig` by `echo`, run it with `args`, return stdout.
#cfg(target="native")
async fn run_wrapper(
  path : String,
  text : String,
  args : Array[String],
) -> String {
  let script = text.replace(old="exec zig", new="exec echo")
  @fs.write_file(path, script, permission=0o755)
  let out = @shell.Cmd("/bin/sh", [path, ..args]).output()
  out.stdout()
}

///|
#cfg(target="native")
async test "cc_wrapper drops the filtered arguments and keeps the order" {
  let dir = "_build/zig-cross-test"
  @fs.mkdir(dir, recursive=true, allow_exist=true)
  let out = run_wrapper(dir + "/cc", cc_wrapper(LinuxX64), [
    "-c", "a.c", "-DMOONBIT_USE_SIMDUTF", "x/moonbit_simdutf.o", "-O2", "y/simdutf.o",
    "z/libbacktrace.a", "-o", "out",
  ])
  inspect(
    out,
    content=(
      #|cc -target x86_64-linux-musl -D_CRT_RAND_S -c a.c -O2 -o out
      #|
    ),
  )
}

///|
#cfg(target="native")
async test "ar_wrapper drops the simdutf objects and keeps the order" {
  let dir = "_build/zig-cross-test"
  @fs.mkdir(dir, recursive=true, allow_exist=true)
  let out = run_wrapper(dir + "/ar", ar_wrapper(LinuxX64), [
    "rcs", "lib.a", "m.o", "p/moonbit_simdutf.o", "q/simdutf.o", "n.o",
  ])
  inspect(
    out,
    content=(
      #|ar rcs lib.a m.o n.o
      #|
    ),
  )
}

///|
/// Run the host `cc` wrapper with `uname` stubbed to print `os`. Return what the wrapper runs.
#cfg(target="native")
async fn run_host_wrapper(os : String, args : Array[String]) -> String {
  let dir = "_build/zig-cross-test/" + os
  @fs.mkdir(dir, recursive=true, allow_exist=true)
  @fs.write_file(
    dir + "/uname",
    "#!/bin/sh\necho " + os + "\n",
    permission=0o755,
  )
  @fs.chmod(dir + "/uname", 0o755)
  let cwd = @env.current_dir().unwrap_or(".")
  let script = cc_wrapper(Host).replace(old="exec zig", new="exec echo")
  @fs.write_file(dir + "/cc", script, permission=0o755)
  let env = { "PATH": cwd + "/" + dir + ":/usr/bin:/bin" }
  @shell.Cmd("/bin/sh", [dir + "/cc", ..args], env~).output().stdout()
}

///|
#cfg(target="native")
async test "host cc wrapper adds -lunwind only for Linux link steps" {
  assert_eq(
    run_host_wrapper("Linux", ["a.o", "-o", "out"]),
    "cc -D_CRT_RAND_S a.o -o out -lunwind\n",
  )
  assert_eq(
    run_host_wrapper("Linux", ["-c", "a.c", "-o", "a.o"]),
    "cc -D_CRT_RAND_S -c a.c -o a.o\n",
  )
  assert_eq(
    run_host_wrapper("Darwin", ["a.o", "-o", "out"]),
    "cc -D_CRT_RAND_S a.o -o out\n",
  )
}
