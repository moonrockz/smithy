///|
/// A node starts. It has only what a streaming parser knows at that point:
/// the node's category and kind, its field in the parent (`None` for the
/// start node), its start, and its depth and path from the start node.
/// Build one with `EnterEvent::new`, which sets `depth` from the path.
pub struct EnterEvent {
  category : String
  kind : String
  field : String?
  start : @span.Offset
  depth : Int32
  path : NodePath
} derive(Eq, Debug)

///|
/// A node ends: the finished node, with the depth and path of its `Enter`.
/// Build one with `LeaveEvent::new`.
pub struct LeaveEvent {
  node : NodeRef
  depth : Int32
  path : NodePath
} derive(Eq, Debug)

///|
/// An `EnterEvent` whose `depth` is the path's depth.
pub fn EnterEvent::new(
  category~ : String,
  kind~ : String,
  field~ : String?,
  start~ : @span.Offset,
  path~ : NodePath,
) -> EnterEvent {
  { category, kind, field, start, depth: path.depth(), path, }
}

///|
/// A `LeaveEvent` whose `depth` is the path's depth.
pub fn LeaveEvent::new(node~ : NodeRef, path~ : NodePath) -> LeaveEvent {
  { node, depth: path.depth(), path, }
}

///|
/// One event of a traversal: a node starts or ends.
pub(all) enum Event {
  Enter(EnterEvent)
  Leave(LeaveEvent)
} derive(Eq, Debug)

///|
/// A source of events in `walk`'s order. `skip_children` right after an
/// `Enter` makes the next event that node's `Leave`; elsewhere it does
/// nothing. A streaming parser can implement it; `push_events` drives any
/// source.
pub(open) trait EventSource {
  fn next(Self) -> Event?
  fn skip_children(Self) -> Unit
}

///|
priv struct ReaderFrame {
  entered : NodeRef
  path : NodePath
  fields : Array[(PathStep, NodeRef)]
  mut at : Int32
}

///|
/// The walk of a node as pull events: `next()` returns `Enter` or `Leave`,
/// then `None` after the start node's `Leave`. To stop, stop calling
/// `next()`. An explicit stack holds the open nodes.
///
/// ```mbt check
/// test {
///   let r = @parser.parse_text("namespace a\n\nstring S\n")
///   let root = @traversal.NodeRef::of_result(r).unwrap()
///   let reader = @traversal.EventReader::new(root)
///   let log = []
///   for e in reader.iter() {
///     match e {
///       Enter(e) => log.push("+" + e.category)
///       Leave(e) => log.push("-" + e.node.category())
///     }
///   }
///   inspect(
///     log.join(" "),
///     content="+file +namespace +name -name -namespace +shape +name -name -shape -file",
///   )
/// }
/// ```
pub struct EventReader {
  priv stack : Array[ReaderFrame]
  /// The node whose `Enter` was returned last (with its path), until its
  /// children are read.
  priv mut pending : (NodeRef, NodePath)?
  /// The start node, until its `Enter` is returned.
  priv mut root : NodeRef?
}

///|
/// A reader at the start of `root`'s walk.
pub fn EventReader::new(root : NodeRef) -> EventReader {
  { stack: [], pending: None, root: Some(root), }
}

///|
/// The remaining events, read from this reader: `skip_children()` on the
/// reader still steers it.
pub fn EventReader::iter(self : EventReader) -> Iter[Event] {
  Iter::new(() => EventSource::next(self))
}

///|
fn enter_event(n : NodeRef, field : String?, path : NodePath) -> Event {
  Enter(
    EnterEvent::new(
      category=n.category(),
      kind=n.kind(),
      field~,
      start=n.span().start,
      path~,
    ),
  )
}

///|
pub impl EventSource for EventReader with fn next(self) {
  if self.pending is Some((n, path)) {
    self.pending = None
    self.stack.push({
      entered: n,
      path,
      fields: n.children_with_fields(),
      at: 0,
    })
  }
  if self.root is Some(r) {
    self.root = None
    let path = NodePath::root()
    self.pending = Some((r, path))
    return Some(enter_event(r, None, path))
  }
  guard self.stack.last() is Some(top) else { return None }
  if top.at < top.fields.length() {
    let (step, child) = top.fields[top.at]
    top.at = top.at + 1
    let path = top.path.child(step.field, step.index)
    self.pending = Some((child, path))
    Some(enter_event(child, Some(step.field), path))
  } else {
    ignore(self.stack.pop())
    Some(Leave(LeaveEvent::new(node=top.entered, path=top.path)))
  }
}

///|
pub impl EventSource for EventReader with fn skip_children(self) {
  if self.pending is Some((n, path)) {
    self.pending = None
    self.stack.push({ entered: n, path, fields: [], at: 0, })
  }
}
