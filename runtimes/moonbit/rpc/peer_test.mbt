// Two peers that run against each other over an in-memory connection, with
// the session rules of examples/payment-terminal/model.smithy.

///|
fn rule(
  receiver : String,
  name : String,
  allowed? : Array[String],
  on_call? : String,
  on_success? : String,
  on_error? : String,
  requires~ : Array[String] = [],
  cancels? : @rpc.CancelRule,
) -> @rpc.MethodRule {
  @rpc.MethodRule::new(
    receiver~,
    method_name=name,
    allowed~,
    on_call~,
    on_success~,
    on_error~,
    requires~,
    cancels~,
  )
}

///|
fn payment_rules() -> @rpc.SessionRules {
  let capabilities = [
    "payment", "swipe", "chip", "contactless", "pin", "tips", "signature", "progress",
    "cancellation",
  ].map(name => {
    @rpc.CapabilitySource::new(
      name~,
      method_name="terminal.initialize",
      pointer="/capabilities/\{name}",
    )
  })
  @rpc.SessionRules::new(
    states=[
      "starting", "initializing", "ready", "paying", "stopping", "stopped",
    ],
    capabilities~,
    methods=[
      rule(
        "terminal",
        "terminal.initialize",
        allowed=["starting"],
        on_success="initializing",
      ),
      rule(
        "terminal",
        "terminal.initialized",
        allowed=["initializing"],
        on_call="ready",
      ),
      rule(
        "terminal",
        "payment.start",
        allowed=["ready"],
        on_call="paying",
        on_success="ready",
        on_error="ready",
        requires=["payment"],
      ),
      rule("terminal", "payment.status", allowed=["ready", "paying"]),
      rule(
        "terminal",
        "terminal.shutdown",
        allowed=["ready"],
        on_success="stopping",
      ),
      rule("terminal", "terminal.exit", allowed=["stopping"], on_call="stopped"),
      rule(
        "terminal",
        "$/cancelRequest",
        allowed=["paying"],
        requires=["cancellation"],
        cancels=@rpc.CancelRule::new(
          id_member="id",
          position=Some(0),
          code=Some(-32800),
        ),
      ),
      rule("pos", "payment.progress", allowed=["paying"], requires=["progress"]),
      rule("pos", "pos.confirmTip", allowed=["paying"], requires=["tips"]),
      rule("pos", "pos.display", allowed=["ready", "paying"]),
    ],
    refusals=[
      ("starting", 1007),
      ("initializing", 1007),
      ("stopping", 1007),
      ("stopped", 1007),
    ],
    capability_refusal=Some(1008),
  )
}

///|
fn json(text : String) -> Json {
  @rpc.parse_json(text) catch {
    err => abort("bad test JSON: \{err}")
  }
}

