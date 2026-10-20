///|
fn main raise {
  let archive : @resources.PublicArchive = {
    url: @resources.HttpUrl::parse(
      "https://codeload.github.com/moonrockz/smithy/zip/f66a4a77685902ffed964c63ecbabd0fd2465ab4",
    ).unwrap(),
    format: @resources.Zip,
    expected_digest: @resources.ContentDigest::parse(
      "sha256:7a191fd47666fd9cb0ef3b4e1cd4561e31d412fcb7205f1a0fb742b723d3faa2",
    ),
  }
  let selection = @resources.Selection::new(
    @resources.ResourceRoot::parse(
      "smithy-f66a4a77685902ffed964c63ecbabd0fd2465ab4/examples/local-resources/imports",
    ).unwrap(),
    [@resources.Exact(@resources.EntryPath::parse("shared.smithy").unwrap())],
  ).unwrap()
  let args = @env.args()[1:].to_owned()
  guard args.is_empty() || args == ["--offline"] else {
    abort("usage: public [--offline]")
  }
  let cache = @cache.open(
    @resources.RepositoryLocation::parse(".dev/cache/public-archive").unwrap(),
  )
  let tree = archive.open(
    @http.transport,
    cache=Some(cache),
    mode=if args.is_empty() { @resources.Online } else { @resources.Offline },
  )
  for resource in @resources.select_resources(tree, selection) {
    println(resource.provenance)
    println(resource.text())
  }
}
