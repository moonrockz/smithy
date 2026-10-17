///|
/// Mutating one returned array cannot affect an earlier result or a later call.
fn[A : Eq + Debug] independent_arrays(
  get : () -> Array[A],
  marker : A,
) -> Unit raise {
  let first = get()
  let second = get()
  let expected = second.copy()
  assert_false(physical_equal(first, second))
  first.clear()
  first.push(marker)
  assert_eq(second, expected)
  assert_eq(get(), expected)
}

///|
test "node queries return independent arrays, including empty fields and leaves" {
  for root in kind_roots() {
    for node in all_nodes(root) {
      independent_arrays(() => node.fields(), "changed")
      independent_arrays(() => node.children(), root)
      independent_arrays(
        () => node.children_with_fields(),
        (@traversal.PathStep::{ field: "changed", index: 0, }, root),
      )
      for field in node.fields() {
        independent_arrays(() => node.field(field), root)
      }
      independent_arrays(() => node.field("unknown"), root)
    }
  }
}

///|
test "tree queries and path steps return independent arrays" {
  let tree = tree_of(every_form)
  let root = tree.root()
  for node in all_nodes(root) {
    independent_arrays(() => tree.ancestors(node), root)
    independent_arrays(() => tree.path(node), root)
    independent_arrays(() => tree.node_path(node).unwrap().steps(), @traversal.PathStep::{
      field: "changed",
      index: 0,
    })
  }
  let token = tree.tokens_in(root.span())[0]
  for span in [root.span(), @span.Offset::zero().to(@span.Offset::zero())] {
    independent_arrays(() => tree.tokens_in(span), token)
  }
}

///|
test "kind table rows and their field arrays are independent" {
  let first = @traversal.kind_table()
  let second = @traversal.kind_table()
  let expected = second.map(row => (row.0, row.1, row.2.copy()))
  assert_false(physical_equal(first, second))
  for i, row in first {
    assert_false(physical_equal(row.2, second[i].2))
    row.2.clear()
    row.2.push("changed")
  }
  first.clear()
  assert_eq(second, expected)
  assert_eq(@traversal.kind_table(), expected)
}
