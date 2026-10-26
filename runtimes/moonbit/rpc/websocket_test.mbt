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

///|
/// A remote that stops reading until shutdown has timed out or been cancelled.
/// Filling the socket keeps a writer ahead of the close frame. Once released,
/// the remote must see EOF in that unfinished message, proving socket cleanup.
async fn blocked_ws_shutdown(cancel~ : Bool) -> Unit {
  @async.with_timeout(5000, () => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let release : @aqueue.Queue[Unit] = @aqueue.Queue(kind=Unbounded)
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        let (http, _) = server.accept()
        defer http.close()
        let ws = @websocket.Conn::from_http_server(http.read_request(), http)
        defer ws.close()
        release.get() |> ignore
        let interrupted = try ws.recv().read_all() |> ignore catch {
          @io.ReaderClosed => true
          err => raise err
        } noraise {
          _ => false
        }
        assert_true(interrupted)
      })
      let conn = @rpc.ws_connect("ws://127.0.0.1:\{server.addr.port()}/ws")
      defer conn.close()
      let sent = Ref("pending")
      group.spawn_bg(no_wait=true, () => {
        try conn.send("x".repeat(32 * 1024 * 1024), related=None) catch {
          err => sent.val = "\{err}"
        } noraise {
          _ => sent.val = "sent"
        }
      })
      @async.sleep(500)
      inspect(sent.val, content="pending")
      let timed_out = try {
        if cancel {
          @async.with_timeout(20, () => conn.shutdown())
        } else {
          conn.shutdown()
        }
      } catch {
        @async.TimeoutError => true
        err => raise err
      } noraise {
        _ => false
      }
      assert_true(timed_out)
      assert_true(conn.receive() is None)
      conn.shutdown()
      release.put(())
    })
  })
}

///|
async test "ws: shutdown times out and closes a blocked socket" {
  blocked_ws_shutdown(cancel=false)
}

///|
async test "ws: cancelled shutdown closes a blocked socket" {
  blocked_ws_shutdown(cancel=true)
}
