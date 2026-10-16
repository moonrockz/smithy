///|
/// Thread an accumulator through a walk of `root`: `enter` gets the
/// accumulator and the node and returns the new accumulator and the
/// `Control` for the node; `leave` gets the accumulator after the node's
/// children. The calls come in `walk`'s order.
///
/// ```mbt check
/// test {
///   let r = @parser.parse_text("namespace a\n\nstring S\n")
///   let root = @traversal.NodeRef::of_result(r).unwrap()
///   let names = @traversal.fold(root, [], (acc, n) => {
///     if n is Name(name) {
///       acc.push(name.value)
///     }
///     (acc, Continue)
///   })
///   debug_inspect(names, content="[\"a\", \"S\"]")
/// }
/// ```
pub fn[A] fold(
  root : NodeRef,
  init : A,
  enter : (A, NodeRef) -> (A, Control),
  leave~ : (A, NodeRef) -> A = (a, _) => a,
) -> A {
  let mut acc = init
  walk(
    root,
    n => {
      let (next, control) = enter(acc, n)
      acc = next
      control
    },
    leave=n => acc = leave(acc, n),
  )
  acc
}

///|
/// One open node of a bottom-up run, with the results of its finished
/// children.
priv struct ReduceFrame[R] {
  node : NodeRef
  children : Array[NodeRef]
  mut next : Int32
  results : Array[R]
}

///|
/// The engine of `reduce` and `reduce_pruned`: post-order with an explicit
/// stack. `None` when `enter` says `Stop`.
fn[R] reduce_engine(
  root : NodeRef,
  enter : (NodeRef) -> Control,
  f : (NodeRef, ArrayView[R]) -> R,
) -> R? {
  let none : Array[R] = []
  match enter(root) {
    Stop => return None
    SkipChildren => return Some(f(root, none[:]))
    Continue => ()
  }
  let stack = [{ node: root, children: root.children(), next: 0, results: [], }]
  while stack.last() is Some(top) {
    if top.next < top.children.length() {
      let child = top.children[top.next]
      top.next = top.next + 1
      match enter(child) {
        Stop => return None
        SkipChildren => top.results.push(f(child, none[:]))
        Continue =>
          stack.push({
            node: child,
            children: child.children(),
            next: 0,
            results: [],
          })
      }
    } else {
      ignore(stack.pop())
      let r = f(top.node, top.results[:])
      match stack.last() {
        Some(parent) => parent.results.push(r)
        None => return Some(r)
      }
    }
  }
  None
}

///|
/// Reduce `root` bottom up: `f` gets each node with the results of its
/// children, in `children()` order, so index `i` matches
/// `children_with_fields()[i]`. The calls to `f` come in the order of
/// `walk`'s `leave` calls, and every node is reduced.
///
/// ```mbt check
/// test {
///   let r = @parser.parse_text(
///     (
///       #|namespace a
///       #|
///       #|structure Foo {
///       #|    a: String
///       #|}
///       #|
///     ),
///   )
///   let root = @traversal.NodeRef::of_result(r).unwrap()
///   let outline = @traversal.reduce(root, (n, rs) => {
///     if rs.length() == 0 {
///       n.kind()
///     } else {
///       n.kind() + "(" + rs.iter().join(",") + ")"
///     }
///   })
///   inspect(
///     outline,
///     content="file(namespace(name),structure(name,member(name,shape_id)))",
///   )
/// }
/// ```
pub fn[R] reduce(root : NodeRef, f : (NodeRef, ArrayView[R]) -> R) -> R {
  match reduce_engine(root, _ => Continue, f) {
    Some(r) => r
    None => abort("reduce: unreachable, nothing returns Stop")
  }
}

///|
/// `reduce`, steered as `walk` is: `enter` runs before a node's children.
/// `Continue` reduces the children; `SkipChildren` does not enter them and
/// calls `f` with no results for that node; `Stop` ends the run with no
/// further calls, and the result is `None`. With `Continue` throughout it is
/// `Some` of what `reduce` gives.
pub fn[R] reduce_pruned(
  root : NodeRef,
  enter : (NodeRef) -> Control,
  f : (NodeRef, ArrayView[R]) -> R,
) -> R? {
  reduce_engine(root, enter, f)
}
