///|
fn selection(
  root : String,
  terms : Array[@resources.ResourceSelector],
) -> @resources.Selection {
  @resources.Selection::new(
    @resources.ResourceRoot::parse(root).unwrap(),
    terms,
  ).unwrap()
}

///|
fn glob(text : String) -> @resources.ResourceSelector {
  @resources.Matching(@resources.GlobPattern::parse(text).unwrap())
}

///|
test "explicit roots exact paths aliases and recursive globs agree across containers" {
  let files = {
    "module/data/root.txt": b"root",
    "module/data/nested/child.txt": b"child",
    "module/data/bytes.bin": b"\xff",
    "module/data/unused.txt": b"unused",
    "other/root.txt": b"other",
  }
  let choose = selection("module/data", [
    @resources.Exact(entry("root.txt")),
    @resources.Named(entry("bytes.bin"), logical("renamed.bin")),
    glob("nested/**/*.txt"),
    glob("**/root.txt"),
  ])
  for
    tree in [
      directory(files.keys().to_array(), path => files[path], "source-tree"),
      @resources.EntryTree::zip(archive(files), location("ordinary.zip")),
    ] {
    let loaded = @resources.select_resources(tree, choose)
    assert_eq(loaded.map(r => r.name.to_string()), [
      "nested/child.txt", "renamed.bin", "root.txt",
    ])
    assert_eq(loaded.map(r => r.path.to_string()), [
      "module/data/nested/child.txt", "module/data/bytes.bin", "module/data/root.txt",
    ])
    assert_eq(loaded.map(r => r.bytes), [b"child", b"\xff", b"root"])
    assert_eq(
      loaded[0].provenance.location().unwrap(),
      tree.entry_origin(entry("module/data/nested/child.txt")),
    )
  }
}

///|
test "glob components are case sensitive bounded and do not cross separators" {
  for
    (pattern, path, expected) in [
      ("*.txt", "a.txt", true),
      ("*.txt", "nested/a.txt", false),
      ("a?.txt", "ab.txt", true),
      ("a?.txt", "a.txt", false),
      ("**/a.txt", "a.txt", true),
      ("**/a.txt", "one/two/a.txt", true),
      ("one/**/a.txt", "one/a.txt", true),
      ("one/**/a.txt", "one/two/a.txt", true),
      ("*.txt", "A.TXT", false),
      ("**", "a/b", true),
      ("?.txt", "é.txt", true),
    ] {
    assert_eq(
      @resources.GlobPattern::parse(pattern).unwrap().matches(entry(path)),
      expected,
    )
  }
  for
    invalid in [
      "",
      "/a",
      "../*",
      "a//b",
      "a/**x",
      "a\\*",
      "[ab]",
      "{a,b}",
      "./a",
      "a/",
      "x".repeat(1025),
    ] {
    assert_true(@resources.GlobPattern::parse(invalid) is None)
  }
  let tree = directory(
    ["a.txt"],
    _ => b"",
    "tree",
    limits=@resources.Limits::new(max_match_steps=1),
  )
  assert_eq(
    error_code(() => ignore(tree.select(selection(".", [glob("*.txt")])))),
    "resource-limit",
  )
}

///|
test "every selector must match a file and roots remain inside the container" {
  let empty = @resources.EntryTree::directory([], _ => b"", location("tree"), directories=[
    entry("root/nested"),
  ])
  assert_eq(
    error_code(() => ignore(empty.select(selection("root", [glob("**")])))),
    "missing-selection",
  )
  let tree = @resources.EntryTree::directory(
    [entry("data/a")],
    _ => b"a",
    location("tree"),
    directories=[entry("empty")],
  )
  for
    (root, selectors, code) in [
      ("missing", [glob("**")], "missing-root"),
      ("empty", [glob("**")], "missing-selection"),
      (
        "data",
        [@resources.Exact(entry("a")), @resources.Exact(entry("missing"))],
        "missing-selection",
      ),
      (".", [@resources.Exact(entry("empty"))], "missing-selection"),
      ("data", [glob("*.smithy")], "missing-selection"),
    ] {
    assert_eq(
      error_code(() => ignore(tree.select(selection(root, selectors)))),
      code,
    )
  }
  for invalid in ["..", "../data", "/data", "data/", "data/./child"] {
    assert_true(@resources.ResourceRoot::parse(invalid) is None)
  }
  assert_true(@resources.Selection::new(@resources.ContainerRoot, []) is None)
  assert_true(
    @resources.Selection::new(
      @resources.ContainerRoot,
      Array::make(257, glob("**")),
    )
    is None,
  )
}

///|
test "overlaps deduplicate identical pairs and reject conflicting logical names" {
  let tree = directory(["a", "b"], _ => b"bytes", "tree")
  let choose = selection(".", [
    glob("**"),
    @resources.Exact(entry("a")),
    @resources.Named(entry("a"), logical("copy")),
  ])
  assert_eq(tree.select(choose).map(d => d.name.to_string()), ["a", "b", "copy"])
  assert_eq(
    error_code(() => {
      ignore(
        tree.select(
          selection(".", [
            @resources.Named(entry("a"), logical("same")),
            @resources.Named(entry("b"), logical("same")),
          ]),
        ),
      )
    }),
    "duplicate-resource",
  )
  let terms = [glob("**")]
  let copied = selection(".", terms)
  terms.clear()
  copied.selectors().clear()
  assert_eq(tree.select(copied).length(), 2)
}
