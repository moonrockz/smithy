///|
/// A transport of JSON-RPC messages, one JSON text for each message.
///
/// - `receive` gives the next message, or None when the remote peer closed
///   the connection.
/// - `send` sends one message. `related` is the ID of the incoming call that
///   the message belongs to, when there is one: its response, or a
///   notification or request that its handler sends. A transport that has
///   one stream per call (HTTP) uses it; other transports ignore it.
/// - `close` requests forced cleanup without waiting for async I/O.
/// - `shutdown` closes gracefully in the caller's async task. The default
///   calls `close`. WebSocket sends a normal close frame before cleanup.
/// - `start` gives the transport the task group of `Peer::run`, for the
///   tasks that read its streams. The default does nothing.
/// - `watch` gives the transport a function that fails a pending call of the
///   peer. A transport with one stream per call (HTTP) calls it when that
///   stream ends before the response. The default does nothing.
pub(open) trait Connection {
  async fn receive(Self) -> String?
  async fn send(Self, String, related~ : RequestId?) -> Unit
  fn close(Self) -> Unit
  async fn shutdown(Self) -> Unit = _
  fn start(Self, @async.TaskGroup[Unit]) -> Unit = _
  fn watch(Self, (RequestId) -> Unit) -> Unit = _
}

///|
impl Connection with fn shutdown(self) {
  self.close()
}

///|
impl Connection with fn start(self, group) {
  ignore(self)
  ignore(group)
}

///|
impl Connection with fn watch(self, lost) {
  ignore(self)
  ignore(lost)
}

///|
/// One end of an in-memory connection pair.
struct MemoryConnection {
  inbox : @aqueue.Queue[String]
  outbox : @aqueue.Queue[String]
}

///|
/// Two connected ends: a message sent on one end is received on the other.
pub fn memory_pair() -> (MemoryConnection, MemoryConnection) {
  let a = @aqueue.Queue(kind=Unbounded)
  let b = @aqueue.Queue(kind=Unbounded)
  ({ inbox: a, outbox: b, }, { inbox: b, outbox: a, })
}

///|
pub impl Connection for MemoryConnection with fn receive(self) {
  let text = self.inbox.get() catch {
    @aqueue.QueueAlreadyClosed => return None
    err => raise err
  }
  Some(text)
}

///|
pub impl Connection for MemoryConnection with fn send(self, text, related~) {
  ignore(related)
  self.outbox.put(text) catch {
    @aqueue.QueueAlreadyClosed =>
      raise TransportError(
        "I could not send the message: the connection is closed.",
      )
    err => raise err
  }
}

///|
pub impl Connection for MemoryConnection with fn close(self) {
  self.outbox.close()
  self.inbox.close()
}
