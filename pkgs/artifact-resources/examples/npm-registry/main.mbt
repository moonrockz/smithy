///|
fn run() -> Unit raise {
  let args = arguments()
  guard args.is_empty() || args == ["--offline"] else {
    eprintln("usage: npm-registry [--offline]")
    @sys.exit(2)
  }
  let request : @resources.NpmArchive = {
    registry: @resources.RepositoryUrl::parse("https://registry.npmjs.org").unwrap(),
    reference: {
      name: @resources.NpmPackageName::parse("@pontx/amazon-sqs").unwrap(),
      version: @resources.NpmVersion::parse("0.1.5").unwrap(),
    },
    expected_digest: @resources.ContentDigest::parse(
      "sha256:d3b921a9d9ddf20a28bb2cbe631e78df83ec646ecf79a0d3ecb606dcad393a08",
    ),
  }
  let cache = @cache.open(
    @resources.CacheDirectory::parse(".dev/cache/npm-registry").unwrap(),
  )
  let tree = request.open(
    @http.transport,
    cache=Some(cache),
    mode=if args.is_empty() { @resources.Online } else { @resources.Offline },
  )
  let selection = @resources.Selection::new(
    @resources.ResourceRoot::parse("package/contract").unwrap(),
    [@resources.Exact(@resources.EntryPath::parse("smithy.json").unwrap())],
  ).unwrap()
  let resource = @resources.select_resources(tree, selection)[0]
  let document = @json.parse(resource.text())
  guard document is { "shapes": Object(shapes), .. } else {
    fail("Expected Smithy JSON shapes")
  }
  println(resource.provenance)
  println("\{shapes.length()} shapes")
}

///|
fn main {
  run() catch {
    @resources.ResourceError(code, at, message) => {
      eprintln(code.to_string() + ": " + at.to_string() + ": " + message)
      @sys.exit(1)
    }
    error => {
      eprintln(error)
      @sys.exit(1)
    }
  }
}

///|
#cfg(target="js")
fn arguments() -> Array[String] {
  @env.args()[2:].to_owned()
}

///|
#cfg(not(target="js"))
fn arguments() -> Array[String] {
  @env.args()[1:].to_owned()
}
