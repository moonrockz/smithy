///|
/// A handler that logs categories and steers by category.
struct Log {
  events : Array[String]
  skip : String
  stop : String
}

///|
impl @traversal.Handler for Log with fn on_enter(self, e) {
  self.events.push("+" + e.category)
  if e.category == self.stop {
    Stop
  } else if e.category == self.skip {
    SkipChildren
  } else {
    Continue
  }
}

///|
impl @traversal.Handler for Log with fn on_leave(self, e) {
  self.events.push("-" + e.node.category())
}

///|
test "push_events follows the handler's SkipChildren and Stop" {
  let log = { events: [], skip: "control", stop: "trait", }
  @traversal.push_events(@traversal.EventReader::new(root_of(tiny)), log)
  assert_eq(
    log.events.join(" "),
    "+file +control -control +namespace +name -name -namespace +shape +trait",
  )
}

///|
struct Leaves(Array[String])

///|
impl @traversal.Handler for Leaves with fn on_leave(self, e) {
  self.0.push(e.node.category())
}

///|
test "a handler with only on_leave leaves every node" {
  let leaves = Leaves([])
  let root = root_of(tiny)
  @traversal.push_events(@traversal.EventReader::new(root), leaves)
  assert_eq(leaves.0.length(), all_nodes(root).length())
}

///|
/// An outside source: two events made with `new`.
struct Fixed(Array[@traversal.Event])

///|
impl @traversal.EventSource for Fixed with fn next(self) {
  if self.0.length() == 0 {
    None
  } else {
    Some(self.0.remove(0))
  }
}

///|
impl @traversal.EventSource for Fixed with fn skip_children(_self) {
  ()
}

///|
test "an outside event source builds events with new, and push_events reads it" {
  let root = root_of(tiny)
  let path = @traversal.NodePath::root().child("shapes", 0)
  let enter = @traversal.EnterEvent::new(
    category="shape",
    kind="string",
    field=Some("shapes"),
    start=@span.Offset::zero(),
    path~,
  )
  assert_eq(enter.depth, 1)
  let log = { events: [], skip: "", stop: "", }
  @traversal.push_events(
    Fixed([Enter(enter), Leave(@traversal.LeaveEvent::new(node=root, path~))]),
    log,
  )
  assert_eq(log.events, ["+shape", "-file"])
}
