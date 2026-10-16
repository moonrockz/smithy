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
