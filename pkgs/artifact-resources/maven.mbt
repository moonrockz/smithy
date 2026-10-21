///|
fn maven_component(text : String) -> Bool {
  !text.is_empty() &&
  text.length() <= 128 &&
  text != "." &&
  text != ".." &&
  !text.contains("..") &&
  text
  .iter()
  .all(c => {
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-".contains(
      c.to_string(),
    )
  })
}

///|
fn maven_timestamp_snapshot(text : String) -> Bool {
  let parts = text.split("-").to_array()
  if parts.length() < 3 {
    return false
  }
  let timestamp = parts[parts.length() - 2]
  let build = parts[parts.length() - 1]
  if timestamp.length() != 15 ||
    timestamp[8] != 46 ||
    build.is_empty() ||
    !build.iter().all(c => "0123456789".contains(c.to_string())) {
    return false
  }
  for i in 0..<15 {
    if i == 8 {
      continue
    }
    let n = timestamp[i].to_int()
    if n < 48 || n > 57 {
      return false
    }
  }
  true
}

///|
pub struct MavenGroupId {
  priv value : String
} derive(Eq, Debug)

///|
pub fn MavenGroupId::parse(text : String) -> MavenGroupId? {
  if text.length() <= 255 &&
    text.split(".").all(part => maven_component(part.to_owned())) {
    Some({ value: text, })
  } else {
    None
  }
}

///|
pub fn MavenGroupId::to_string(self : MavenGroupId) -> String {
  self.value
}

///|
pub struct MavenArtifactId {
  priv value : String
} derive(Eq, Debug)

///|
pub fn MavenArtifactId::parse(text : String) -> MavenArtifactId? {
  if maven_component(text) {
    Some({ value: text, })
  } else {
    None
  }
}

///|
pub fn MavenArtifactId::to_string(self : MavenArtifactId) -> String {
  self.value
}

///|
pub struct MavenVersion {
  priv value : String
} derive(Eq, Debug)

///|
pub fn MavenVersion::parse(text : String) -> MavenVersion? {
  if maven_component(text) &&
    !text.to_upper().has_suffix("SNAPSHOT") &&
    !maven_timestamp_snapshot(text) &&
    !["LATEST", "RELEASE"].contains(text.to_upper()) {
    Some({ value: text, })
  } else {
    None
  }
}

///|
pub fn MavenVersion::to_string(self : MavenVersion) -> String {
  self.value
}

///|
pub struct MavenClassifier {
  priv value : String
} derive(Eq, Debug)

///|
pub fn MavenClassifier::parse(text : String) -> MavenClassifier? {
  if maven_component(text) {
    Some({ value: text, })
  } else {
    None
  }
}

///|
pub fn MavenClassifier::to_string(self : MavenClassifier) -> String {
  self.value
}

///|
/// Direct JAR coordinates only. No mutable snapshots, ranges or POM traversal.
pub(all) struct MavenCoordinates {
  group : MavenGroupId
  artifact : MavenArtifactId
  version : MavenVersion
  classifier : MavenClassifier?
} derive(Eq, Debug)

///|
pub fn MavenCoordinates::to_string(self : MavenCoordinates) -> String {
  let suffix = match self.classifier {
    Some(classifier) => ":" + classifier.value
    None => ""
  }
  self.group.value +
  ":" +
  self.artifact.value +
  ":" +
  self.version.value +
  suffix
}

///|
/// A repository-relative artifact location, distinct from paths inside its JAR.
pub struct MavenArtifactPath {
  priv value : String
} derive(Eq, Debug)

///|
pub fn MavenArtifactPath::to_string(self : MavenArtifactPath) -> String {
  self.value
}

