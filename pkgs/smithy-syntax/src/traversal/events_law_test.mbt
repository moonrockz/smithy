///|
/// The events `push_events` gives a handler that follows `p`.
struct Steered {
  policy : Policy
  events : Array[String]
  mut k : Int32
}

///|
impl @traversal.Handler for Steered with fn on_enter(self, e) {
  self.events.push("+" + start_tag(e.category, e.kind, e.start))
  self.k = self.k + 1
  decide(self.policy, self.k - 1)
}

///|
impl @traversal.Handler for Steered with fn on_leave(self, e) {
  self.events.push("-" + tag(e.node))
}

///|
fn events_agree(text : String, p : Policy) -> Bool {
  guard maybe_root(text) is Some(root) else { return true }
  let p = policy_for(root, p)
  let expected = walk_projection(root, p)
  let h = { policy: p, events: [], k: 0, }
  @traversal.push_events(@traversal.EventReader::new(root), h)
  reader_events(root, p) == expected && h.events == expected
}

///|
test "law: the reader and push_events, driven by a Control policy, give walk's events" {
  @quickcheck.check(
    (input : (@lawkit.EditedModel, Policy)) => {
      events_agree(input.0.text(), input.1)
    },
    count=200,
    max_size=16,
    seed=7071,
  )
  @quickcheck.check(
    (input : (@lawkit.SmithyText, Policy)) => {
      events_agree(input.0.text(), input.1)
    },
    count=300,
    max_size=16,
    seed=7072,
  )
}

///|
/// Each Enter's path resolves to a node whose start and kind it shows, its
/// field is the last step's field, and each Leave repeats its Enter's depth
/// and path.
fn events_locate(text : String) -> Bool {
  guard maybe_root(text) is Some(root) else { return true }
  let open : Array[@traversal.EnterEvent] = []
  for e in @traversal.EventReader::new(root).iter() {
    match e {
      Enter(e) => {
        guard e.path.resolve(root) is Some(n) else { return false }
        if n.kind() != e.kind ||
          n.span().start != e.start ||
          e.depth != e.path.depth() ||
          e.field != e.path.last().map(s => s.field) {
          return false
        }
        open.push(e)
      }
      Leave(e) => {
        guard open.pop() is Some(o) else { return false }
        if o.path != e.path || o.depth != e.depth {
          return false
        }
        guard e.path.resolve(root) is Some(n) && same_node(n, e.node) else {
          return false
        }
      }
    }
  }
  open.length() == 0
}

///|
test "law: each event's depth and path lead to its node, and each Leave repeats its Enter's" {
  @quickcheck.check(
    (m : @lawkit.EditedModel) => events_locate(m.text()),
    count=200,
    max_size=16,
    seed=7073,
  )
  @quickcheck.check(
    (t : @lawkit.SmithyText) => events_locate(t.text()),
    count=300,
    max_size=16,
    seed=7074,
  )
}

///|
/// `skip_children` after a Leave changes nothing.
fn stray_skip_is_inert(text : String) -> Bool {
  guard maybe_root(text) is Some(root) else { return true }
  let plain = @traversal.EventReader::new(root)
    .iter()
    .map(e => {
      match e {
        Enter(e) => "+\{e.path}"
        Leave(e) => "-\{e.path}"
      }
    })
    .to_array()
  let r = @traversal.EventReader::new(root)
  let got = []
  while r.next() is Some(e) {
    match e {
      Enter(e) => got.push("+\{e.path}")
      Leave(e) => {
        got.push("-\{e.path}")
        r.skip_children()
      }
    }
  }
  got == plain
}

///|
test "law: skip_children anywhere but right after an Enter changes nothing" {
  @quickcheck.check(
    (m : @lawkit.EditedModel) => stray_skip_is_inert(m.text()),
    count=200,
    max_size=16,
    seed=7075,
  )
}
