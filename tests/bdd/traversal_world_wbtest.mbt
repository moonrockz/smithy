///|
/// Scenario state for the traversal feature.
struct TraversalWorld {
  mut text : String
  mut tree : @syntax.Tree?
}

///|
/// Start a scenario before any tree has been built.
fn TraversalWorld::new() -> TraversalWorld {
  { text: "", tree: None, }
}

///|
/// Require the tree produced by the scenario's build step.
fn TraversalWorld::the_tree(self : TraversalWorld) -> @syntax.Tree raise {
  guard self.tree is Some(t) else { fail("the tree was not built yet") }
  t
}

///|
/// Every node in pre-order, by an explicit stack.
fn every_node(root : @syntax.NodeRef) -> Array[@syntax.NodeRef] {
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
/// Identify an occurrence by its category, kind and source span.
fn node_tag(n : @syntax.NodeRef) -> String {
  let s = n.span()
  "\{n.category()}/\{n.kind()}@\{s.start.0}+\{s.length.0}"
}

///|
/// The rows of the markdown table between the kind markers, as
/// `category/kind: fields`.
fn readme_rows(text : String) -> Array[String] raise {
  guard text.find("<!-- kinds:start -->") is Some(a) &&
    text.find("<!-- kinds:end -->") is Some(b) else {
    fail("no kind markers")
  }
  let rows = []
  for line in text.unsafe_substring(start=a, end=b).split("\n") {
    let cells = line.split("|").map(c => c.trim().to_owned()).to_array()
    // A row is `| `c` | `k` | fields |`: five cells with the empty ends.
    if cells.length() == 5 && cells[1].has_prefix("`") {
      let c = cells[1].replace_all(old="`", new="")
      let k = cells[2].replace_all(old="`", new="")
      let f = if cells[3] == "—" { "" } else { cells[3] }
      rows.push("\{c}/\{k}: \{f}")
    }
  }
  rows
}

///|
impl @moonspec.World for TraversalWorld with fn configure(self, setup) {
  setup.given1("the TCK case {string}", fn(path : String) raise {
    for c in @tck.cases() {
      if c.path == path {
        self.text = c.text
        return
      }
    }
    fail("no TCK case \{path}")
  })
  setup.when0("I build the syntax tree", fn() raise {
    guard @syntax.Tree::new(@syntax.parse_idl(self.text)) is Some(t) else {
      fail("no tree")
    }
    self.tree = Some(t)
  })
  setup.then0("every child lies inside its parent, in source order", fn() raise {
    for n in every_node(self.the_tree().root()) {
      let p = n.span()
      let cs = n.children()
      for i, c in cs {
        let s = c.span()
        if s.start < p.start || s.end() > p.end() {
          fail("\{node_tag(c)} is outside \{node_tag(n)}")
        }
        if i > 0 && cs[i - 1].span().start > s.start {
          fail("\{node_tag(c)} is out of order in \{node_tag(n)}")
        }
      }
    }
  })
  setup.then0("every child's parent is the identical node it came from", fn() raise {
    let tree = self.the_tree()
    for n in every_node(tree.root()) {
      for c in n.children() {
        if tree.parent(c).map(parent => same_node(parent, n)) != Some(true) {
          fail("wrong parent for \{node_tag(c)}")
        }
      }
    }
  })
  setup.then0("every node's fields match the kind table", fn() raise {
    let table = Map([])
    for row in @syntax.kind_table() {
      table["\{row.0}/\{row.1}"] = row.2
    }
    for n in every_node(self.the_tree().root()) {
      let key = "\{n.category()}/\{n.kind()}"
      guard table.get(key) is Some(fields) else { fail("no row for \{key}") }
      if n.fields() != fields {
        fail("fields of \{key} differ from the table")
      }
    }
  })
  setup.then0(
    "node_at at the start of every node finds that node or a descendant",
    fn() raise {
      let tree = self.the_tree()
      for n in every_node(tree.root()) {
        if n.span().is_empty() {
          continue
        }
        guard tree.node_at(n.span().start) is Some(m) else {
          fail("nothing at \{node_tag(n)}")
        }
        if !same_node(m, n) &&
          !tree.ancestors(m).iter().any(parent => same_node(parent, n)) {
          fail("node_at(\{node_tag(n)}) gives \{node_tag(m)}")
        }
      }
    },
  )
  setup.then0(
    "walk, fold, reduce, the event reader and the cursor enter the same nodes",
    fn() raise {
      let root = self.the_tree().root()
      let expected = every_node(root).map(node_tag)
      let walked = []
      @syntax.walk(root, n => {
        walked.push(node_tag(n))
        Continue
      })
      let folded = @syntax.fold(root, [], (acc, n) => {
        acc.push(node_tag(n))
        (acc, Continue)
      })
      let count = @syntax.reduce(root, (_, rs : ArrayView[Int32]) => {
        1 + rs.iter().fold(init=0, (a, b) => a + b)
      })
      let read = []
      for e in @syntax.EventReader::new(root).iter() {
        if e is Enter(e) {
          read.push(e.path)
        }
      }
      let c = @syntax.TreeCursor::new(root)
      let toured = [node_tag(c.node())]
      let mut done = false
      while !done {
        if c.goto_first_child() {
          toured.push(node_tag(c.node()))
          continue
        }
        while !c.goto_next_sibling() {
          if !c.goto_parent() {
            done = true
            break
          }
        }
        if !done {
          toured.push(node_tag(c.node()))
        }
      }
      let resolved = read.map(p => p.resolve(root).map(node_tag).unwrap_or("?"))
      if walked != expected ||
        folded != expected ||
        count != expected.length() ||
        resolved != expected ||
        toured != expected {
        fail("the styles disagree")
      }
    },
  )
  setup.given1("the file {string}", fn(path : String) raise {
    // The tests run in the tests module, one level below the repository root.
    self.text = @xfs.read_file_to_string("../\{path}")
  })
  setup.then0("the kind table between the markers matches the node model", fn() raise {
    let expected = @syntax.kind_table().map(r => {
      "\{r.0}/\{r.1}: \{r.2.join(", ")}"
    })
    let rows = readme_rows(self.text)
    let a : Set[String] = Set([])
    let b : Set[String] = Set([])
    for x in rows {
      a.add(x)
    }
    for x in expected {
      b.add(x)
    }
    for x in expected {
      if !a.contains(x) {
        fail("the README lacks the row \{x}")
      }
    }
    for x in rows {
      if !b.contains(x) {
        fail("the README has a row the code does not: \{x}")
      }
    }
    if rows.length() != expected.length() {
      fail(
        "the README has \{rows.length()} rows, the code \{expected.length()}",
      )
    }
  })
}

///|
async test "traversal feature" {
  @moonspec.run_or_fail(
    TraversalWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/traversal.feature"),
    ]),
  )
  |> ignore
}

///|
/// Compare AST object identity even when child enumeration rebuilds wrappers.
fn same_node(a : @syntax.NodeRef, b : @syntax.NodeRef) -> Bool {
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
