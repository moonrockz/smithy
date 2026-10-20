///|
fn run() -> Unit raise @resources.ResourceError {
  let args = arguments()
  guard args.is_empty() || args == ["--offline"] else {
    eprintln("usage: github [--offline]")
    @sys.exit(2)
  }
  let request : @resources.GitHubArchive = {
    repository: @resources.GitHubRepository::parse("sharkdp/bat").unwrap(),
    reference: {
      tag: @resources.GitHubTag::parse("v0.25.0").unwrap(),
      asset: @resources.GitHubAssetName::parse(
        "bat-v0.25.0-x86_64-pc-windows-msvc.zip",
      ).unwrap(),
    },
    format: @resources.Zip,
    expected_digest: @resources.ContentDigest::parse(
      "sha256:1d5ced071ba9c765e16f4065877c178cefcfd2fe9581e9ddc92af265b73991bd",
    ),
  }
  let cache = @cache.open(
    @resources.CacheDirectory::parse(".dev/cache/github-release").unwrap(),
  )
  let tree = request.open(
    @http.transport,
    cache=Some(cache),
    mode=if args.is_empty() { @resources.Online } else { @resources.Offline },
  )
  let selection = @resources.Selection::new(
    @resources.ResourceRoot::parse("bat-v0.25.0-x86_64-pc-windows-msvc").unwrap(),
    [@resources.Exact(@resources.EntryPath::parse("LICENSE-MIT").unwrap())],
  ).unwrap()
  for resource in @resources.select_resources(tree, selection) {
    println(resource.provenance)
    println(resource.text())
  }
}

///|
fn main {
  run() catch {
    @resources.ResourceError(code, at, message) => {
      eprintln(code.to_string() + ": " + at.to_string() + ": " + message)
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
