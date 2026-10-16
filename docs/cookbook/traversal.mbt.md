# Traverse a model

The traversal gives one node model over the AST: `category`, `kind`,
`fields` and `children` for every node, with names from the Smithy JSON AST.
Every style is a loop with its own stack, so deep models work on every
target.

## List every shape and its kind

```mbt check
///|
test "list every shape and its kind" {
  let r = @syntax.parse_idl(
    (
      #|$version: "2"
      #|namespace com.example
      #|
      #|string Name
      #|structure Person {
      #|    name: Name
      #|}
      #|apply Person @sensitive
      #|
    ),
  )
  let root = @syntax.NodeRef::of_result(r).unwrap()
  let shapes = []
  @syntax.walk(root, n => {
    if n.category() == "shape" {
      shapes.push(n.kind())
      SkipChildren
    } else {
      Continue
    }
  })
  debug_inspect(shapes, content="[\"string\", \"structure\", \"apply\"]")
}
```

## Collect every trait ID

```mbt check
///|
test "collect every trait ID" {
  let r = @syntax.parse_idl(
    (
      #|$version: "2"
      #|namespace com.example
      #|
      #|@documentation("A person.")
      #|structure Person {
      #|    @required
      #|    name: String
      #|}
      #|
    ),
  )
  let root = @syntax.NodeRef::of_result(r).unwrap()
  let ids = @syntax.fold(root, [], (acc, n) => {
    if n is Trait(t) {
      acc.push(t.id.value.to_string())
    }
    (acc, Continue)
  })
  debug_inspect(ids, content="[\"documentation\", \"required\"]")
}
```

## Count the members of each shape

`reduce` works bottom up: each node gets the results of its children.

```mbt check
///|
test "count the members of each shape" {
  let r = @syntax.parse_idl(
    (
      #|$version: "2"
      #|namespace com.example
      #|
      #|structure Person {
      #|    name: String
      #|    age: Integer
      #|}
      #|enum Color {
      #|    RED
      #|}
      #|
    ),
  )
  let root = @syntax.NodeRef::of_result(r).unwrap()
  // Each node gives the "Shape=count" lines below it; a member counts 1.
  let lines = @syntax.reduce(root, (n, rs : ArrayView[Array[String]]) => {
    match n {
      Shape(s) => {
        let count = n.field("members").length()
        ["\{s.shape.name().value}=\{count}"]
      }
      _ => rs.iter().flat_map(xs => xs.iter()).to_array()
    }
  })
  debug_inspect(lines, content="[\"Person=2\", \"Color=1\"]")
}
```

## Find the node at an offset

An editor asks what is under the cursor. `Tree::node_at` gives the
innermost node, and `node_path` gives where it is, as a path into the JSON
AST.

```mbt check
///|
test "find the node at an offset" {
  let text =
    #|$version: "2"
    #|namespace com.example
    #|
    #|structure Person {
    #|    name: String
    #|}
    #|
  let tree = @syntax.Tree::new(@syntax.parse_idl(text)).unwrap()
  let at = @syntax.Offset::new(text.find("String").unwrap()).unwrap()
  let node = tree.node_at(at).unwrap()
  inspect(node.kind(), content="shape_id")
  inspect(
    tree.node_path(node).unwrap(),
    content="shapes[0].members[0].target[0]",
  )
  inspect(tree.parent(node).unwrap().kind(), content="member")
}
```
