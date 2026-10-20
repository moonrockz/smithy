///|
/// A configured source. Its provider interprets location and artifact keys.
pub(all) struct Repository {
  id : String
  provider : String
  location : String
} derive(Debug, Eq)

///|
pub(all) struct ArtifactRef {
  repository : String
  key : String
} derive(Debug, Eq)

///|
/// Provider-specific resolved identity and the common entry tree.
/// Archive trees expose a SHA-256 digest; mutable directories have no digest.
pub(all) struct ResolvedArtifact {
  reference : ArtifactRef
  identity : String
  tree : EntryTree
}

///|
pub struct Registry {
  priv repositories : Map[String, Repository]
  priv providers : Map[
    String,
    (Repository, ArtifactRef) -> ResolvedArtifact raise ResourceError,
  ]
}

///|
pub fn Registry::new() -> Registry {
  { repositories: Map([]), providers: Map([]), }
}

///|
pub fn Registry::register_provider(
  self : Registry,
  name : String,
  provider : (Repository, ArtifactRef) -> ResolvedArtifact raise ResourceError,
) -> Registry raise ResourceError {
  if self.providers.contains(name) {
    raise ResourceError(
      "duplicate-provider", name, "Provider already registered",
    )
  }
  self.providers[name] = provider
  self
}

///|
pub fn Registry::add_repository(
  self : Registry,
  repository : Repository,
) -> Registry raise ResourceError {
  if self.repositories.contains(repository.id) {
    raise ResourceError(
      "duplicate-repository",
      repository.id,
      "Repository already registered",
    )
  }
  self.repositories[repository.id] = repository
  self
}

///|
pub fn Registry::resolve(
  self : Registry,
  reference : ArtifactRef,
) -> ResolvedArtifact raise ResourceError {
  guard self.repositories.get(reference.repository) is Some(repository) else {
    raise ResourceError(
      "unknown-repository",
      reference.repository,
      "Unknown repository for `" + reference.key + "`",
    )
  }
  guard self.providers.get(repository.provider) is Some(provider) else {
    raise ResourceError(
      "unknown-provider",
      repository.id,
      "Unknown provider `" + repository.provider + "`",
    )
  }
  let artifact = provider(repository, reference) catch {
    ResourceError(code, origin, message) =>
      raise ResourceError(
        code,
        repository.id + "[" + reference.key + "] -> " + origin,
        message,
      )
  }
  if artifact.reference != reference {
    raise ResourceError(
      "invalid-resolution",
      repository.id,
      "Provider returned a different artifact reference",
    )
  }
  {
    ..artifact,
    tree: {
      ..artifact.tree,
      provenance: repository.id +
      "[" +
      reference.key +
      "] -> " +
      artifact.identity +
      " -> " +
      artifact.tree.provenance,
    },
  }
}