///|
/// A terminal with test handlers. `payment.start` follows the cents of the
/// amount: `.17` waits for a cancel, any other amount runs the callback flow.
fn new_terminal(log : @rpc.TranscriptLog) -> @rpc.Peer {
  let peer = @rpc.Peer::new(
    self_name="terminal",
    remote_name="pos",
    rules=payment_rules(),
    log=Some(log),
  )
  peer.on_request("terminal.ping", RequestOnly, (_, _) => Json::null())
  peer.on_request("terminal.initialize", RequestOnly, (params, _) => {
    let fields = @rpc.object_of(
      @rpc.named_params(params, path="/params"),
      path="/params",
    )
    let pos_name = @rpc.decode_string(
      @rpc.required(fields, "posName", path="/params"),
      path="/params/posName",
    )
    let payment = !pos_name.has_suffix("(no payment)")
    let caps = Map([("payment", Json::boolean(payment))])
    for name in ["chip", "tips", "progress", "cancellation"] {
      caps[name] = Json::boolean(true)
    }
    Json::object(
      Map([
        ("protocolVersion", Json::string("1")),
        ("terminalId", Json::string("test-terminal")),
        ("capabilities", Json::object(caps)),
      ]),
    )
  })
  peer.on_notification("terminal.initialized", NotificationOnly, (_, _) => ())
  peer.on_request("payment.start", RequestOnly, (params, ctx) => {
    let fields = @rpc.object_of(
      @rpc.named_params(params, path="/params"),
      path="/params",
    )
    let payment_id = @rpc.decode_string(
      @rpc.required(fields, "paymentId", path="/params"),
      path="/params/paymentId",
    )
    let money = @rpc.object_of(
      @rpc.required(fields, "amount", path="/params"),
      path="/params/amount",
    )
    let amount = @rpc.Decimal::from_json(
      @rpc.required(money, "amount", path="/params/amount"),
      path="/params/amount/amount",
    )
    let remote = ctx.peer()
    let progress = (phase : String) => {
      remote.notify(
        "payment.progress",
        Some(
          Json::object(
            Map([("requestId", ctx.id_json()), ("phase", Json::string(phase))]),
          ),
        ),
      )
    }
    progress("insertCard")
    if amount.to_string().has_suffix(".17") {
      // Wait until the POS cancels the call.
      @async.sleep(60000)
      raise @rpc.RpcError(code=1004, message="I timed out.", data=None)
    }
    if amount.to_string().has_suffix(".13") {
      raise @rpc.RpcError(
        code=1001,
        message="I declined the card.",
        data=Some(Json::string("test decline")),
      )
    }
    let tip = remote.request(
      "pos.confirmTip",
      Some(Json::object(Map([("paymentId", Json::string(payment_id))]))),
    )
    remote.notify(
      "pos.display",
      Some(json("{\"message\":\"I am checking the test payment.\"}")),
    )
    Json::object(
      Map([
        ("paymentId", Json::string(payment_id)),
        ("amount", amount.to_json()),
        ("tip", tip),
      ]),
    )
  })
  peer.on_request("payment.status", RequestOnly, (_, _) => {
    raise @rpc.RpcError(
      code=1005,
      message="I have no such payment.",
      data=Some(json("{\"paymentId\":\"x\"}")),
    )
  })
  peer.on_request("terminal.shutdown", RequestOnly, (_, _) => Json::null())
  peer.on_notification("terminal.exit", NotificationOnly, (_, _) => ())
  peer.on_request("terminal.fail", RequestOnly, (_, _) => fail("broken handler"))
  peer
}

///|
/// A POS with test handlers. On progress of a call it can send a cancel.
fn new_pos(
  log : @rpc.TranscriptLog,
  cancel_on_progress~ : Bool = false,
) -> @rpc.Peer {
  let peer = @rpc.Peer::new(
    self_name="pos",
    remote_name="terminal",
    rules=payment_rules(),
    log=Some(log),
  )
  peer.call_reference("payment.progress", id_member="requestId", position=None)
  peer.on_notification("payment.progress", NotificationOnly, (params, ctx) => {
    guard cancel_on_progress else { return }
    let fields = @rpc.object_of(
      @rpc.named_params(params, path="/params"),
      path="/params",
    )
    let id = @rpc.required(fields, "requestId", path="/params")
    ctx.peer().notify("$/cancelRequest", Some(Json::object(Map([("id", id)]))))
  })
  peer.on_request("pos.confirmTip", RequestOnly, (_, _) => Json::boolean(true))
  peer.on_notification("pos.display", NotificationOnly, (_, _) => ())
  peer
}

///|
fn lines(log : @rpc.TranscriptLog) -> String {
  log.lines().join("\n")
}

///|
/// Runs `body` with a POS and a terminal that are connected in memory.
async fn with_peers(
  body : async (@rpc.Peer, @rpc.Peer) -> Unit,
  cancel_on_progress~ : Bool = false,
) -> (String, String) {
  let pos_log = @rpc.TranscriptLog::memory()
  let terminal_log = @rpc.TranscriptLog::memory()
  let pos = new_pos(pos_log, cancel_on_progress~)
  let terminal = new_terminal(terminal_log)
  let (a, b) = @rpc.memory_pair()
  @async.with_task_group(group => {
    group.spawn_bg(() => terminal.run(b))
    group.spawn_bg(() => pos.run(a))
    body(pos, terminal)
    a.close()
  })
  (lines(pos_log), lines(terminal_log))
}

///|
async fn error_text(f : async () -> Unit) -> String {
  try f() catch {
    @rpc.RpcError(code~, message~, data~) => {
      let data = match data {
        Some(value) => " " + @rpc.write_json(value)
        None => ""
      }
      "\{code} \{message}\{data}"
    }
    err => "other: \{err}"
  } noraise {
    _ => "no error"
  }
}

