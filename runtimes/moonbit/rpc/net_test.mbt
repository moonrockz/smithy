// Two peers over real localhost HTTP and WebSocket connections. The helpers
// new_pos, new_terminal, initialize, json and error_text are in
// peer_test.mbt.

///|
/// Runs `body` with a POS that connects to a terminal server over `kind`
/// ("http" or "ws"), and gives the two logs.
async fn over_network(
  kind : String,
  body : async (@rpc.Peer, @rpc.Peer) -> Unit,
  cancel_on_progress~ : Bool = false,
) -> (String, String) {
  let pos_log = @rpc.TranscriptLog::memory()
  let terminal_log = @rpc.TranscriptLog::memory()
  let pos = new_pos(pos_log, cancel_on_progress~)
  let terminal = new_terminal(terminal_log)
  let server = @rpc.RpcServer::listen(port=0)
  defer server.close()
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => server.run(conn => terminal.run(conn)))
    let port = server.port()
    let conn : &@rpc.Connection = if kind == "http" {
      let http = @rpc.http_connect("http://127.0.0.1:\{port}/rpc")
      (http : &@rpc.Connection)
    } else {
      let ws = @rpc.ws_connect("ws://127.0.0.1:\{port}/ws")
      (ws : &@rpc.Connection)
    }
    group.spawn_bg(() => pos.run(conn))
    body(pos, terminal)
    conn.close()
  })
  (lines(pos_log), lines(terminal_log))
}

///|
let payment_log : String =
  #|{"dir":"send","message":{"jsonrpc":"2.0","id":1,"method":"terminal.initialize","params":{"protocolVersion":"1","posName":"test checkout"}}}
  #|{"dir":"recv","message":{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"1","terminalId":"test-terminal","capabilities":{"payment":true,"chip":true,"tips":true,"progress":true,"cancellation":true}}}}
  #|{"dir":"send","message":{"jsonrpc":"2.0","method":"terminal.initialized"}}
  #|{"dir":"send","message":{"jsonrpc":"2.0","id":2,"method":"payment.start","params":{"paymentId":"test-big","amount":{"amount":12345678901234567.00,"currency":"USD"},"entry":{"chip":{"maskedNumber":"**** 4242"}}}}}
  #|{"dir":"recv","message":{"jsonrpc":"2.0","method":"payment.progress","params":{"requestId":2,"phase":"insertCard"}}}
  #|{"dir":"recv","message":{"jsonrpc":"2.0","id":1,"method":"pos.confirmTip","params":{"paymentId":"test-big"}}}
  #|{"dir":"send","message":{"jsonrpc":"2.0","id":1,"result":true}}
  #|{"dir":"recv","message":{"jsonrpc":"2.0","method":"pos.display","params":{"message":"I am checking the test payment."}}}
  #|{"dir":"recv","message":{"jsonrpc":"2.0","id":2,"result":{"paymentId":"test-big","amount":12345678901234567.00,"tip":true}}}

///|
async fn payment_flow(pos : @rpc.Peer, terminal : @rpc.Peer) -> Unit {
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
}

///|
async test "http: a callback and progress during a call" {
  let (pos_log, _) = over_network("http", payment_flow)
  inspect(pos_log == payment_log, content="true")
}

///|
async test "ws: a callback and progress during a call" {
  let (pos_log, _) = over_network("ws", payment_flow)
  inspect(pos_log == payment_log, content="true")
}

///|
async fn cancel_flow(pos : @rpc.Peer, terminal : @rpc.Peer) -> Unit {
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
  pos.notify("terminal.exit", None)
}

///|
async test "http: a cancel during a long call" {
  over_network("http", cancel_flow, cancel_on_progress=true) |> ignore
}

///|
async test "ws: a cancel during a long call" {
  over_network("ws", cancel_flow, cancel_on_progress=true) |> ignore
}

///|
async fn refusal_flow(pos : @rpc.Peer, _terminal : @rpc.Peer) -> Unit {
  let status = Some(json("{\"paymentId\":\"test-1\"}"))
  inspect(
    error_text(() => pos.request("payment.status", status) |> ignore),
    content="1007 I refused payment.status in state starting.",
  )
  inspect(
    error_text(() => {
      pos.request("payment.status", status, checked=false) |> ignore
    }),
    content="1007 I refused payment.status in state starting.",
  )
  initialize(pos, "test checkout (no payment)")
  inspect(
    error_text(() => {
      pos.request(
        "payment.start",
        Some(json("{\"paymentId\":\"test-1\"}")),
        checked=false,
      )
      |> ignore
    }),
    content="1008 I refused payment.start because payment is not advertised.",
  )
}

///|
async test "http: refusals" {
  let (pos_log, _) = over_network("http", refusal_flow)
  inspect(pos_log.split("\n").count(), content="7")
}

///|
async test "ws: refusals" {
  let (pos_log, _) = over_network("ws", refusal_flow)
  inspect(pos_log.split("\n").count(), content="7")
}

