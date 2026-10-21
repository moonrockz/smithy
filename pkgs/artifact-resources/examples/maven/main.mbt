///|
fn run() -> Unit raise {
  let args = arguments()
  guard args.is_empty() || args == ["--offline"] else {
    eprintln("usage: maven [--offline]")
    @sys.exit(2)
  }
  let request : @resources.MavenArchive = {
    repository: @resources.RepositoryUrl::parse(
      "https://repo.maven.apache.org/maven2",
    ).unwrap(),
    coordinates: {
      group: @resources.MavenGroupId::parse("software.amazon.smithy").unwrap(),
      artifact: @resources.MavenArtifactId::parse("smithy-aws-traits").unwrap(),
      version: @resources.MavenVersion::parse("1.72.0").unwrap(),
      classifier: None,
    },
    checksum: @resources.Sha1Sidecar,
    expected_digest: @resources.ContentDigest::parse(
      "sha256:1074d208fe17f0e92e30b40bfee7e4b34c799f8156960d92e50d5c5e5f789321",
    ),
  }
  let cache = @cache.open(
    @resources.CacheDirectory::parse(".dev/cache/maven-repository").unwrap(),
  )
  let tree = request.open(
    @http.transport,
    cache=Some(cache),
    mode=if args.is_empty() { @resources.Online } else { @resources.Offline },
  )
  let selection = @resources.Selection::new(
    @resources.ResourceRoot::parse("META-INF/smithy").unwrap(),
    [@resources.Exact(@resources.EntryPath::parse("aws.api.smithy").unwrap())],
  ).unwrap()
  let resource = @resources.select_resources(tree, selection)[0]
  println(resource.provenance)
  println(resource.text())
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
