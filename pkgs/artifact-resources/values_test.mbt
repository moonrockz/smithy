///|
test "domain constructors reject invalid values and preserve valid values" {
  for invalid in ["", "   ", "bad\nvalue", "bad\u007fvalue"] {
    assert_true(@resources.RepositoryId::parse(invalid) is None)
    assert_true(@resources.ProviderId::parse(invalid) is None)
    assert_true(@resources.ArtifactKey::parse(invalid) is None)
    assert_true(@resources.ArtifactIdentity::parse(invalid) is None)
    assert_true(@resources.RepositoryLocation::parse(invalid) is None)
    assert_true(@resources.Location::parse(invalid) is None)
  }
  for invalid in ["", "../a", "/a", "a/", "a//b", "a/./b", "a\\b", "C:/a"] {
    assert_true(@resources.EntryPath::parse(invalid) is None)
    assert_true(@resources.ResourceName::parse(invalid) is None)
  }
  assert_eq(entry("nested/a").join(entry("b")).to_string(), "nested/a/b")
  assert_eq(entry("nested/a").relative_to(entry("nested")), Some(entry("a")))
  assert_eq(entry("nested-other/a").relative_to(entry("nested")), None)
  assert_eq(entry("nested").relative_to(entry("nested")), None)
  let digest = @resources.ContentDigest::sha256(b"hello")
  assert_eq(
    digest.to_string(),
    "sha256:2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
  )
  assert_eq(@resources.ContentDigest::parse(digest.to_string()), Some(digest))
  for
    invalid in ["sha256:", "md5:" + "0".repeat(64), "sha256:" + "g".repeat(64)] {
    assert_true(@resources.ContentDigest::parse(invalid) is None)
  }
}

///|
test "provenance composition uses structural ancestry rather than rendered prefixes" {
  let provider = @resources.ProviderId::parse("local").unwrap()
  let registration = @resources.Provenance::provider_registration(provider)
  assert_eq(registration.origin, @resources.ProviderRegistration(provider))
  assert_eq(registration.location(), None)
  assert_eq(location("/").directory_entry(entry("file")).to_string(), "/file")
  assert_eq(
    location("C:\\")
    .directory_entry(entry("file"), style=@resources.Backslash)
    .to_string(),
    "C:\\file",
  )
  let container = location("outer.jar")
  let nested = container.archive_entry(entry("lib/inner.jar"))
  let physical = nested.archive_entry(entry("a.txt"))
  let parent = @resources.Provenance::new(container).resolved(
    {
      repository: @resources.RepositoryId::parse("repo").unwrap(),
      key: @resources.ArtifactKey::parse("key").unwrap(),
    },
    Some(@resources.ArtifactIdentity::parse("identity").unwrap()),
  )
  let child = @resources.Provenance::new(physical).through(parent)
  assert_eq(child.location(), Some(physical))
  assert_eq(child.steps(), parent.steps())
  assert_eq(
    child.to_string(),
    "repo[key] -> identity -> outer.jar!/lib/inner.jar!/a.txt",
  )
  child.steps().clear()
  assert_eq(child.steps().length(), 1)
  // Identical rendered text can represent an unrelated provider's source.
  let unrelated = @resources.Provenance::new(
    location("outer.jar!/lib/inner.jar!/a.txt"),
  ).through(parent)
  assert_eq(unrelated.steps().length(), 2)
  assert_eq(unrelated.steps()[1], @resources.ContainerStep(container))
  assert_eq(
    unrelated.location(),
    Some(location("outer.jar!/lib/inner.jar!/a.txt")),
  )
  assert_eq(
    @resources.Provenance::new(location("outer.jar-other/a"))
    .through(parent)
    .steps()
    .length(),
    2,
  )
}

///|
test "composition retains configuration origins before physical acquisition" {
  let provider = @resources.ProviderId::parse("local").unwrap()
  let repository = @resources.RepositoryId::parse("models").unwrap()
  let physical = @resources.Provenance::new(location("tree/file"))
  let registration = @resources.Provenance::provider_registration(provider)
  let configured = physical.through(registration)
  assert_eq(configured.to_string(), "local -> tree/file")
  assert_eq(configured.steps(), [@resources.ProviderRegistrationStep(provider)])
  let reference = @resources.Provenance::repository_reference(repository)
  assert_eq(
    configured.through(reference).to_string(),
    "models -> local -> tree/file",
  )
  assert_eq(
    configured.through(reference).steps()[0],
    @resources.RepositoryReferenceStep(repository),
  )
}
