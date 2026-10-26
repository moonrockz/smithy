///|
async fn with_raw_ws(body : async (&@rpc.Connection) -> Unit) -> Unit {
  @async.with_timeout(5000, () => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        let (http, _) = server.accept()
        defer http.close()
        let ws = @websocket.Conn::from_http_server(http.read_request(), http)
        defer ws.close()
        let outcome = try ws.recv() |> ignore catch {
          err => "\{err}"
        } noraise {
          _ => "message"
        }
        inspect(outcome, content="ConnectionClosed(Normal, None)")
      })
      let conn = @rpc.ws_connect("ws://127.0.0.1:\{server.addr.port()}/ws")
      defer conn.close()
      body(conn)
    })
  })
}

///|
async test "ws: shutdown sends normal close code 1000" {
  with_raw_ws(conn => conn.shutdown())
}

///|
async test "ws: shutdown after the reader task group ended" {
  with_raw_ws(conn => {
    @async.with_task_group(group => {
      conn.start(group)
      group.return_immediately(())
    })
    conn.shutdown()
    assert_true(conn.receive() is None)
  })
}

///|
async test "ws: repeated and concurrent shutdown" {
  with_raw_ws(conn => {
    @async.with_task_group(group => {
      group.spawn_bg(() => conn.shutdown())
      conn.shutdown()
    })
    conn.shutdown()
    conn.close()
    conn.shutdown()
    assert_true(conn.receive() is None)
  })
}

///|
async test "ws: shutdown while a peer reads" {
  with_raw_ws(conn => {
    let peer = new_pos(@rpc.TranscriptLog::memory())
    @async.with_task_group(group => {
      group.spawn_bg(() => peer.run(conn))
      @async.sleep(10)
      conn.shutdown()
    })
    assert_true(conn.receive() is None)
  })
}

///|
async test "ws: server callback completion sends normal close code 1000" {
  @async.with_timeout(5000, () => {
    let server = @rpc.RpcServer::listen(port=0)
    defer server.close()
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => server.run(_ => ()))
      let ws = @websocket.connect("ws://127.0.0.1:\{server.port()}/ws")
      defer ws.close()
      let outcome = try ws.recv() |> ignore catch {
        err => "\{err}"
      } noraise {
        _ => "message"
      }
      inspect(outcome, content="ConnectionClosed(Normal, None)")
    })
  })
}

///|
async test "ws: shutdown cleans up after the remote sends close" {
  @async.with_timeout(5000, () => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        let (http, _) = server.accept()
        defer http.close()
        let ws = @websocket.Conn::from_http_server(http.read_request(), http)
        defer ws.close()
        ws.send_close()
      })
      let conn = @rpc.ws_connect("ws://127.0.0.1:\{server.addr.port()}/ws")
      defer conn.close()
      assert_true(conn.receive() is None)
      conn.shutdown()
      conn.shutdown()
      assert_true(conn.receive() is None)
    })
  })
}
