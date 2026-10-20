///|
/// A configured source. Its provider interprets location and artifact keys.
pub(all) struct Repository {
  id : RepositoryId
  provider : ProviderId
  location : RepositoryLocation
} derive(Debug, Eq)

///|
pub(all) struct ArtifactRef {
  repository : RepositoryId
  key : ArtifactKey
} derive(Debug, Eq)

///|
/// Provider-specific resolved identity and the common entry tree.
/// Archive trees expose a SHA-256 digest; mutable directories have no digest.
pub(all) struct ResolvedArtifact {
  reference : ArtifactRef
  identity : ArtifactIdentity
  tree : EntryTree
}

///|
pub struct Registry {
  priv repositories : Map[RepositoryId, Repository]
  priv providers : Map[
    ProviderId,
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
  name : ProviderId,
  provider : (Repository, ArtifactRef) -> ResolvedArtifact raise ResourceError,
) -> Registry raise ResourceError {
  if self.providers.contains(name) {
    raise ResourceError(
      DuplicateProvider,
      Provenance::provider_registration(name),
      "Provider already registered",
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
      DuplicateRepository,
      Provenance::new(Location::Source(repository.location)),
      "Repository `" + repository.id.to_string() + "` already registered",
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
      UnknownRepository,
      Provenance::repository_reference(reference.repository).resolved(
        reference,
        None,
      ),
      "Unknown repository for `" + reference.key.to_string() + "`",
    )
  }
  guard self.providers.get(repository.provider) is Some(provider) else {
    raise ResourceError(
      UnknownProvider,
      Provenance::new(Location::Source(repository.location)).resolved(
        reference,
        None,
      ),
      "Unknown provider `" + repository.provider.to_string() + "`",
    )
  }
  let artifact = provider(repository, reference) catch {
    ResourceError(code, origin, message) =>
      raise ResourceError(code, origin.resolved(reference, None), message)
  }
  if artifact.reference != reference {
    raise ResourceError(
      InvalidResolution,
      Provenance::new(Location::Source(repository.location)).resolved(
        reference,
        None,
      ),
      "Provider returned a different artifact reference",
    )
  }
  {
    ..artifact,
    tree: {
      ..artifact.tree,
      provenance: artifact.tree.provenance.resolved(
        reference,
        Some(artifact.identity),
      ),
    },
  }
}

///|
pub fn ArtifactRef::to_string(self : ArtifactRef) -> String {
  self.repository.to_string() + "[" + self.key.to_string() + "]"
}
