// The WebSocket transport: one JSON-RPC message in each text frame, in both
// directions.

///|
/// A WebSocket as a connection.
///
/// With `Peer::run`, a reader task of the peer reads the frames into an
/// inbox, so that `close` can end `receive` at once: a read that waits on a
/// closed socket would never end.
struct WsConnection {
  conn : @websocket.Conn
  inbox : @aqueue.Queue[String]
  mut reading : Bool
  mut closed : Bool
}

///|
fn WsConnection::wrap(conn : @websocket.Conn) -> WsConnection {
  { conn, inbox: @aqueue.Queue(kind=Unbounded), reading: false, closed: false, }
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
    err => if self.closed { return None } else { raise err }
  }
  Some(message.read_all().text())
}

///|
pub impl Connection for WsConnection with fn start(self, group) {
  self.reading = true
  group.spawn_bg(allow_failure=true, () => {
    defer self.inbox.close()
    try {
      while !self.closed {
        match self.read_message() {
          Some(text) => self.inbox.put(text)
          None => break
        }
      }
    } catch {
      err =>
        if !self.closed && !@async.is_being_cancelled() {
          diagnose("I lost the WebSocket: \{err}")
        }
    }
  })
}

///|
pub impl Connection for WsConnection with fn receive(self) {
  if !self.reading {
    if self.closed {
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
  if self.closed {
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
  self.closed = true
  self.inbox.close()
  self.conn.close()
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
  guard !self.closed else { return }
  self.closed = true
  defer Connection::close(self)
  @async.with_timeout(1000, close_frame) catch {
    @websocket.ConnectionClosed(_, _) => ()
    err => raise err
  }
}
