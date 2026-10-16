///|
/// One method per node category, for `accept`. Every `visit_*` method
/// defaults to `Continue` and `leave` to nothing, so a visitor implements
/// only what it needs; the `Control` it returns steers the walk as in
/// `walk`.
pub(open) trait Visitor {
  /// The file.
  fn visit_file(Self, NodeRef) -> Control = _
  /// Control, metadata, namespace and use statements.
  fn visit_statement(Self, NodeRef) -> Control = _
  /// Shape statements, apply statements and inline shapes.
  fn visit_shape(Self, NodeRef) -> Control = _
  /// Members and enum members.
  fn visit_member(Self, NodeRef) -> Control = _
  /// Applied traits.
  fn visit_trait(Self, NodeRef) -> Control = _
  /// Node values and their object entries.
  fn visit_value(Self, NodeRef) -> Control = _
  /// Doc comments and comments.
  fn visit_comment(Self, NodeRef) -> Control = _
  /// Every other node: mixins, operation properties, shape IDs and names.
  fn visit_other(Self, NodeRef) -> Control = _
  /// Runs after a node's children, as in `walk`.
  fn leave(Self, NodeRef) -> Unit = _
}

///|
impl Visitor with fn visit_file(_self, _node) {
  Continue
}

///|
impl Visitor with fn visit_statement(_self, _node) {
  Continue
}

///|
impl Visitor with fn visit_shape(_self, _node) {
  Continue
}

///|
impl Visitor with fn visit_member(_self, _node) {
  Continue
}

///|
impl Visitor with fn visit_trait(_self, _node) {
  Continue
}

///|
impl Visitor with fn visit_value(_self, _node) {
  Continue
}

///|
impl Visitor with fn visit_comment(_self, _node) {
  Continue
}

///|
impl Visitor with fn visit_other(_self, _node) {
  Continue
}

///|
impl Visitor with fn leave(_self, _node) {
  ()
}

///|
fn[V : Visitor] dispatch(visitor : V, n : NodeRef) -> Control {
  match n {
    File(_, _) => visitor.visit_file(n)
    Control(_) | Metadata(_) | Namespace(_) | Use(_) =>
      visitor.visit_statement(n)
    Shape(_) | Apply(_) | Inline(_) => visitor.visit_shape(n)
    Member(_) | EnumMember(_) => visitor.visit_member(n)
    Trait(_) => visitor.visit_trait(n)
    Value(_) | Entry(_) => visitor.visit_value(n)
    Doc(_) | Comment(_) => visitor.visit_comment(n)
    Mixins(_) | Property(_) | ShapeIdRef(_) | Name(_) => visitor.visit_other(n)
  }
}

///|
/// Walk `root` and call one `Visitor` method per node by its category, and
/// `leave` after its children, in `walk`'s order.
///
/// A visitor is a type of yours with `impl Visitor` for the methods it
/// needs; its own fields hold its state.
pub fn[V : Visitor] accept(root : NodeRef, visitor : V) -> Unit {
  walk(root, n => dispatch(visitor, n), leave=n => visitor.leave(n))
}
