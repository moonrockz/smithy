///|
/// One level of a cursor: the siblings at that level (with each one's step in
/// the parent; `None` for the start node), the path of their parent, and the
/// index of the current one.
priv struct CursorFrame {
  siblings : Array[(PathStep?, NodeRef)]
  parent_path : NodePath
  mut index : Int32
}

///|
/// A cursor that the caller moves through the tree, as in tree-sitter. Each
/// `goto_*` returns `false` and leaves the cursor in place when there is
/// nowhere to go. The cursor keeps its own stack of levels, so it never
/// recurses.
///
/// ```mbt check
/// test {
///   let r = @parser.parse_text("namespace a\n\nstring S\n")
///   let c = @traversal.TreeCursor::new(@traversal.NodeRef::of_result(r).unwrap())
///   inspect(c.goto_first_child(), content="true")
///   debug_inspect(c.field_name(), content="Some(\"namespace\")")
///   inspect(c.goto_next_sibling(), content="true")
///   inspect(c.path(), content="shapes[0]")
///   inspect(c.goto_next_sibling(), content="false")
/// }
/// ```
pub struct TreeCursor {
  priv frames : Array[CursorFrame]
}

///|
/// A cursor at `root`, its start node.
pub fn TreeCursor::new(root : NodeRef) -> TreeCursor {
  {
    frames: [
      { siblings: [(None, root)], parent_path: NodePath::root(), index: 0, },
    ],
  }
}

///|
fn TreeCursor::top(self : TreeCursor) -> CursorFrame {
  self.frames[self.frames.length() - 1]
}

///|
/// The node at the cursor.
pub fn TreeCursor::node(self : TreeCursor) -> NodeRef {
  let f = self.top()
  f.siblings[f.index].1
}

///|
/// The field of the node in its parent; `None` at the start node.
pub fn TreeCursor::field_name(self : TreeCursor) -> String? {
  let f = self.top()
  f.siblings[f.index].0.map(step => step.field)
}

///|
/// The path of the node from the start node.
pub fn TreeCursor::path(self : TreeCursor) -> NodePath {
  let f = self.top()
  match f.siblings[f.index].0 {
    Some(step) => f.parent_path.child(step.field, step.index)
    None => f.parent_path
  }
}

///|
/// The number of levels below the start node.
pub fn TreeCursor::depth(self : TreeCursor) -> Int32 {
  self.frames.length() - 1
}

///|
fn TreeCursor::descend(
  self : TreeCursor,
  choose : (Array[(PathStep?, NodeRef)]) -> Int32?,
) -> Bool {
  let kids = self.node().children_with_fields().map(x => (Some(x.0), x.1))
  guard choose(kids) is Some(i) else { return false }
  let parent_path = self.path()
  self.frames.push({ siblings: kids, parent_path, index: i, })
  true
}

///|
/// Move to the first child.
pub fn TreeCursor::goto_first_child(self : TreeCursor) -> Bool {
  self.descend(kids => if kids.is_empty() { None } else { Some(0) })
}

///|
/// Move to the last child.
pub fn TreeCursor::goto_last_child(self : TreeCursor) -> Bool {
  self.descend(kids => {
    if kids.is_empty() {
      None
    } else {
      Some(kids.length() - 1)
    }
  })
}

///|
/// Move to the next sibling.
pub fn TreeCursor::goto_next_sibling(self : TreeCursor) -> Bool {
  let f = self.top()
  if f.index + 1 < f.siblings.length() {
    f.index = f.index + 1
    true
  } else {
    false
  }
}

///|
/// Move to the previous sibling.
pub fn TreeCursor::goto_previous_sibling(self : TreeCursor) -> Bool {
  let f = self.top()
  if f.index > 0 {
    f.index = f.index - 1
    true
  } else {
    false
  }
}

///|
/// Move to the parent; `false` at the start node.
pub fn TreeCursor::goto_parent(self : TreeCursor) -> Bool {
  if self.frames.length() > 1 {
    ignore(self.frames.pop())
    true
  } else {
    false
  }
}

///|
/// Move to the innermost child that contains `offset`, or else to the first
/// child that starts after it. A plain loop of this call can go one node too
/// far when that node has children after the offset; use `goto_node_at` to
/// reach the node at an offset.
pub fn TreeCursor::goto_first_child_for(
  self : TreeCursor,
  offset : @span.Offset,
) -> Bool {
  self.descend(kids => {
    let mut best : Int32? = None
    for i, x in kids {
      let s = x.1.span()
      if s.contains(offset) {
        match best {
          None => best = Some(i)
          Some(b) => {
            let bs = kids[b].1.span()
            if within(s, bs) && s != bs {
              best = Some(i)
            }
          }
        }
      }
    }
    match best {
      Some(_) => best
      None => kids.search_by(x => x.1.span().start > offset)
    }
  })
}

///|
/// Move to the innermost node below the cursor's node that contains
/// `offset`, the rule of `Tree::node_at`. `false`, and no move, when the
/// cursor's node does not contain it.
pub fn TreeCursor::goto_node_at(
  self : TreeCursor,
  offset : @span.Offset,
) -> Bool {
  guard innermost_at(self.node(), offset) is Some((_, indices)) else {
    return false
  }
  for i in indices {
    ignore(self.descend(_ => Some(i)))
  }
  true
}

///|
/// Move the cursor to `node`, as a new start node.
pub fn TreeCursor::reset(self : TreeCursor, node : NodeRef) -> Unit {
  self.frames.clear()
  self.frames.push({
    siblings: [(None, node)],
    parent_path: NodePath::root(),
    index: 0,
  })
}

///|
/// An independent cursor at the same place.
pub fn TreeCursor::copy(self : TreeCursor) -> TreeCursor {
  {
    frames: self.frames.map(f => {
      siblings: f.siblings,
      parent_path: f.parent_path,
      index: f.index,
    }),
  }
}