///|
/// POSTs `text` to the server, and gives the status, the content type, the
/// session header and the body.
async fn post_raw(
  port : Int32,
  text : String,
  session? : String,
) -> (Int32, String, String, String) {
  let headers : @http.Headers = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream",
  }
  if session is Some(id) {
    headers[@http.CaseInsensitiveString("Smithy-Session-Id")] = id
  }
  let (response, body) = @http.post(
    "http://127.0.0.1:\{port}/rpc",
    text,
    headers~,
  )
  let header = (name : String) => {
    response.headers.get(@http.CaseInsensitiveString(name)).unwrap_or("")
  }
  (
    response.code,
    header("Content-Type"),
    header("Smithy-Session-Id"),
    body.text(),
  )
}

///|
async test "http: the wire form of sessions, streams and errors" {
  let terminal = new_terminal(@rpc.TranscriptLog::memory())
  let server = @rpc.RpcServer::listen(port=0)
  defer server.close()
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => server.run(conn => terminal.run(conn)))
    let port = server.port()
    let (code, kind, session, body) = post_raw(
      port, "{\"jsonrpc\":\"2.0\",\"id\":\"payment-1\",\"method\":\"terminal.ping\"}",
    )
    inspect(code, content="200")
    inspect(kind, content="text/event-stream")
    assert_true(session.has_prefix("session-"))
    inspect(
      body,
      content=(
        #|: open
        #|
        #|event: message
        #|data: {"jsonrpc":"2.0","id":"payment-1","result":null}
        #|
        #|
      ),
    )
    let (_, _, again, body) = post_raw(
      port,
      "{\"jsonrpc\":\"2.0\",\"id\":900719925474099312345,\"method\":\"terminal.ping\"}",
      session~,
    )
    inspect(again == session, content="true")
    assert_true(
      body.contains(
        "data: {\"jsonrpc\":\"2.0\",\"id\":900719925474099312345,\"result\":null}",
      ),
    )
    let (code, _, _, body) = post_raw(
      port,
      "{\"jsonrpc\":\"2.0\",\"method\":\"terminal.initialized\"}",
      session~,
    )
    inspect(code, content="202")
    inspect(body, content="")
    let (code, kind, _, body) = post_raw(
      port,
      "[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"terminal.ping\"}]",
      session~,
    )
    inspect(code, content="200")
    inspect(kind, content="application/json")
    inspect(
      body,
      content="{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"I do not accept a batch; I received a JSON array.\"}}",
    )
    let (code, _, _, body) = post_raw(
      port,
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"terminal.ping\"}",
      session="unknown",
    )
    inspect(code, content="404")
    inspect(body, content="I do not know the session unknown.")
  })
}

///|
async test "serve picks a free port and writes listening to stderr" {
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      @rpc.serve(port=0, conn => {
        let peer = new_terminal(@rpc.TranscriptLog::memory())
        peer.run(conn)
      })
    })
    @async.sleep(50)
  })
}

///|
async test "http_connect and ws_connect check the URL" {
  let message = (f : async () -> Unit) => {
    try f() catch {
      @rpc.TransportError(text) => text
      err => "other: \{err}"
    } noraise {
      _ => "no error"
    }
  }
  inspect(
    message(() => @rpc.http_connect("ftp://127.0.0.1/rpc") |> ignore),
    content="I expected a URL that starts with http://, found 'ftp://127.0.0.1/rpc'.",
  )
  inspect(
    message(() => @rpc.ws_connect("http://127.0.0.1/ws") |> ignore),
    content="I expected a URL that starts with ws://, found 'http://127.0.0.1/ws'.",
  )
}

///|
async test "http: each client gets its own session and peer" {
  let server = @rpc.RpcServer::listen(port=0)
  defer server.close()
  let peers = []
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      server.run(conn => {
        let terminal = new_terminal(@rpc.TranscriptLog::memory())
        peers.push(terminal)
        terminal.run(conn)
      })
    })
    let url = "http://127.0.0.1:\{server.port()}/rpc"
    let first = new_pos(@rpc.TranscriptLog::memory())
    let second = new_pos(@rpc.TranscriptLog::memory())
    let a = @rpc.http_connect(url)
    let b = @rpc.http_connect(url)
    group.spawn_bg(() => first.run(a))
    group.spawn_bg(() => second.run(b))
    initialize(first, "test checkout")
    second.request("terminal.ping", None) |> ignore
    inspect(first.state(), content="ready")
    inspect(second.state(), content="starting")
    inspect(peers.length(), content="2")
    inspect(peers[0].state(), content="ready")
    inspect(peers[1].state(), content="starting")
    assert_true(a.session_id() is Some(_))
    assert_true(a.session_id() != b.session_id())
    a.close()
    b.close()
  })
}