///|
async fn initialize(pos : @rpc.Peer, name : String) -> Unit {
  pos.request(
    "terminal.initialize",
    Some(
      Json::object(
        Map([
          ("protocolVersion", Json::string("1")),
          ("posName", Json::string(name)),
        ]),
      ),
    ),
  )
  |> ignore
  pos.notify("terminal.initialized", None)
}

///|
async test "a call before initialize is refused locally and remotely" {
  let (pos_log, terminal_log) = with_peers((pos, terminal) => {
    let params = Some(json("{\"paymentId\":\"test-1\"}"))
    inspect(
      error_text(() => pos.request("payment.status", params) |> ignore),
      content="1007 I refused payment.status in state starting.",
    )
    inspect(
      error_text(() => {
        pos.request("payment.status", params, checked=false) |> ignore
      }),
      content="1007 I refused payment.status in state starting.",
    )
    inspect(pos.state(), content="starting")
    inspect(terminal.state(), content="starting")
  })
  // The checked call sent nothing.
  inspect(
    pos_log,
    content=(
      #|{"dir":"send","message":{"jsonrpc":"2.0","id":1,"method":"payment.status","params":{"paymentId":"test-1"}}}
      #|{"dir":"recv","message":{"jsonrpc":"2.0","id":1,"error":{"code":1007,"message":"I refused payment.status in state starting."}}}
    ),
  )
  inspect(
    terminal_log,
    content=(
      #|{"dir":"recv","message":{"jsonrpc":"2.0","id":1,"method":"payment.status","params":{"paymentId":"test-1"}}}
      #|{"dir":"send","message":{"jsonrpc":"2.0","id":1,"error":{"code":1007,"message":"I refused payment.status in state starting."}}}
    ),
  )
}

///|
async test "a capability that is not advertised is refused" {
  let (_, terminal_log) = with_peers((pos, terminal) => {
    initialize(pos, "test checkout (no payment)")
    inspect(pos.state(), content="ready")
    inspect(pos.advertised("payment"), content="false")
    inspect(pos.advertised("chip"), content="true")
    let params = Some(
      json(
        "{\"paymentId\":\"test-1\",\"amount\":{\"amount\":20.00,\"currency\":\"USD\"},\"entry\":{\"chip\":{\"maskedNumber\":\"**** 4242\"}}}",
      ),
    )
    inspect(
      error_text(() => pos.request("payment.start", params) |> ignore),
      content="1008 I refused payment.start because payment is not advertised.",
    )
    inspect(
      error_text(() => {
        pos.request("payment.start", params, checked=false) |> ignore
      }),
      content="1008 I refused payment.start because payment is not advertised.",
    )
    // A refused call causes no transition on either side.
    inspect(pos.state(), content="ready")
    inspect(terminal.state(), content="ready")
    pos.request("terminal.shutdown", None) |> ignore
    inspect(
      error_text(() => {
        pos.request("payment.status", Some(json("{\"paymentId\":\"test-1\"}")))
        |> ignore
      }),
      content="1007 I refused payment.status in state stopping.",
    )
    pos.notify("terminal.exit", None)
    inspect(pos.state(), content="stopped")
  })
  inspect(
    terminal_log,
    content=(
      #|{"dir":"recv","message":{"jsonrpc":"2.0","id":1,"method":"terminal.initialize","params":{"protocolVersion":"1","posName":"test checkout (no payment)"}}}
      #|{"dir":"send","message":{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"1","terminalId":"test-terminal","capabilities":{"payment":false,"chip":true,"tips":true,"progress":true,"cancellation":true}}}}
      #|{"dir":"recv","message":{"jsonrpc":"2.0","method":"terminal.initialized"}}
      #|{"dir":"recv","message":{"jsonrpc":"2.0","id":2,"method":"payment.start","params":{"paymentId":"test-1","amount":{"amount":20.00,"currency":"USD"},"entry":{"chip":{"maskedNumber":"**** 4242"}}}}}
      #|{"dir":"send","message":{"jsonrpc":"2.0","id":2,"error":{"code":1008,"message":"I refused payment.start because payment is not advertised."}}}
      #|{"dir":"recv","message":{"jsonrpc":"2.0","id":3,"method":"terminal.shutdown"}}
      #|{"dir":"send","message":{"jsonrpc":"2.0","id":3,"result":null}}
      #|{"dir":"recv","message":{"jsonrpc":"2.0","method":"terminal.exit"}}
    ),
  )
}

