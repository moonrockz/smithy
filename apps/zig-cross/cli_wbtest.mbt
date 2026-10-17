///|
test "parse_args build with targets and paths" {
  assert_eq(
    parse_args(["build", "linux-x64", "darwin-arm64", "--", "apps/myapp"]),
    Ok(
      Build(target_dir="_build/cross", targets=[LinuxX64, DarwinArm64], paths=[
        "apps/myapp",
      ]),
    ),
  )
}

///|
test "parse_args build with a target dir" {
  assert_eq(
    parse_args(["build", "--target-dir", "out", "host"]),
    Ok(Build(target_dir="out", targets=[Host], paths=[])),
  )
  assert_eq(
    parse_args(["build", "host", "--target-dir=out2"]),
    Ok(Build(target_dir="out2", targets=[Host], paths=[])),
  )
}

///|
test "parse_args build errors" {
  assert_eq(parse_args(["build"]), Err("give at least one target"))
  assert_eq(
    parse_args(["build", "nope"]),
    Err(
      "unknown target: nope (expected one of linux-x64, linux-arm64, darwin-arm64, darwin-x64, windows-x64, host)",
    ),
  )
  assert_eq(
    parse_args(["build", "--target-dir"]),
    Err("give a directory after --target-dir"),
  )
  assert_eq(
    parse_args(["build", "--bogus", "host"]),
    Err("unknown option: --bogus"),
  )
}

///|
test "parse_args exec" {
  assert_eq(
    parse_args(["exec", "host", "--", "moon", "test"]),
    Ok(Exec(target=Host, argv=["moon", "test"])),
  )
  assert_eq(parse_args(["exec", "host"]), Err("give a command after --"))
  assert_eq(parse_args(["exec", "host", "--"]), Err("give a command after --"))
  assert_eq(parse_args(["exec"]), Err("give a target"))
}

///|
test "parse_args flags and unknown commands" {
  assert_eq(parse_args(["--version"]), Ok(Version))
  assert_eq(parse_args(["--help"]), Ok(Help))
  assert_eq(parse_args([]), Ok(Help))
  assert_eq(
    parse_args(["frobnicate"]),
    Err("unknown command: frobnicate (expected build or exec)"),
  )
}

///|
test "version text" {
  inspect(version_text(), content="zig-cross 0.1.1")
}
