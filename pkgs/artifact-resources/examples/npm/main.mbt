///|
/// Inspect a downloaded npm contract without extracting or executing its code.
fn run() -> Unit raise {
  let tree = @local_resources.open(
    @resources.RepositoryLocation::parse(
      "examples/npm-archive/amazon-sqs-0.1.5.tgz",
    ).unwrap(),
  )
  let selection = @resources.Selection::new(
    @resources.ResourceRoot::parse("package/contract").unwrap(),
    [@resources.Exact(@resources.EntryPath::parse("smithy.json").unwrap())],
  ).unwrap()
  let model = @resources.select_resources(tree, selection)[0]
  let json = @json.parse(model.text())
  guard json is { "shapes": Object(shapes), .. } else {
    fail("Expected Smithy JSON shapes")
  }
  println(model.name)
  println(model.origin)
  println("\{shapes.length()} shapes")
}

///|
fn main {
  run() catch {
    error => {
      eprintln(error)
      @sys.exit(1)
    }
  }
}
