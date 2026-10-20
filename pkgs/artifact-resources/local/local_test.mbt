///|
test "downloaded npm package exposes its Smithy model beneath package without installation" {
  let path = "../../examples/npm-archive/amazon-sqs-0.1.5.tgz"
  let registry = @local.register(@resources.Registry::new()).add_repository({
    id: @resources.RepositoryId::parse("npm-download").unwrap(),
    provider: @resources.ProviderId::parse("local").unwrap(),
    location: @resources.RepositoryLocation::parse(path).unwrap(),
  })
  let artifact = registry.resolve({
    repository: @resources.RepositoryId::parse("npm-download").unwrap(),
    key: @resources.ArtifactKey::parse(".").unwrap(),
  })
  let selection = @resources.Selection::new(
    @resources.ResourceRoot::parse("package/contract").unwrap(),
    [@resources.Exact(@resources.EntryPath::parse("smithy.json").unwrap())],
  ).unwrap()
  let model = @resources.select_resources(artifact.tree, selection)[0]
  let json = @json.parse(model.text())
  guard json is { "shapes": Object(shapes), .. } else {
    fail("Expected shapes")
  }
  assert_true(shapes.get("com.amazonaws.sqs#AmazonSQS") is Some(Object(_)))
  assert_eq(model.name.to_string(), "smithy.json")
  assert_eq(model.path.to_string(), "package/contract/smithy.json")
  assert_eq(model.origin.to_string(), path + "!/package/contract/smithy.json")
  assert_true(model.provenance.to_string().contains("npm-download[.] ->"))
  assert_eq(
    artifact.tree.digest,
    @resources.ContentDigest::parse(
      "sha256:d3b921a9d9ddf20a28bb2cbe631e78df83ec646ecf79a0d3ecb606dcad393a08",
    ),
  )
}
