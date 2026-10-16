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
      #|exec zig cc -D_CRT_RAND_S "$@"
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
