///|
/// One end of an in-memory link between the two generated runtime packages.
/// `None` in a queue means that the other end closed.
priv struct End {
  inbox : @aqueue.Queue[String?]
  outbox : @aqueue.Queue[String?]
}

///|
fn link() -> (End, End) {
  let a = @aqueue.Queue(kind=Unbounded)
  let b = @aqueue.Queue(kind=Unbounded)
  ({ inbox: a, outbox: b, }, { inbox: b, outbox: a, })
}

///|
impl @pos_rpc.Connection for End with fn receive(self) {
  self.inbox.get()
}

///|
impl @pos_rpc.Connection for End with fn send(self, text, related~) {
  ignore(related)
  self.outbox.put(Some(text))
}

///|
impl @pos_rpc.Connection for End with fn close(self) {
  let _ = self.outbox.try_put(None) catch { _ => false }
}

///|
priv struct TerminalEnd(End)

///|
impl @terminal_rpc.Connection for TerminalEnd with fn receive(self) {
  self.0.inbox.get()
}

///|
impl @terminal_rpc.Connection for TerminalEnd with fn send(self, text, related~) {
  ignore(related)
  self.0.outbox.put(Some(text))
}

///|
impl @terminal_rpc.Connection for TerminalEnd with fn close(self) {
  let _ = self.0.outbox.try_put(None) catch { _ => false }
}

///|
/// Run one scenario between the MoonBit POS and the MoonBit terminal, and give
/// the POS log.
async fn run_pair(scenario : String) -> Array[String] {
  let (pos_end, terminal_end) = link()
  let log = @pos_rpc.TranscriptLog::memory()
  let pos_peer = @pos.new_peer(log~)
  let pos = Pos::new(scenario)
  @pos.register_point_of_sale(pos_peer, pos)
  let terminal_peer = @terminal.new_peer()
  @terminal.register_payment_terminal(terminal_peer, Terminal::new())
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let conn = TerminalEnd(terminal_end)
      terminal_peer.run(conn)
      @terminal_rpc.Connection::close(conn)
    })
    group.spawn_bg(() => pos_peer.run(pos_end))
    run_scenario(pos, @pos.PaymentTerminalClient::new(pos_peer))
    @pos_rpc.Connection::close(pos_end)
  })
  log.lines()
}

///|
async test "payment scenario" {
  let lines = run_pair("payment")
  assert_true(lines.iter().any(line => line.contains("\"amount\":2.50")))
  assert_true(lines.iter().any(line => line.contains("\"pos.confirmTip\"")))
}

///|
async test "errors scenario" {
  let lines = run_pair("errors")
  assert_true(
    lines.iter().any(line => line.contains("\"amount\":12345678901234567.00")),
  )
  assert_true(lines.iter().any(line => line.contains("\"code\":1001")))
}

///|
async test "cancellation scenario" {
  let lines = run_pair("cancellation")
  assert_true(lines.iter().any(line => line.contains("\"$/cancelRequest\"")))
  assert_true(lines.iter().any(line => line.contains("\"code\":-32800")))
}

///|
async test "refusals scenario" {
  let lines = run_pair("refusals")
  // The checked calls send nothing: twelve messages reach the wire.
  assert_eq(lines.length(), 12)
  assert_true(lines[1].contains("\"code\":1007"))
  assert_true(lines[6].contains("\"code\":1008"))
}

///|
test "exact decimal addition" {
  assert_eq(add_decimal("20.00", "2.50"), "22.50")
  assert_eq(add_decimal("12345678901234567.00", "2.50"), "12345678901234569.50")
  assert_eq(add_decimal("9.99", "0.01"), "10.00")
  assert_eq(add_decimal("1", "2.5"), "3.5")
}
