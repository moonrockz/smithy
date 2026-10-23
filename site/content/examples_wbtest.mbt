///|
fn dir(name : String, files : Array[String]) -> ExampleDir {
  { dir: name, title: "T " + name, files, }
}

///|
test "build: a directory without a README is skipped" {
  let found = Example::build([
    dir("local-resources", ["smithy-build.json", "models/service.smithy"]),
    dir("openrpc", ["README.md", "model.smithy"]),
    dir("ion-validation-consumer", ["main.mbtx"]),
  ])
  assert_eq(found.map(e => e.dir), ["openrpc"])
}

///|
test "build: a README in a subdirectory does not count" {
  assert_eq(Example::build([dir("a", ["docs/README.md"])]).length(), 0)
}

///|
test "build: examples sort by directory and keep the other files, not the README" {
  let found = Example::build([
    dir("zeta", ["README.md"]),
    dir("alpha", ["b.json", "README.md", "a/c.json"]),
  ])
  assert_eq(found.map(e => e.dir), ["alpha", "zeta"])
  assert_eq(found[0].files, ["a/c.json", "b.json"])
  assert_eq(found[0].title, "T alpha")
  assert_eq(found[1].files, [])
}

///|
test "source, find and find_source" {
  let found = Example::build([dir("openrpc", ["README.md"])])
  assert_eq(found[0].source(), "examples/openrpc/README.md")
  assert_eq(Example::find(found, "openrpc").map(e => e.dir), Some("openrpc"))
  assert_eq(Example::find(found, "nope"), None)
  assert_eq(
    Example::find_source(found, "./examples/openrpc/README.md").map(e => e.dir),
    Some("openrpc"),
  )
  assert_eq(Example::find_source(found, "examples/openrpc/model.smithy"), None)
}

///|
test "summary: known directories have one, others an empty one" {
  assert_true(example_summary("openrpc") != "")
  assert_eq(example_summary("not-an-example"), "")
}

///|
test "Example round-trips through JSON" {
  let e = Example::build([dir("openrpc", ["README.md", "model.smithy"])])[0]
  let back : Example = @json.from_json(Json(e))
  assert_eq(back, e)
}
