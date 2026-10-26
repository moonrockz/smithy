///|
/// Block the close operation after signaling entry. The remote still uses a
/// real socket and must observe EOF after timeout or cancellation cleans up.
async fn blocked_ws_shutdown(cancel~ : Bool, force~ : Bool = false) -> Unit {
  @async.with_timeout(5000, () => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let entered : @aqueue.Queue[Unit] = @aqueue.Queue(kind=Unbounded)
    let blocked : @aqueue.Queue[Unit] = @aqueue.Queue(kind=Unbounded)
    let ended : @aqueue.Queue[Unit] = @aqueue.Queue(kind=Unbounded)
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        let (http, _) = server.accept()
        defer http.close()
        let ws = @websocket.Conn::from_http_server(http.read_request(), http)
        defer ws.close()
        let interrupted = try ws.recv().read_all() |> ignore catch {
          @io.ReaderClosed => true
          err => raise err
        } noraise {
          _ => false
        }
        assert_true(interrupted)
        ended.put(())
      })
      let conn = ws_connect("ws://127.0.0.1:\{server.addr.port()}/ws")
      defer Connection::close(conn)
      Connection::start(conn, group)
      let close_frame : async () -> Unit = () => {
        entered.put(())
        blocked.get() |> ignore
      }
      let shutdown = group.spawn(allow_failure=true, () => {
        conn.shutdown_with(close_frame)
      })
      entered.get() |> ignore
      if cancel {
        shutdown.cancel()
        let cancelled = try shutdown.wait() catch {
          @async.WaitedTaskAlreadyCancelled => true
          err => raise err
        } noraise {
          _ => false
        }
        assert_true(cancelled)
      } else {
        if force {
          Connection::close(conn)
        }
        let timed_out = try shutdown.wait() catch {
          @async.TimeoutError => true
          err => raise err
        } noraise {
          _ => false
        }
        assert_true(timed_out)
      }
      assert_true(Connection::receive(conn) is None)
      let inbox_closed = try conn.inbox.get() |> ignore catch {
        @aqueue.QueueAlreadyClosed => true
        err => raise err
      } noraise {
        _ => false
      }
      assert_true(inbox_closed)
      Connection::shutdown(conn)
      ended.get() |> ignore
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

///|
async test "ws: forced close during graceful shutdown" {
  blocked_ws_shutdown(cancel=false, force=true)
}

///|
async test "ws: forced close preserves an active graceful close operation" {
  @async.with_timeout(5000, () => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let entered : @aqueue.Queue[Unit] = @aqueue.Queue(kind=Unbounded)
    let release : @aqueue.Queue[Unit] = @aqueue.Queue(kind=Unbounded)
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        let (http, _) = server.accept()
        defer http.close()
        let ws = @websocket.Conn::from_http_server(http.read_request(), http)
        defer ws.close()
        ws.send_text("ready")
        let outcome = try ws.recv() |> ignore catch {
          err => "\{err}"
        } noraise {
          _ => "message"
        }
        inspect(outcome, content="ConnectionClosed(Normal, None)")
      })
      let conn = ws_connect("ws://127.0.0.1:\{server.addr.port()}/ws")
      defer Connection::close(conn)
      Connection::start(conn, group)
      assert_eq(Connection::receive(conn), Some("ready"))
      guard conn.reader is Running(reader) else {
        fail("I expected the WebSocket reader to be running.")
      }
      let shutdown = group.spawn(() => {
        conn.shutdown_with(() => {
          entered.put(())
          release.get() |> ignore
          conn.conn.send_close(code=Normal)
        })
      })
      entered.get() |> ignore
      Connection::close(conn)
      reader.wait() catch {
        @async.WaitedTaskAlreadyCancelled => ()
        err => raise err
      }
      release.put(())
      shutdown.wait()
    })
  })
}