///|
async test "a handler calls back while its call runs, with exact decimals" {
  let (pos_log, _) = with_peers((pos, terminal) => {
    initialize(pos, "test checkout")
    let result = pos.request(
      "payment.start",
      Some(
        json(
          "{\"paymentId\":\"test-big\",\"amount\":{\"amount\":12345678901234567.00,\"currency\":\"USD\"},\"entry\":{\"chip\":{\"maskedNumber\":\"**** 4242\"}}}",
        ),
      ),
    )
    inspect(
      @rpc.write_json(result),
      content="{\"paymentId\":\"test-big\",\"amount\":12345678901234567.00,\"tip\":true}",
    )
    inspect(pos.state(), content="ready")
    inspect(terminal.state(), content="ready")
  })
  inspect(
    pos_log,
    content=(
      #|{"dir":"send","message":{"jsonrpc":"2.0","id":1,"method":"terminal.initialize","params":{"protocolVersion":"1","posName":"test checkout"}}}
      #|{"dir":"recv","message":{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"1","terminalId":"test-terminal","capabilities":{"payment":true,"chip":true,"tips":true,"progress":true,"cancellation":true}}}}
      #|{"dir":"send","message":{"jsonrpc":"2.0","method":"terminal.initialized"}}
      #|{"dir":"send","message":{"jsonrpc":"2.0","id":2,"method":"payment.start","params":{"paymentId":"test-big","amount":{"amount":12345678901234567.00,"currency":"USD"},"entry":{"chip":{"maskedNumber":"**** 4242"}}}}}
      #|{"dir":"recv","message":{"jsonrpc":"2.0","method":"payment.progress","params":{"requestId":2,"phase":"insertCard"}}}
      #|{"dir":"recv","message":{"jsonrpc":"2.0","id":1,"method":"pos.confirmTip","params":{"paymentId":"test-big"}}}
      #|{"dir":"send","message":{"jsonrpc":"2.0","id":1,"result":true}}
      #|{"dir":"recv","message":{"jsonrpc":"2.0","method":"pos.display","params":{"message":"I am checking the test payment."}}}
      #|{"dir":"recv","message":{"jsonrpc":"2.0","id":2,"result":{"paymentId":"test-big","amount":12345678901234567.00,"tip":true}}}
    ),
  )
}

///|
async test "a cancel stops a long call and answers it with the modeled code" {
  let (pos_log, terminal_log) = with_peers(cancel_on_progress=true, (
    pos,
    terminal,
  ) => {
    initialize(pos, "test checkout")
    inspect(
      error_text(() => {
        pos.request(
          "payment.start",
          Some(
            json(
              "{\"paymentId\":\"test-cancel\",\"amount\":{\"amount\":12345678901234567.17,\"currency\":\"USD\"},\"entry\":{\"chip\":{\"maskedNumber\":\"**** 4242\"}}}",
            ),
          ),
        )
        |> ignore
      }),
      content="-32800 I cancelled payment.start.",
    )
    inspect(pos.state(), content="ready")
    inspect(terminal.state(), content="ready")
    pos.request("terminal.shutdown", None) |> ignore
  })
  let tail = (text : String) => {
    let all = text.split("\n").map(s => s.to_owned()).collect()
    all[3:].to_owned().join("\n")
  }
  inspect(
    tail(pos_log),
    content=(
      #|{"dir":"send","message":{"jsonrpc":"2.0","id":2,"method":"payment.start","params":{"paymentId":"test-cancel","amount":{"amount":12345678901234567.17,"currency":"USD"},"entry":{"chip":{"maskedNumber":"**** 4242"}}}}}
      #|{"dir":"recv","message":{"jsonrpc":"2.0","method":"payment.progress","params":{"requestId":2,"phase":"insertCard"}}}
      #|{"dir":"send","message":{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":2}}}
      #|{"dir":"recv","message":{"jsonrpc":"2.0","id":2,"error":{"code":-32800,"message":"I cancelled payment.start."}}}
      #|{"dir":"send","message":{"jsonrpc":"2.0","id":3,"method":"terminal.shutdown"}}
      #|{"dir":"recv","message":{"jsonrpc":"2.0","id":3,"result":null}}
    ),
  )
  inspect(
    tail(terminal_log),
    content=(
      #|{"dir":"recv","message":{"jsonrpc":"2.0","id":2,"method":"payment.start","params":{"paymentId":"test-cancel","amount":{"amount":12345678901234567.17,"currency":"USD"},"entry":{"chip":{"maskedNumber":"**** 4242"}}}}}
      #|{"dir":"send","message":{"jsonrpc":"2.0","method":"payment.progress","params":{"requestId":2,"phase":"insertCard"}}}
      #|{"dir":"recv","message":{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":2}}}
      #|{"dir":"send","message":{"jsonrpc":"2.0","id":2,"error":{"code":-32800,"message":"I cancelled payment.start."}}}
      #|{"dir":"recv","message":{"jsonrpc":"2.0","id":3,"method":"terminal.shutdown"}}
      #|{"dir":"send","message":{"jsonrpc":"2.0","id":3,"result":null}}
    ),
  )
}

