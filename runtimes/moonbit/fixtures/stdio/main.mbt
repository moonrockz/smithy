///|
/// Native child-process fixture for the runtime's stdio tests.
async fn main {
  let args = @env.args()
  match args.get(1) {
    Some("echo") => @sys_stdio.stdout.write_reader(@sys_stdio.stdin)
    Some("exit-after-header") => @sys_stdio.stdin.read_until("\n") |> ignore
    _ => fail("I expected echo or exit-after-header for the stdio fixture.")
  }
}
