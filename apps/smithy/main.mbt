///|
fn main {
  let status = run(program_args()) catch {
    CliError(message, code) => {
      cli_stderr("smithy: \{message}")
      code
    }
    error => {
      cli_stderr("smithy: \{error}")
      1
    }
  }
  if status != 0 {
    @sys.exit(status)
  }
}

///|
#cfg(target="js")
fn program_args() -> Array[String] {
  @env.args()[2:].to_owned()
}

///|
#cfg(not(target="js"))
fn program_args() -> Array[String] {
  @env.args()[1:].to_owned()
}