///|
async test "errors of handlers map to JSON-RPC codes" {
  with_peers((pos, _) => {
    initialize(pos, "test checkout")
    inspect(
      error_text(() => {
        pos.request("payment.status", Some(json("{\"paymentId\":\"x\"}")))
        |> ignore
      }),
      content="1005 I have no such payment. {\"paymentId\":\"x\"}",
    )
    inspect(
      error_text(() => pos.request("terminal.unknown", None) |> ignore),
      content="-32601 I do not know method terminal.unknown.",
    )
    inspect(
      error_text(() => {
        pos.request("terminal.initialize", Some(json("{}"))) |> ignore
      }),
      content="-32600 I refused terminal.initialize in state ready.",
    )
    inspect(
      error_text(() => {
        pos.request("payment.start", Some(json("{\"paymentId\":\"p\"}")))
        |> ignore
      }),
      content="-32602 I could not decode payment.start params at /params/amount: I expected the required member amount, found nothing.",
    )
    inspect(pos.state(), content="ready")
    let failed = error_text(() => pos.request("terminal.fail", None) |> ignore)
    assert_true(failed.has_prefix("-32603 I could not handle terminal.fail: "))
    assert_true(failed.contains("broken handler"))
    inspect(
      error_text(() => {
        pos.request("terminal.exit", None, checked=false) |> ignore
      }),
      content="-32600 I refused terminal.exit in state ready.",
    )
    pos.request("terminal.shutdown", None) |> ignore
    // A request to a notification method is accepted by the session, and
    // gets -32600.
    inspect(
      error_text(() => pos.request("terminal.exit", None) |> ignore),
      content="-32600 I expected a notification for method terminal.exit; I received a request.",
    )
    inspect(pos.state(), content="stopped")
  })
  |> ignore
}

///|
/// Runs a terminal against a raw connection end, sends `inputs` one by one,
/// and gives the texts that the terminal sent.
async fn raw_exchange(inputs : Array[String], replies : Int32) -> String {
  let terminal = new_terminal(@rpc.TranscriptLog::memory())
  let (a, b) = @rpc.memory_pair()
  let out = []
  @async.with_task_group(group => {
    group.spawn_bg(() => terminal.run(b))
    for input in inputs {
      a.send(input, related=None)
    }
    for _ in 0..<replies {
      match a.receive() {
        Some(text) => out.push(text)
        None => break
      }
    }
    a.close()
  })
  out.join("\n")
}

///|
async test "request IDs are echoed exactly" {
  inspect(
    raw_exchange(
      [
        "{\"jsonrpc\":\"2.0\",\"id\":900719925474099312345,\"method\":\"terminal.ping\"}",
        "{\"jsonrpc\":\"2.0\",\"id\":\"payment-1\",\"method\":\"terminal.ping\",\"extra\":true}",
        "{\"jsonrpc\":\"2.0\",\"id\":-0,\"method\":\"terminal.ping\"}",
      ],
      3,
    ),
    content=(
      #|{"jsonrpc":"2.0","id":900719925474099312345,"result":null}
      #|{"jsonrpc":"2.0","id":"payment-1","result":null}
      #|{"jsonrpc":"2.0","id":-0,"result":null}
    ),
  )
}

