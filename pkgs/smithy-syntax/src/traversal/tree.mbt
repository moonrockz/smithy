///|
/// A parse result as a tree with random access: parents, ancestors, paths,
/// the node at an offset and the tokens in a span. It is built once and
/// never changes; its indexes are private.
pub struct Tree {
  priv root : NodeRef
  /// identity key → (node, parent, step in the parent) for every node below
  /// the root.
  priv parents : Map[String, Array[(NodeRef, NodeRef, PathStep)]]
  priv tokens : ArrayView[@scanner.Token]
}

///|
/// The index key of a node: category, kind and span. Two different nodes
/// with the same key are told apart by `same`.
fn identity(n : NodeRef) -> String {
  let s = n.span()
  "\{n.category()}/\{n.kind()}/\{s.start.0}+\{s.length.0}"
}

///|
/// The tree of `result`, or `None` when the parser read no AST. It walks the
/// whole tree once to index the parents, so build it once and keep it.
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
///   let tree = @traversal.Tree::new(r).unwrap()
///   let member = tree.root().field("shapes")[0].field("members")[0]
///   inspect(tree.parent(member).unwrap().kind(), content="structure")
///   debug_inspect(
///     tree.path(member).map(n => n.kind()),
///     content="[\"file\", \"structure\", \"member\"]",
///   )
///   inspect(tree.node_path(member).unwrap(), content="shapes[0].members[0]")
/// }
/// ```
pub fn Tree::new(result : @parser.ParseResult) -> Tree? {
  guard NodeRef::of_result(result) is Some(root) else { return None }
  let parents : Map[String, Array[(NodeRef, NodeRef, PathStep)]] = Map([])
  // An explicit stack: no recursion in any walk.
  let stack = [root]
  while stack.pop() is Some(node) {
    for entry in node.children_with_fields() {
      let (step, child) = entry
      let key = identity(child)
      let item = (child, node, step)
      match parents.get(key) {
        Some(bucket) => bucket.push(item)
        None => parents[key] = [item]
      }
      stack.push(child)
    }
  }
  Some({ root, parents, tokens: result.cst.tokens, })
}

///|
/// The root: the file node.
pub fn Tree::root(self : Tree) -> NodeRef {
  self.root
}

///|
/// The parent of `n`, or `None` for the root and for a node not in the tree.
pub fn Tree::parent(self : Tree, n : NodeRef) -> NodeRef? {
  self.parent_entry(n).map(e => e.0)
}

///|
/// The field and index of `n` in its parent, or `None` for the root.
pub fn Tree::step(self : Tree, n : NodeRef) -> PathStep? {
  self.parent_entry(n).map(e => e.1)
}

///|
/// The field of `n` in its parent, or `None` for the root.
pub fn Tree::field_of(self : Tree, n : NodeRef) -> String? {
  self.parent_entry(n).map(e => e.1.field)
}

///|
fn Tree::parent_entry(self : Tree, n : NodeRef) -> (NodeRef, PathStep)? {
  // Only the root is a file, and it has no parent. Its span joins every
  // comment, so skipping it keeps each lookup independent of the comments.
  if n is File(_, _) {
    return None
  }
  guard self.parents.get(identity(n)) is Some(bucket) else { return None }
  for entry in bucket {
    if same(entry.0, n) {
      return Some((entry.1, entry.2))
    }
  }
  None
}

///|
/// The ancestors of `n`, nearest first (a new array).
pub fn Tree::ancestors(self : Tree, n : NodeRef) -> Array[NodeRef] {
  let found = []
  let mut current = n
  while self.parent(current) is Some(p) {
    found.push(p)
    current = p
  }
  found
}

///|
/// The nodes from the root down to `n`, `n` included (a new array).
pub fn Tree::path(self : Tree, n : NodeRef) -> Array[NodeRef] {
  let path = self.ancestors(n)
  path.rev_in_place()
  path.push(n)
  path
}

///|
/// The path of `n` from the root, or `None` for a node not in the tree.
pub fn Tree::node_path(self : Tree, n : NodeRef) -> NodePath? {
  // Up the parent index (the steps nearest first), then down from the root.
  let steps = []
  let mut current = n
  while self.parent_entry(current) is Some((parent, step)) {
    steps.push(step)
    current = parent
  }
  guard same(current, self.root) else { return None }
  let mut path = NodePath::root()
  for step in steps.rev_iter() {
    path = path.child(step.field, step.index)
  }
  Some(path)
}

///|
/// Whether span `a` lies inside span `b`.
fn within(a : @span.Span, b : @span.Span) -> Bool {
  b.start <= a.start && a.end() <= b.end()
}

///|
/// The innermost node that contains `offset`, or `None` when the root does
/// not contain it. A doc comment's offset gives the `doc` node.
pub fn Tree::node_at(self : Tree, offset : @span.Offset) -> NodeRef? {
  innermost_at(self.root, offset).map(found => found.0)
}

///|
/// The innermost node below `start` that contains `offset`, with the child
/// indices from `start` down to it.
fn innermost_at(
  start : NodeRef,
  offset : @span.Offset,
) -> (NodeRef, Array[Int32])? {
  if !start.span().contains(offset) {
    return None
  }
  let mut best = start
  let mut best_trail : @list.List[Int32] = @list.List([])
  let mut best_depth = 0
  // An explicit stack, visited in source order. A trail holds the child
  // indices from `start`, innermost first.
  let stack : Array[(NodeRef, Int32, @list.List[Int32])] = [
    (start, 0, @list.List([])),
  ]
  while stack.pop() is Some((node, depth, trail)) {
    let s = node.span()
    let b = best.span()
    if (within(s, b) && s != b) || (s == b && depth > best_depth) {
      best = node
      best_trail = trail
      best_depth = depth
    }
    let kids = node.children()
    for i = kids.length() - 1; i >= 0; i = i - 1 {
      if kids[i].span().contains(offset) {
        stack.push((kids[i], depth + 1, trail.prepend(i)))
      }
    }
  }
  let indices = best_trail.to_array()
  indices.rev_in_place()
  Some((best, indices))
}

///|
/// The tokens that lie inside `span`, in order (a new array; tokens and
/// their trivia are read-only).
pub fn Tree::tokens_in(self : Tree, span : @span.Span) -> Array[@scanner.Token] {
  self.tokens.iter().filter(t => within(t.span, span)).to_array()
}
