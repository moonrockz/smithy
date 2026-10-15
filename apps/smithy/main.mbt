///|
fn main {
  let args = @env.args()
  match args {
    [_, "version", ..] | [_, "--version", ..] =>
      println("smithy \{@smithy.version()} (Smithy \{@smithy.SMITHY_VERSION})")
    _ => {
      println("smithy: a Smithy toolchain for MoonBit")
      println("")
      println("Usage: smithy <command>")
      println("")
      println("Commands:")
      println("  version    Print the version")
    }
  }
}