///|
async test "a batch and invalid envelopes get -32600, invalid JSON gets -32700" {
  inspect(
    raw_exchange(
      [
        "[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"terminal.ping\"}]", "[]", "{\"jsonrpc\":\"1.0\",\"id\":2,\"method\":\"terminal.ping\"}",
        "{\"jsonrpc\":\"2.0\",\"id\":1.5,\"method\":\"terminal.ping\"}", "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":7}",
        "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"terminal.ping\",\"params\":\"x\"}",
        "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\"", "{\"jsonrpc\":\"2.0\",\"method\":\"terminal.ping\"}",
        "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"terminal.ping\"}",
      ],
      8,
    ),
    content=(
      #|{"jsonrpc":"2.0","id":null,"error":{"code":-32600,"message":"I do not accept a batch; I received a JSON array."}}
      #|{"jsonrpc":"2.0","id":null,"error":{"code":-32600,"message":"I do not accept a batch; I received a JSON array."}}
      #|{"jsonrpc":"2.0","id":2,"error":{"code":-32600,"message":"I expected a valid JSON-RPC 2.0 request; I found no jsonrpc member with the value 2.0."}}
      #|{"jsonrpc":"2.0","id":null,"error":{"code":-32600,"message":"I expected a valid JSON-RPC 2.0 request; I found an id that is not a string or an integer: 1.5."}}
      #|{"jsonrpc":"2.0","id":3,"error":{"code":-32600,"message":"I expected a valid JSON-RPC 2.0 request; I found a method member that is not a string."}}
      #|{"jsonrpc":"2.0","id":4,"error":{"code":-32600,"message":"I expected a valid JSON-RPC 2.0 request; I found params that are a string."}}
      #|{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"I could not parse the message as JSON: I expected ':' after the member name at offset 32 of the JSON text, found the end of the input."}}
      #|{"jsonrpc":"2.0","id":6,"result":null}
    ),
  )
}

///|
async test "a notification to a request method is dropped" {
  inspect(
    raw_exchange(
      [
        "{\"jsonrpc\":\"2.0\",\"method\":\"terminal.ping\"}", "{\"jsonrpc\":\"2.0\",\"method\":\"payment.unknown\"}",
        "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"terminal.ping\"}",
      ],
      1,
    ),
    content=(
      #|{"jsonrpc":"2.0","id":7,"result":null}
    ),
  )
}

///|
async test "a progress for a call that is not pending is dropped" {
  let log = @rpc.TranscriptLog::memory()
  let pos = new_pos(log)
  let seen = []
  pos.on_notification("payment.progress", NotificationOnly, (params, _) => {
    seen.push(@rpc.write_json(params.unwrap_or(Json::null())))
  })
  let (a, b) = @rpc.memory_pair()
  @async.with_task_group(group => {
    group.spawn_bg(() => pos.run(a))
    b.send(
      "{\"jsonrpc\":\"2.0\",\"method\":\"payment.progress\",\"params\":{\"requestId\":\"missing\",\"phase\":\"authorizing\"}}",
      related=None,
    )
    @async.sleep(10)
    b.close()
  })
  inspect(seen.length(), content="0")
}

///|
async test "a call after the connection closes fails with a TransportError" {
  let pos = new_pos(@rpc.TranscriptLog::memory())
  let (a, b) = @rpc.memory_pair()
  b.close()
  pos.run(a)
  let text = try pos.request("terminal.ping", None) catch {
    @rpc.TransportError(message) => message
    err => "other: \{err}"
  } noraise {
    _ => "no error"
  }
  inspect(
    text,
    content="I have no connection: the session with terminal ended.",
  )
}

///|
async test "a file log holds one dir-message line per message" {
  let dir = @fs.tmpdir(prefix="jsonrpc-log")
  let path = dir + "/pos.jsonl"
  let log = @rpc.TranscriptLog::open(path)
  let pos = new_pos(log)
  let terminal = new_terminal(@rpc.TranscriptLog::memory())
  let (a, b) = @rpc.memory_pair()
  @async.with_task_group(group => {
    group.spawn_bg(() => terminal.run(b))
    group.spawn_bg(() => pos.run(a))
    pos.request("terminal.ping", None) |> ignore
    a.close()
  })
  inspect(
    @fs.read_file(path).text(),
    content=(
      #|{"dir":"send","message":{"jsonrpc":"2.0","id":1,"method":"terminal.ping"}}
      #|{"dir":"recv","message":{"jsonrpc":"2.0","id":1,"result":null}}
      #|
    ),
  )
  @fs.remove(path)
  @fs.rmdir(dir)
}

///|
test "a transcript log needs a path" {
  let text = try @rpc.TranscriptLog::open("") |> ignore catch {
    @rpc.TransportError(message) => message
  } noraise {
    _ => "no error"
  }
  inspect(
    text,
    content="I expected a path for the transcript log, found an empty text.",
  )
}