///|
pub fn MavenCoordinates::path(self : MavenCoordinates) -> MavenArtifactPath {
  let suffix = match self.classifier {
    Some(classifier) => "-" + classifier.value
    None => ""
  }
  {
    value: self.group.value.replace_all(old=".", new="/") +
    "/" +
    self.artifact.value +
    "/" +
    self.version.value +
    "/" +
    self.artifact.value +
    "-" +
    self.version.value +
    suffix +
    ".jar",
  }
}

///|
pub fn MavenCoordinates::key(self : MavenCoordinates) -> ArtifactKey {
  ArtifactKey::parse(
    Json::array([
      Json::string(self.group.value),
      Json::string(self.artifact.value),
      Json::string(self.version.value),
      match self.classifier {
        Some(classifier) => Json::string(classifier.value)
        None => Json::null()
      },
    ]).stringify(),
  ).unwrap()
}

///|
pub fn MavenCoordinates::from_key(key : ArtifactKey) -> MavenCoordinates? {
  let json = @json.parse(key.to_string()) catch { _ => return None }
  guard json is [String(group), String(artifact), String(version), classifier] &&
    MavenGroupId::parse(group) is Some(group) &&
    MavenArtifactId::parse(artifact) is Some(artifact) &&
    MavenVersion::parse(version) is Some(version) else {
    return None
  }
  let classifier = match classifier {
    Null => None
    String(text) => {
      guard MavenClassifier::parse(text) is Some(value) else { return None }
      Some(value)
    }
    _ => return None
  }
  Some({ group, artifact, version, classifier, })
}

///|
pub(all) enum MavenChecksum {
  Sha1Sidecar
  Sha256Sidecar
} derive(Eq, Debug)

///|
pub fn MavenChecksum::algorithm(self : MavenChecksum) -> ChecksumAlgorithm {
  match self {
    Sha1Sidecar => Sha1
    Sha256Sidecar => Sha256
  }
}

///|
pub(all) enum MavenVerification {
  PinnedDigest(ContentDigest)
  RepositoryChecksum(Acquisition, Checksum)
} derive(Eq, Debug)

///|
pub(all) struct MavenResolution {
  repository : RepositoryUrl
  coordinates : MavenCoordinates
  artifact : HttpUrl
  verification : MavenVerification
} derive(Eq, Debug)

///|
pub fn MavenResolution::to_string(self : MavenResolution) -> String {
  let verification = match self.verification {
    PinnedDigest(digest) => digest.to_string()
    RepositoryChecksum(_, checksum) => checksum.to_string()
  }
  "maven:" +
  self.coordinates.to_string() +
  " repository=" +
  self.repository.to_string() +
  " verification=" +
  verification
}

///|
pub(all) struct MavenArchive {
  repository : RepositoryUrl
  coordinates : MavenCoordinates
  checksum : MavenChecksum
  expected_digest : ContentDigest?
} derive(Eq, Debug)

///|
pub fn Provenance::maven_requested(
  self : Provenance,
  repository : RepositoryUrl,
  coordinates : MavenCoordinates,
) -> Provenance {
  let history = [MavenRequestStep(repository, coordinates)]
  history.append(self.history)
  { ..self, history, }
}

///|
pub fn Provenance::maven(
  self : Provenance,
  resolution : MavenResolution,
) -> Provenance {
  let history = [MavenStep(resolution)]
  history.append(self.history)
  { ..self, history, }
}

///|
pub fn MavenArchive::open(
  self : MavenArchive,
  transport : HttpTransport,
  acquisition_limits~ : AcquisitionLimits = AcquisitionLimits::new().unwrap(),
  limits~ : Limits = Limits::new(),
  cache~ : VerifiedCache? = None,
  mode~ : AcquisitionMode = Online,
) -> EntryTree raise ResourceError {
  self.open_resolved(transport, acquisition_limits~, limits~, cache~, mode~).1
}