///|
async test "ws: request IDs are echoed exactly" {
  let server = @rpc.RpcServer::listen(port=0)
  defer server.close()
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      server.run(conn => new_terminal(@rpc.TranscriptLog::memory()).run(conn))
    })
    let ws = @rpc.ws_connect("ws://127.0.0.1:\{server.port()}/ws")
    let replies = []
    for
      text in [
        "{\"jsonrpc\":\"2.0\",\"id\":900719925474099312345,\"method\":\"terminal.ping\"}",
        "{\"jsonrpc\":\"2.0\",\"id\":\"payment-1\",\"method\":\"terminal.ping\"}",
        "[]",
      ] {
      ws.send(text, related=None)
      replies.push(ws.receive().unwrap())
    }
    ws.close()
    inspect(
      replies.join("\n"),
      content=(
        #|{"jsonrpc":"2.0","id":900719925474099312345,"result":null}
        #|{"jsonrpc":"2.0","id":"payment-1","result":null}
        #|{"jsonrpc":"2.0","id":null,"error":{"code":-32600,"message":"I do not accept a batch; I received a JSON array."}}
      ),
    )
  })
}

///|
/// A server that answers each POSTed request with an event stream that ends
/// before the response: one stream with nothing, then one stream that breaks
/// after one event.
async fn broken_stream_server(server : @http.Server) -> Unit {
  let count = Ref(0)
  server.run_forever(allow_failure=true, (_, body, conn) => {
    body.read_all() |> ignore
    count.val += 1
    conn.send_response(200, "OK", extra_headers={
      "Content-Type": "text/event-stream",
      "Smithy-Session-Id": "s-1",
    })
    conn.write(": open\n\n")
    if count.val == 1 {
      conn.end_response()
    } else {
      conn.write(
        "event: message\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"pos.display\",\"params\":{\"message\":\"x\"}}\n\n",
      )
      conn.flush()
      conn.close()
    }
  })
}

///|
async test "http: a stream that ends before its response fails that call" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"), reuse_addr=true)
  defer server.close()
  let pos = new_pos(@rpc.TranscriptLog::memory())
  let failure = (f : async () -> Unit) => {
    try f() catch {
      @rpc.TransportError(message) => message
      err => "other: \{err}"
    } noraise {
      _ => "no error"
    }
  }
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => broken_stream_server(server))
      let conn = @rpc.http_connect("http://127.0.0.1:\{server.addr.port()}/rpc")
      group.spawn_bg(() => pos.run(conn))
      inspect(
        failure(() => pos.request("terminal.ping", None) |> ignore),
        content="I lost the event stream of the call to terminal.ping before its reply.",
      )
      inspect(
        failure(() => pos.request("terminal.ping", None) |> ignore),
        content="I lost the event stream of the call to terminal.ping before its reply.",
      )
      conn.close()
    })
  })
}

///|
async test "http: frames of a stream are dispatched before its call fails" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"), reuse_addr=true)
  defer server.close()
  let posted : @aqueue.Queue[String] = @aqueue.Queue(kind=Unbounded)
  let count = Ref(0)
  let log = @rpc.TranscriptLog::memory()
  let pos = @rpc.Peer::new(
    self_name="pos",
    remote_name="terminal",
    rules=@rpc.SessionRules::none(),
    log=Some(log),
  )
  pos.on_request("pos.confirmTip", RequestOnly, (_, _) => Json::boolean(true))
  let outcome = Ref("")
  let seen_at_failure = Ref("")
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => {
        server.run_forever(allow_failure=true, (_, body, conn) => {
          let text = body.read_all().text()
          count.val += 1
          if count.val == 1 {
            // The stream of the call: a server request, then a batch frame,
            // then the end, with no response to the call.
            conn.send_response(200, "OK", extra_headers={
              "Content-Type": "text/event-stream",
              "Smithy-Session-Id": "s-1",
            })
            conn.write(
              "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":\"cb-1\",\"method\":\"pos.confirmTip\",\"params\":{}}\n\n",
            )
            conn.write("event: message\ndata: [1,2]\n\n")
            conn.end_response()
          } else {
            posted.put(text)
            conn
            ..send_response(202, "Accepted", extra_headers={
              "Smithy-Session-Id": "s-1",
            })
            .end_response()
          }
        })
      })
      let conn = @rpc.http_connect("http://127.0.0.1:\{server.addr.port()}/rpc")
      group.spawn_bg(() => pos.run(conn))
      outcome.val = try pos.request("terminal.ping", None) |> ignore catch {
        @rpc.TransportError(message) => message
        err => "other: \{err}"
      } noraise {
        _ => "no error"
      }
      // The frames of the stream went through the dispatcher before the call
      // failed.
      seen_at_failure.val = log
        .lines()
        .filter(line => line.has_prefix("{\"dir\":\"recv\""))
        .join("\n")
      let replies = [posted.get(), posted.get()]
      replies.sort_by((a, b) => a.lexical_compare(b))
      inspect(
        replies.join("\n"),
        content=(
          #|{"jsonrpc":"2.0","id":"cb-1","result":true}
          #|{"jsonrpc":"2.0","id":null,"error":{"code":-32600,"message":"I do not accept a batch; I received a JSON array."}}
        ),
      )
      conn.close()
    })
  })
  inspect(
    outcome.val,
    content="I lost the event stream of the call to terminal.ping before its reply.",
  )
  inspect(
    seen_at_failure.val,
    content=(
      #|{"dir":"recv","message":{"jsonrpc":"2.0","id":"cb-1","method":"pos.confirmTip","params":{}}}
      #|{"dir":"recv","message":[1,2]}
    ),
  )
}
