// The WebSocket transport: one JSON-RPC message in each text frame, in both
// directions.

///|
priv enum WsCloseState {
  Open
  Graceful
  Forced
} derive(Eq)

///|
priv enum WsReaderState {
  NotStarted
  Starting
  Running(@async.Task[Unit])
  Finished
}

///|
/// A WebSocket as a connection.
///
/// With `Peer::run`, a reader task of the peer reads the frames into an
/// inbox, so that `close` can end `receive` at once: a read that waits on a
/// closed socket would never end.
struct WsConnection {
  conn : @websocket.Conn
  inbox : @aqueue.Queue[String]
  mut reader : WsReaderState
  mut close_state : WsCloseState
}

///|
fn WsConnection::wrap(conn : @websocket.Conn) -> WsConnection {
  {
    conn,
    inbox: @aqueue.Queue(kind=Unbounded),
    reader: NotStarted,
    close_state: Open,
  }
}

///|
/// Connects to the WebSocket endpoint at `url`, such as
/// `ws://127.0.0.1:8080/ws`.
pub async fn ws_connect(url : String) -> WsConnection {
  guard url.has_prefix("ws://") else {
    raise TransportError(
      "I expected a URL that starts with ws://, found '\{url}'.",
    )
  }
  let conn = @websocket.connect(url) catch {
    err => raise TransportError("I could not connect to \{url}: \{err}")
  }
  WsConnection::wrap(conn)
}

///|
/// Reads the next text frame, or None when the socket is closed.
async fn WsConnection::read_message(self : WsConnection) -> String? {
  let message = self.conn.recv() catch {
    @websocket.ConnectionClosed(_, _) | @io.ReaderClosed => return None
    err => if self.close_state != Open { return None } else { raise err }
  }
  Some(message.read_all().text())
}

///|
pub impl Connection for WsConnection with fn start(self, group) {
  self.reader = Starting
  let reader = group.spawn(allow_failure=true, () => {
    defer {
      self.reader = Finished
      self.inbox.close()
      if self.close_state == Forced {
        self.conn.close()
      }
    }
    try {
      while self.close_state == Open {
        match self.read_message() {
          Some(text) => self.inbox.put(text)
          None => break
        }
      }
    } catch {
      err =>
        if self.close_state == Open && !@async.is_being_cancelled() {
          diagnose("I lost the WebSocket: \{err}")
        }
    }
  })
  // A spawned task may finish before spawn returns.
  if self.reader is Starting {
    self.reader = Running(reader)
  }
}

///|
pub impl Connection for WsConnection with fn receive(self) {
  if self.reader is NotStarted {
    if self.close_state != Open {
      return None
    }
    return self.read_message()
  }
  let text = self.inbox.get() catch {
    @aqueue.QueueAlreadyClosed => return None
    err => raise err
  }
  Some(text)
}

///|
pub impl Connection for WsConnection with fn send(self, text, related~) {
  ignore(related)
  if self.close_state != Open {
    raise TransportError(
      "I could not send the message: the WebSocket is closed.",
    )
  }
  self.conn.send_text(text) catch {
    @websocket.ConnectionClosed(_, _) =>
      raise TransportError(
        "I could not send the message: the WebSocket is closed.",
      )
    err => raise err
  }
}

///|
pub impl Connection for WsConnection with fn close(self) {
  // An active shutdown owns disposal until its close operation finishes.
  if self.close_state != Graceful {
    self.close_state = Forced
  }
  self.inbox.close()
  match self.reader {
    Running(reader) => reader.cancel()
    Starting => ()
    NotStarted | Finished => if self.close_state == Forced { self.conn.close() }
  }
}

///|
pub impl Connection for WsConnection with fn shutdown(self) {
  self.shutdown_with(() => self.conn.send_close(code=Normal))
}

///|
/// Bounds the close operation and cleans up on failure or cancellation.
async fn WsConnection::shutdown_with(
  self : WsConnection,
  close_frame : async () -> Unit,
) -> Unit {
  guard self.close_state == Open else { return }
  self.close_state = Graceful
  let result : Result[Unit, Error]? = @async.handle_cancellation(() => {
    try @async.with_timeout(1000, close_frame) catch {
      @websocket.ConnectionClosed(_, _) => Ok(())
      err => Err(err)
    } noraise {
      _ => Ok(())
    }
  })
  @async.protect_from_cancel(() => {
    defer self.conn.close()
    self.inbox.close()
    if self.reader is Running(reader) {
      reader.cancel()
      reader.wait() catch {
        _ => ()
      }
    }
  })
  match result {
    Some(Ok(_)) => ()
    Some(Err(err)) => raise err
    // The unprotected pause resumes cancellation after cleanup finishes.
    None => @async.pause()
  }
}
