///|
/// The sample terminal. Usage: `terminal_main stdio [--log PATH]`, or
/// `terminal_main serve --port N [--log PATH]` to serve `/rpc` and `/ws` on
/// 127.0.0.1:N. Diagnostics go to stderr; stdout is the stdio transport.
async fn usage(message : String) -> Unit {
  @sample.note("terminal: \{message}")
  @sys.exit(2)
}

///|
async fn main {
  let args = @env.args()
  let mode = if args.length() > 1 { args[1] } else { "" }
  let mut log_path : String? = None
  let mut port = -1
  let mut index = 2
  while index < args.length() {
    match args[index] {
      "--log" if index + 1 < args.length() => {
        index += 1
        log_path = Some(args[index])
      }
      "--port" if index + 1 < args.length() => {
        index += 1
        port = @sample.parse_port(args[index])
      }
      other => usage("I did not expect the argument `\{other}`.")
    }
    index += 1
  }
  let new_peer = () => {
    let log = match log_path {
      Some(path) => Some(@terminal_rpc.TranscriptLog::open(path))
      None => None
    }
    let peer = @gen_terminal.new_peer(log?)
    @gen_terminal.register_payment_terminal(peer, @sample.Terminal::new())
    peer
  }
  match mode {
    "stdio" => new_peer().run(@terminal_rpc.stdio_connection())
    "serve" => usage("I cannot serve on port \{port} yet.")
    _ => usage("I expected `stdio` or `serve`, found `\{mode}`.")
  }
}
