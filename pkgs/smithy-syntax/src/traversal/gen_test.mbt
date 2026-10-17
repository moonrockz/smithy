///|
/// The file node of `text`, parsed with recovery.
fn root_of(text : String) -> @traversal.NodeRef raise {
  guard @traversal.NodeRef::of_result(@parser.parse_text(text)) is Some(root) else {
    fail("no AST for the text")
  }
  root
}

///|
/// The offset of the first `needle` in `text`.
fn off(text : String, needle : String) -> @span.Offset raise {
  guard text.find(needle) is Some(i) else { fail("no \{needle} in the text") }
  guard @span.Offset::new(i) is Some(o) else { fail("bad offset") }
  o
}

///|
/// A node's occurrence tag: category, kind, start and length of `span()`.
fn tag(n : @traversal.NodeRef) -> String {
  let s = n.span()
  "\{n.category()}/\{n.kind()}@\{s.start.0}+\{s.length.0}"
}

///|
/// Every node below and including `root`, in pre-order, by an explicit stack.
fn all_nodes(root : @traversal.NodeRef) -> Array[@traversal.NodeRef] {
  let out = []
  let stack = [root]
  while stack.pop() is Some(n) {
    out.push(n)
    let cs = n.children()
    for i = cs.length() - 1; i >= 0; i = i - 1 {
      stack.push(cs[i])
    }
  }
  out
}

///|
/// The root of a text, or `None` when the parser gives no AST.
fn maybe_root(text : String) -> @traversal.NodeRef? {
  @traversal.NodeRef::of_result(@parser.parse_text(text))
}

///|
fn pick(rs : @splitmix.RandomState, n : Int32) -> Int32 {
  rs.next_uint(limit=n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
/// Repeated Continue/SkipChildren decisions and a separate Stop draw.
/// `policy_for` binds the stop to the actual tree's node count.
struct Policy(Array[@traversal.Control], Int32?) derive(Debug)

///|
impl @quickcheck.Arbitrary for Policy with fn arbitrary(_, rs) {
  let n = 1 + pick(rs, 8)
  let decisions = Array::makei(n, _ => {
    if pick(rs, 4) == 0 {
      @traversal.SkipChildren
    } else {
      @traversal.Continue
    }
  })
  let stop = if pick(rs, 2) == 0 { None } else { Some(pick(rs, 2147483647)) }
  Policy(decisions, stop)
}

///|
impl @quickcheck.Shrink for Policy

///|
fn policy_for(root : @traversal.NodeRef, p : Policy) -> Policy {
  let Policy(cs, stop) = p
  let count = all_nodes(root).length()
  Policy(cs, stop.map(draw => draw % count))
}

///|
fn decide(p : Policy, k : Int32) -> @traversal.Control {
  let Policy(cs, stop) = p
  if stop == Some(k) {
    Stop
  } else {
    cs[k % cs.length()]
  }
}

///|
/// The events a walk under `p` must produce, by plain recursion (test-only;
/// the trees here are shallow).
fn model(root : @traversal.NodeRef, p : Policy) -> Array[String] {
  let events = []
  let mut k = 0
  fn go(n : @traversal.NodeRef) -> Bool {
    let c = decide(p, k)
    k = k + 1
    events.push("+" + tag(n))
    match c {
      Stop => return true
      SkipChildren => ()
      Continue =>
        for child in n.children() {
          if go(child) {
            return true
          }
        }
    }
    events.push("-" + tag(n))
    false
  }

  ignore(go(root))
  events
}

///|
fn walk_events(root : @traversal.NodeRef, p : Policy) -> Array[String] {
  let events = []
  let mut k = 0
  @traversal.walk(
    root,
    n => {
      events.push("+" + tag(n))
      k = k + 1
      decide(p, k - 1)
    },
    leave=n => events.push("-" + tag(n)),
  )
  events
}

///|
/// A trait value of `depth` nested arrays on a string shape.
fn deep_value(depth : Int32) -> String {
  let open = "[".repeat(depth)
  let close = "]".repeat(depth)
  "$version: \"2\"\nnamespace a\n\n@t(\{open}\{close})\nstring S\n"
}

///|
/// What an `Enter` shows of a node: category/kind@start (no length yet).
fn start_tag(category : String, kind : String, start : @span.Offset) -> String {
  "\{category}/\{kind}@\{start.0}"
}

///|
/// walk's events under `p`, with each enter shown as an `Enter` shows it.
fn walk_projection(root : @traversal.NodeRef, p : Policy) -> Array[String] {
  let events = []
  let mut k = 0
  @traversal.walk(
    root,
    n => {
      events.push("+" + start_tag(n.category(), n.kind(), n.span().start))
      k = k + 1
      decide(p, k - 1)
    },
    leave=n => events.push("-" + tag(n)),
  )
  events
}

///|
/// The events a reader gives when its caller follows `p` after each `Enter`.
fn reader_events(root : @traversal.NodeRef, p : Policy) -> Array[String] {
  let r = @traversal.EventReader::new(root)
  let events = []
  let mut k = 0
  while r.next() is Some(e) {
    match e {
      Enter(e) => {
        events.push("+" + start_tag(e.category, e.kind, e.start))
        k = k + 1
        match decide(p, k - 1) {
          Continue => ()
          SkipChildren => r.skip_children()
          Stop => break
        }
      }
      Leave(e) => events.push("-" + tag(e.node))
    }
  }
  events
}

///|
/// The tags a full cursor navigation enters, depth first, and whether it
/// ends back at the start node.
fn cursor_tour(root : @traversal.NodeRef) -> (Array[String], Bool) {
  let c = @traversal.TreeCursor::new(root)
  let seen = [tag(c.node())]
  while true {
    if c.goto_first_child() {
      seen.push(tag(c.node()))
      continue
    }
    while !c.goto_next_sibling() {
      if !c.goto_parent() {
        return (seen, c.depth() == 0 && same_node(c.node(), root))
      }
    }
    seen.push(tag(c.node()))
  }
  (seen, false)
}

///|
/// Compare the AST objects inside references, not newly built enum wrappers.
fn same_node(a : @traversal.NodeRef, b : @traversal.NodeRef) -> Bool {
  match (a, b) {
    (File(x, _), File(y, _)) => physical_equal(x, y)
    (Control(x), Control(y)) => physical_equal(x, y)
    (Metadata(x), Metadata(y)) => physical_equal(x, y)
    (Namespace(x), Namespace(y)) => physical_equal(x, y)
    (Use(x), Use(y)) => physical_equal(x, y)
    (Shape(x), Shape(y)) => physical_equal(x, y)
    (Apply(x), Apply(y)) => physical_equal(x, y)
    (Inline(x), Inline(y)) => physical_equal(x, y)
    (Mixins(x), Mixins(y)) => physical_equal(x, y)
    (Member(x), Member(y)) => physical_equal(x, y)
    (EnumMember(x), EnumMember(y)) => physical_equal(x, y)
    (Property(x), Property(y)) => physical_equal(x, y)
    (Trait(x), Trait(y)) => physical_equal(x, y)
    (Value(x), Value(y)) => physical_equal(x, y)
    (Entry(x), Entry(y)) => physical_equal(x, y)
    (ShapeIdRef(x), ShapeIdRef(y)) => physical_equal(x, y)
    (Name(x), Name(y)) => physical_equal(x, y)
    (Doc(x), Doc(y)) => physical_equal(x, y)
    (Comment(x), Comment(y)) => physical_equal(x, y)
    _ => false
  }
}
