///|
pub struct NpmPackageName {
  priv value : String
} derive(Eq, Debug)

///|
pub fn NpmPackageName::parse(text : String) -> NpmPackageName? {
  if text.is_empty() ||
    text.length() > 214 ||
    text == "node_modules" ||
    text == "favicon.ico" {
    return None
  }
  let parts = if text.has_prefix("@") {
    text[1:].split("/").to_array()
  } else {
    [text[:]]
  }
  if (text.has_prefix("@") && parts.length() != 2) ||
    parts.any(part => {
      part.is_empty() ||
      part.has_prefix(".") ||
      part.has_prefix("_") ||
      part.has_prefix("-") ||
      part
      .iter()
      .any(c => {
        !"abcdefghijklmnopqrstuvwxyz0123456789-_.".contains(c.to_string())
      })
    }) {
    return None
  }
  Some({ value: text, })
}

///|
pub fn NpmPackageName::to_string(self : NpmPackageName) -> String {
  self.value
}

///|
pub struct NpmVersion {
  priv value : String
} derive(Eq, Debug)

///|
pub fn NpmVersion::parse(text : String) -> NpmVersion? {
  if text.is_empty() || text.length() > 256 {
    return None
  }
  fn number(part : StringView) -> Bool {
    !part.is_empty() &&
    (part.length() == 1 || !part.has_prefix("0")) &&
    part.iter().all(c => "0123456789".contains(c.to_string()))
  }
  fn identifiers(text : StringView, prerelease : Bool) -> Bool {
    text
    .split(".")
    .all(part => {
      !part.is_empty() &&
      part
      .iter()
      .all(c => {
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-".contains(
          c.to_string(),
        )
      }) &&
      (
        !prerelease ||
        !part.iter().all(c => "0123456789".contains(c.to_string())) ||
        number(part)
      )
    })
  }
  let build = text.split("+").to_array()
  if build.length() > 2 ||
    (build.length() == 2 && !identifiers(build[1], false)) {
    return None
  }
  let main = build[0]
  let core = if main.find("-") is Some(i) {
    if !identifiers(main[i + 1:], true) {
      return None
    }
    main[:i]
  } else {
    main
  }
  let components = core.split(".").to_array()
  if components.length() != 3 || !components.all(number) {
    return None
  }
  Some({ value: text, })
}

///|
pub fn NpmVersion::to_string(self : NpmVersion) -> String {
  self.value
}

///|
pub(all) struct NpmPackageRef {
  name : NpmPackageName
  version : NpmVersion
} derive(Eq, Debug)

///|
pub fn NpmPackageRef::to_string(self : NpmPackageRef) -> String {
  self.name.value + "@" + self.version.value
}

///|
pub fn NpmPackageRef::key(self : NpmPackageRef) -> ArtifactKey {
  ArtifactKey::parse(
    Json::array([
      Json::string(self.name.value),
      Json::string(self.version.value),
    ]).stringify(),
  ).unwrap()
}

///|
pub fn NpmPackageRef::from_key(key : ArtifactKey) -> NpmPackageRef? {
  let json = @json.parse(key.to_string()) catch { _ => return None }
  guard json is [String(name), String(version)] &&
    NpmPackageName::parse(name) is Some(name) &&
    NpmVersion::parse(version) is Some(version) else {
    return None
  }
  Some({ name, version, })
}

///|
pub(all) struct NpmResolution {
  registry : RepositoryUrl
  reference : NpmPackageRef
  tarball : HttpUrl
  integrity : NpmIntegrity
} derive(Eq, Debug)

///|
pub fn NpmResolution::to_string(self : NpmResolution) -> String {
  "npm:" +
  self.reference.to_string() +
  " registry=" +
  self.registry.to_string() +
  " " +
  self.integrity.to_string()
}

///|
pub(all) struct NpmArchive {
  registry : RepositoryUrl
  reference : NpmPackageRef
  expected_digest : ContentDigest?
} derive(Eq, Debug)

///|
pub fn Provenance::npm_requested(
  self : Provenance,
  registry : RepositoryUrl,
  reference : NpmPackageRef,
) -> Provenance {
  let history = [NpmRequestStep(registry, reference)]
  history.append(self.history)
  { ..self, history, }
}

///|
pub fn Provenance::npm(
  self : Provenance,
  resolution : NpmResolution,
) -> Provenance {
  let history = [NpmStep(resolution)]
  history.append(self.history)
  { ..self, history, }
}

