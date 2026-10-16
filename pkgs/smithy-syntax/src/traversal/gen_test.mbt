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
