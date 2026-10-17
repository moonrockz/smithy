///|
/// Records the source/handler handshake. A callback must consume each event
/// before another read, and only a SkipChildren decision permits a skip.
struct AuditedSource {
  reader : @traversal.EventReader
  read : Array[@traversal.Event]
  mut awaiting_callback : Bool
  mut awaiting_skip : Bool
  mut stopped : Bool
  mut eof_reads : Int32
  mut valid : Bool
}

///|
impl @traversal.EventSource for AuditedSource with fn next(self) {
  self.valid = self.valid &&
    !self.awaiting_callback &&
    !self.awaiting_skip &&
    !self.stopped
  let event = self.reader.next()
  match event {
    Some(e) => {
      self.read.push(e)
      self.awaiting_callback = true
    }
    None => self.eof_reads += 1
  }
  event
}

///|
impl @traversal.EventSource for AuditedSource with fn skip_children(self) {
  self.valid = self.valid &&
    self.awaiting_skip &&
    !self.awaiting_callback &&
    !self.stopped
  self.awaiting_skip = false
  self.reader.skip_children()
}

///|
struct AuditedHandler {
  source : AuditedSource
  policy : Policy
  handled : Array[@traversal.Event]
  mut enters : Int32
}

///|
impl @traversal.Handler for AuditedHandler with fn on_enter(self, event) {
  self.source.valid = self.source.valid && self.source.awaiting_callback
  self.source.awaiting_callback = false
  self.handled.push(Enter(event))
  let decision = decide(self.policy, self.enters)
  self.enters += 1
  match decision {
    SkipChildren => self.source.awaiting_skip = true
    Stop => self.source.stopped = true
    Continue => ()
  }
  decision
}

///|
impl @traversal.Handler for AuditedHandler with fn on_leave(self, event) {
  self.source.valid = self.source.valid && self.source.awaiting_callback
  self.source.awaiting_callback = false
  self.handled.push(Leave(event))
}

///|
/// The two independent contracts: source interaction and event-record identity.
fn push_contracts(root : @traversal.NodeRef, policy : Policy) -> (Bool, Bool) {
  let source = {
    reader: @traversal.EventReader::new(root),
    read: [],
    awaiting_callback: false,
    awaiting_skip: false,
    stopped: false,
    eof_reads: 0,
    valid: true,
  }
  let handler = { source, policy, handled: [], enters: 0, }
  @traversal.push_events(source, handler)
  let interaction = source.valid &&
    !source.awaiting_callback &&
    !source.awaiting_skip &&
    source.eof_reads == (if source.stopped { 0 } else { 1 })
  let records = source.read.length() == handler.handled.length() &&
    source.read
    .iter()
    .zip(handler.handled.iter())
    .all(pair => {
      match pair {
        (Enter(a), Enter(b)) => physical_equal(a, b)
        (Leave(a), Leave(b)) => physical_equal(a, b)
        _ => false
      }
    })
  (interaction, records)
}

///|
test "law: push reads one event at a time, skips only on request and never reads after Stop" {
  @quickcheck.check(
    (input : (@lawkit.EditedModel, Policy)) => {
      guard maybe_root(input.0.text()) is Some(root) else { return true }
      push_contracts(root, policy_for(root, input.1)).0
    },
    count=250,
    max_size=16,
    seed=7081,
  )
  @quickcheck.check(
    (input : (@lawkit.SmithyText, Policy)) => {
      guard maybe_root(input.0.text()) is Some(root) else { return true }
      push_contracts(root, policy_for(root, input.1)).0
    },
    count=300,
    max_size=16,
    seed=7082,
  )
}

///|
test "law: push forwards the exact enter and leave records returned by its source" {
  @quickcheck.check(
    (input : (@lawkit.EditedModel, Policy)) => {
      guard maybe_root(input.0.text()) is Some(root) else { return true }
      push_contracts(root, policy_for(root, input.1)).1
    },
    count=250,
    max_size=16,
    seed=7083,
  )
  @quickcheck.check(
    (input : (@lawkit.SmithyText, Policy)) => {
      guard maybe_root(input.0.text()) is Some(root) else { return true }
      push_contracts(root, policy_for(root, input.1)).1
    },
    count=300,
    max_size=16,
    seed=7084,
  )
}

///|
test "push honors early and late stops and the final enter without reading ahead" {
  let root = root_of(every_form)
  let count = all_nodes(root).length()
  assert_true(count > 8)
  for stop in [0, 1, 8, count / 2, count - 1] {
    let policy = Policy([Continue], Some(stop))
    assert_eq(push_contracts(root, policy), (true, true))
    assert_eq(
      walk_events(root, policy).filter(s => s.has_prefix("+")).length(),
      stop + 1,
    )
    assert_eq(reader_events(root, policy), walk_projection(root, policy))
    assert_true(accept_agrees(every_form, policy))
    assert_true(fold_laws(every_form, policy))
  }
  assert_eq(push_contracts(root, Policy([Continue], None)), (true, true))
  assert_eq(push_contracts(root, Policy([SkipChildren], None)), (true, true))
}