///|
fn MavenArchive::open_resolved(
  self : MavenArchive,
  transport : HttpTransport,
  acquisition_limits~ : AcquisitionLimits,
  limits~ : Limits,
  cache~ : VerifiedCache?,
  mode~ : AcquisitionMode,
) -> (MavenResolution, EntryTree) raise ResourceError {
  let origin = Provenance::new(self.repository.location()).maven_requested(
    self.repository,
    self.coordinates,
  )
  check_limits(limits, self.repository.location())
  if limits.max_archive_bytes == 0 {
    raise ResourceError(ResourceLimit, origin, "Archive byte limit is zero")
  }
  try {
    let path = self.coordinates.path().to_string()
    let artifact = self.repository.endpoint(path)
    let verification = if self.expected_digest is Some(digest) {
      PinnedDigest(digest)
    } else {
      let data = acquire(
        self.repository.endpoint(
          path + "." + self.checksum.algorithm().to_string(),
        ),
        transport,
        limits={
          ..acquisition_limits,
          max_bytes: Int32::min(4096, acquisition_limits.max_bytes),
        },
        cache~,
        mode~,
      )
      let text = @utf8.decode(data.body) catch {
        _ =>
          raise ResourceError(
            InvalidResolution,
            origin,
            "Expected a hexadecimal Maven checksum sidecar",
          )
      }
      guard Checksum::parse_hex(
          self.checksum.algorithm(),
          text.trim().to_owned(),
        )
        is Some(checksum) else {
        raise ResourceError(
          InvalidResolution,
          origin,
          "Expected a bare hexadecimal Maven " +
          self.checksum.algorithm().to_string() +
          " sidecar",
        )
      }
      RepositoryChecksum(data.metadata, checksum)
    }
    let resolution : MavenResolution = {
      repository: self.repository,
      coordinates: self.coordinates,
      artifact,
      verification,
    }
    let tree = PublicArchive::{
      url: artifact,
      format: Zip,
      expected_digest: self.expected_digest,
    }.open(transport, acquisition_limits~, limits~, cache~, mode~, verify=(
      body,
      at,
    ) => {
      if verification is RepositoryChecksum(_, checksum) &&
        !checksum.matches(body) {
        raise ResourceError(
          IntegrityFailure,
          at,
          "JAR does not match repository " + checksum.to_string(),
        )
      }
    }) catch {
      ResourceError(code, at, message) =>
        raise ResourceError(code, at.through(origin.maven(resolution)), message)
    }
    (resolution, { ..tree, provenance: tree.provenance.maven(resolution), })
  } catch {
    ResourceError(MissingAsset, at, message) =>
      raise ResourceError(MissingArtifact, at.through(origin), message)
    ResourceError(code, at, message) =>
      raise ResourceError(code, at.through(origin), message)
  }
}

///|
pub fn register_maven(
  registry : Registry,
  transport : HttpTransport,
  checksum~ : MavenChecksum = Sha1Sidecar,
  expected_digest~ : ContentDigest? = None,
  acquisition_limits~ : AcquisitionLimits = AcquisitionLimits::new().unwrap(),
  limits~ : Limits = Limits::new(),
  cache~ : VerifiedCache? = None,
  mode~ : AcquisitionMode = Online,
) -> Registry raise ResourceError {
  registry.register_provider(ProviderId::parse("maven").unwrap(), (
    repository,
    reference,
  ) => {
    guard RepositoryUrl::parse(repository.location.to_string()) is Some(base) &&
      MavenCoordinates::from_key(reference.key) is Some(coordinates) else {
      raise ResourceError(
        InvalidResolution,
        Provenance::new(Location::Source(repository.location)),
        "Maven requires a repository URL and exact JAR coordinates",
      )
    }
    let (resolution, tree) = MavenArchive::{
      repository: base,
      coordinates,
      checksum,
      expected_digest,
    }.open_resolved(transport, acquisition_limits~, limits~, cache~, mode~)
    {
      reference,
      identity: ArtifactIdentity::parse(resolution.to_string()).unwrap(),
      tree,
    }
  })
}
