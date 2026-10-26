///|
/// Block the close operation after signaling entry. The remote still uses a
/// real socket and must observe EOF after timeout or cancellation cleans up.
async fn blocked_ws_shutdown(cancel~ : Bool) -> Unit {
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
      let close_frame : async () -> Unit = () => {
        entered.put(())
        blocked.get() |> ignore
      }
      if cancel {
        let shutdown = group.spawn(allow_failure=true, () => {
          conn.shutdown_with(close_frame)
        })
        entered.get() |> ignore
        shutdown.cancel()
        let cancelled = try shutdown.wait() catch {
          @async.WaitedTaskAlreadyCancelled => true
          err => raise err
        } noraise {
          _ => false
        }
        assert_true(cancelled)
      } else {
        let timed_out = try conn.shutdown_with(close_frame) catch {
          @async.TimeoutError => true
          err => raise err
        } noraise {
          _ => false
        }
        assert_true(timed_out)
        entered.get() |> ignore
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
