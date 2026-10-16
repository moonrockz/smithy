///|
/// One step of a path: the field that holds a child and its index there.
pub(all) struct PathStep {
  field : String
  index : Int32
} derive(Eq, Hash, Debug)

///|
/// The steps from a start node down to a node: the field and index of each
/// child on the way, like a path into the Smithy JSON AST
/// (`shapes[2].members[0].target[0]`). It is immutable; a child's path shares
/// its parent's steps.
///
/// ```mbt check
/// test {
///   let r = @parser.parse_text(
///     (
///       #|namespace a
///       #|
///       #|structure Foo {
///       #|    x: String
///       #|}
///       #|
///     ),
///   )
///   let root = @traversal.NodeRef::of_result(r).unwrap()
///   let path = @traversal.NodePath::root()
///     .child("shapes", 0)
///     .child("members", 0)
///     .child("target", 0)
///   inspect(path, content="shapes[0].members[0].target[0]")
///   debug_inspect(
///     path.resolve(root).map(n => n.kind()),
///     content="Some(\"shape_id\")",
///   )
/// }
/// ```
pub struct NodePath {
  /// The steps, innermost first.
  priv reversed : @list.List[PathStep]
  priv length : Int32
} derive(Eq, Hash)

///|
/// The path of the start node itself: no steps.
pub fn NodePath::root() -> NodePath {
  { reversed: @list.List([]), length: 0, }
}

///|
/// The path of the child at `index` in `field` of the node at this path.
pub fn NodePath::child(
  self : NodePath,
  field : String,
  index : Int32,
) -> NodePath {
  {
    reversed: self.reversed.prepend({ field, index, }),
    length: self.length + 1,
  }
}

///|
/// The path with these steps, from the start node down.
pub fn NodePath::from_steps(steps : ArrayView[PathStep]) -> NodePath {
  let mut path = NodePath::root()
  for step in steps {
    path = path.child(step.field, step.index)
  }
  path
}

///|
/// This path's steps followed by the steps of `rest`.
pub fn NodePath::append(self : NodePath, rest : NodePath) -> NodePath {
  let mut path = self
  for step in rest.steps() {
    path = path.child(step.field, step.index)
  }
  path
}

///|
/// The number of steps.
pub fn NodePath::depth(self : NodePath) -> Int32 {
  self.length
}

///|
/// The steps from the start node down (a new array).
pub fn NodePath::steps(self : NodePath) -> Array[PathStep] {
  let steps = self.reversed.to_array()
  steps.rev_in_place()
  steps
}

///|
/// The last step, or `None` for the start node.
pub fn NodePath::last(self : NodePath) -> PathStep? {
  self.reversed.head()
}

///|
/// The path of the parent, or `None` for the start node.
pub fn NodePath::parent(self : NodePath) -> NodePath? {
  match self.reversed {
    More(_, tail~) => Some({ reversed: tail, length: self.length - 1, })
    Empty => None
  }
}

///|
/// The node this path reaches from `start`, or `None` where a step does not
/// exist.
pub fn NodePath::resolve(self : NodePath, start : NodeRef) -> NodeRef? {
  let mut n = start
  for step in self.steps() {
    guard n.field(step.field).get(step.index) is Some(c) else { return None }
    n = c
  }
  Some(n)
}

///|
/// `field[index].field[index]...`, from the start node down; empty for the
/// start node.
pub impl Show for NodePath with fn output(self, logger) {
  logger.write_string(self.steps().map(s => "\{s.field}[\{s.index}]").join("."))
}

///|
/// `{ steps: [...] }`, the steps from the start node down.
pub impl @debug.Debug for NodePath with fn to_repr(self) {
  let steps = self.steps().map(s => @debug.Repr(s))
  @debug.Repr::record({ "steps": @debug.Repr::array(steps) })
}