///|
pub fn NpmArchive::open(
  self : NpmArchive,
  transport : HttpTransport,
  acquisition_limits~ : AcquisitionLimits = AcquisitionLimits::new().unwrap(),
  limits~ : Limits = Limits::new(),
  cache~ : VerifiedCache? = None,
  mode~ : AcquisitionMode = Online,
) -> EntryTree raise ResourceError {
  self.open_resolved(transport, acquisition_limits~, limits~, cache~, mode~).1
}

///|
fn NpmArchive::open_resolved(
  self : NpmArchive,
  transport : HttpTransport,
  acquisition_limits~ : AcquisitionLimits,
  limits~ : Limits,
  cache~ : VerifiedCache?,
  mode~ : AcquisitionMode,
) -> (NpmResolution, EntryTree) raise ResourceError {
  let origin = Provenance::new(self.registry.location()).npm_requested(
    self.registry,
    self.reference,
  )
  check_limits(limits, self.registry.location())
  if limits.max_archive_bytes == 0 {
    raise ResourceError(ResourceLimit, origin, "Archive byte limit is zero")
  }
  try {
    let endpoint = self.registry.endpoint(
      encode_repository_segment(self.reference.name.value) +
      "/" +
      encode_repository_segment(self.reference.version.value),
    )
    let data = acquire(
      endpoint,
      transport,
      limits={
        ..acquisition_limits,
        max_bytes: Int32::min(1048576, acquisition_limits.max_bytes),
      },
      cache~,
      mode~,
    ) catch {
      ResourceError(MissingAsset, at, _) =>
        raise ResourceError(
          MissingPackageVersion,
          at,
          "No npm package version `" + self.reference.to_string() + "`",
        )
      error => raise error
    }
    let document = provider_json(data)
    guard document
      is {
        "name": String(name),
        "version": String(version),
        "dist": Object(dist),
        ..
      } &&
      name == self.reference.name.value &&
      version == self.reference.version.value &&
      dist.get("tarball") is Some(String(tarball)) &&
      HttpUrl::parse(tarball) is Some(tarball) else {
      raise ResourceError(
        InvalidResolution,
        origin,
        "npm metadata must match the exact package/version and contain a credential-free tarball URL",
      )
    }
    let integrity = match dist.get("integrity") {
      Some(String(text)) => NpmIntegrity::parse_sri(text)
      None =>
        match dist.get("shasum") {
          Some(String(text)) => NpmIntegrity::parse_shasum(text)
          _ => None
        }
      _ => None
    }
    guard integrity is Some(integrity) else {
      raise ResourceError(
        UnsupportedIntegrity,
        origin,
        "Expected supported npm SRI integrity or a legacy SHA-1 shasum",
      )
    }
    let resolution : NpmResolution = {
      registry: self.registry,
      reference: self.reference,
      tarball,
      integrity,
    }
    let provenance = origin.npm(resolution)
    let tree = PublicArchive::{
      url: tarball,
      format: Tgz,
      expected_digest: self.expected_digest,
    }.open(transport, acquisition_limits~, limits~, cache~, mode~, verify=(
      body,
      at,
    ) => integrity.verify(body, at)) catch {
      ResourceError(code, at, message) =>
        raise ResourceError(code, at.through(provenance), message)
    }
    (resolution, { ..tree, provenance: tree.provenance.npm(resolution), })
  } catch {
    ResourceError(code, at, message) =>
      raise ResourceError(code, at.through(origin), message)
  }
}

///|
pub fn register_npm(
  registry : Registry,
  transport : HttpTransport,
  expected_digest~ : ContentDigest? = None,
  acquisition_limits~ : AcquisitionLimits = AcquisitionLimits::new().unwrap(),
  limits~ : Limits = Limits::new(),
  cache~ : VerifiedCache? = None,
  mode~ : AcquisitionMode = Online,
) -> Registry raise ResourceError {
  registry.register_provider(ProviderId::parse("npm").unwrap(), (
    repository,
    reference,
  ) => {
    guard RepositoryUrl::parse(repository.location.to_string()) is Some(base) &&
      NpmPackageRef::from_key(reference.key) is Some(requested) else {
      raise ResourceError(
        InvalidResolution,
        Provenance::new(Location::Source(repository.location)),
        "npm requires a repository URL and an exact package/version key",
      )
    }
    let (resolution, tree) = NpmArchive::{
      registry: base,
      reference: requested,
      expected_digest,
    }.open_resolved(transport, acquisition_limits~, limits~, cache~, mode~)
    {
      reference,
      identity: ArtifactIdentity::parse(resolution.to_string()).unwrap(),
      tree,
    }
  })
}
