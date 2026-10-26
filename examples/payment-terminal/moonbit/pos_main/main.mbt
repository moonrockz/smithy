///|
/// The sample POS. Usage:
/// `pos_main --scenario NAME --connect TARGET [--log PATH] [-- TERMINAL ARGV...]`.
/// TARGET is `stdio` (start the terminal command after `--`),
/// `http://127.0.0.1:N/rpc` or `ws://127.0.0.1:N/ws`. The exit code is 0 when
/// every check of the scenario passes.
async fn usage(message : String) -> Unit {
  @sample.note("pos: \{message}")
  @sys.exit(2)
}

///|
async fn main {
  let args = @env.args()
  let mut scenario = ""
  let mut target = ""
  let mut log_path : String? = None
  let terminal : Array[String] = []
  let mut index = 1
  while index < args.length() {
    match args[index] {
      "--scenario" if index + 1 < args.length() => {
        index += 1
        scenario = args[index]
      }
      "--connect" if index + 1 < args.length() => {
        index += 1
        target = args[index]
      }
      "--log" if index + 1 < args.length() => {
        index += 1
        log_path = Some(args[index])
      }
      "--" => {
        terminal.append(args[index + 1:].to_owned())
        break
      }
      other => usage("I did not expect the argument `\{other}`.")
    }
    index += 1
  }
  if !@sample.scenarios.contains(scenario) {
    usage(
      "I expected --scenario with one of \{@sample.scenarios.join(", ")}, found `\{scenario}`.",
    )
  }
  let log = match log_path {
    Some(path) => Some(@pos_rpc.TranscriptLog::open(path))
    None => None
  }
  let peer = @gen_pos.new_peer(log?)
  let pos = @sample.Pos::new(scenario)
  @gen_pos.register_point_of_sale(peer, pos)
  let client = @gen_pos.PaymentTerminalClient::new(peer)
  let failed = match target {
    "stdio" => {
      if terminal.is_empty() {
        usage("I expected the terminal command after `--`.")
      }
      let conn = @pos_rpc.spawn_stdio(terminal)
      let failed = run(peer, conn, pos, client)
      let status = conn.wait()
      if status != 0 {
        @sample.note("pos: the terminal exited with status \{status}.")
      }
      failed || status != 0
    }
    _ if target.has_prefix("http://") => {
      let conn = @pos_rpc.http_connect(target)
      run(peer, conn, pos, client)
    }
    _ if target.has_prefix("ws://") => {
      let conn = @pos_rpc.ws_connect(target)
      run(peer, conn, pos, client)
    }
    _ => {
      usage(
        "I expected --connect stdio, http://HOST:PORT/rpc or ws://HOST:PORT/ws, found `\{target}`.",
      )
      true
    }
  }
  @sys.exit(if failed { 1 } else { 0 })
}

///|
/// Run the scenario while the peer reads the connection. It gives true when a
/// check failed.
async fn run(
  peer : @pos_rpc.Peer,
  conn : &@pos_rpc.Connection,
  pos : @sample.Pos,
  client : @gen_pos.PaymentTerminalClient,
) -> Bool {
  @async.with_task_group(group => {
    group.spawn_bg(() => peer.run(conn))
    let failed = try @sample.run_scenario(pos, client) catch {
      error => {
        @sample.note("pos: scenario failed: \{@sample.describe(error)}")
        true
      }
    } noraise {
      _ => false
    }
    conn.close()
    failed
  })
}
