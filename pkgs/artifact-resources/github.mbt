///|
/// A public GitHub repository coordinate, independent of its API host.
pub struct GitHubRepository {
  priv value : String
} derive(Eq, Debug)

///|
pub fn GitHubRepository::parse(text : String) -> GitHubRepository? {
  let parts = text.split("/").to_array()
  if parts.length() != 2 ||
    parts.any(part => {
      part.is_empty() ||
      part == "." ||
      part == ".." ||
      part.length() > 100 ||
      part
      .iter()
      .any(c => {
        !"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.".contains(
          c.to_string(),
        )
      })
    }) {
    return None
  }
  Some({ value: text, })
}

///|
pub fn GitHubRepository::to_string(self : GitHubRepository) -> String {
  self.value
}

///|
pub struct GitHubTag {
  priv value : String
} derive(Eq, Debug)

///|
pub fn GitHubTag::parse(text : String) -> GitHubTag? {
  if valid_value(text) && text.length() <= 255 && text != "." && text != ".." {
    Some({ value: text, })
  } else {
    None
  }
}

///|
pub fn GitHubTag::to_string(self : GitHubTag) -> String {
  self.value
}

///|
pub struct GitHubAssetName {
  priv value : String
} derive(Eq, Debug)

///|
pub fn GitHubAssetName::parse(text : String) -> GitHubAssetName? {
  if valid_value(text) &&
    text.length() <= 255 &&
    !text.contains("/") &&
    !text.contains("\\") &&
    text != "." &&
    text != ".." {
    Some({ value: text, })
  } else {
    None
  }
}

///|
pub fn GitHubAssetName::to_string(self : GitHubAssetName) -> String {
  self.value
}

///|
pub struct GitHubReleaseId {
  priv value : Int64
} derive(Eq, Debug)

///|
pub struct GitHubAssetId {
  priv value : Int64
} derive(Eq, Debug)

///|
pub fn GitHubReleaseId::to_string(self : GitHubReleaseId) -> String {
  self.value.to_string()
}

///|
pub fn GitHubAssetId::to_string(self : GitHubAssetId) -> String {
  self.value.to_string()
}

///|
/// An exact name within an explicitly named release. Keys serialize both fields
/// as JSON, so tags and names containing punctuation cannot collide.
pub(all) struct GitHubAssetRef {
  tag : GitHubTag
  asset : GitHubAssetName
} derive(Eq, Debug)

///|
pub fn GitHubAssetRef::key(self : GitHubAssetRef) -> ArtifactKey {
  ArtifactKey::parse(
    Json::array([Json::string(self.tag.value), Json::string(self.asset.value)]).stringify(),
  ).unwrap()
}

///|
pub fn GitHubAssetRef::from_key(key : ArtifactKey) -> GitHubAssetRef? {
  let json = @json.parse(key.to_string()) catch { _ => return None }
  guard json is [String(tag), String(asset)] &&
    GitHubTag::parse(tag) is Some(tag) &&
    GitHubAssetName::parse(asset) is Some(asset) else {
    return None
  }
  Some({ tag, asset, })
}

///|
pub(all) struct GitHubResolution {
  repository : GitHubRepository
  requested : GitHubAssetRef
  release_id : GitHubReleaseId
  asset_id : GitHubAssetId
  download : HttpUrl
} derive(Eq, Debug)

///|
pub fn GitHubResolution::to_string(self : GitHubResolution) -> String {
  "github:" +
  self.repository.value +
  " tag=" +
  self.requested.tag.value +
  " release=" +
  self.release_id.to_string() +
  " asset=" +
  self.requested.asset.value +
  " id=" +
  self.asset_id.to_string()
}

///|
pub fn Provenance::github(
  self : Provenance,
  resolution : GitHubResolution,
) -> Provenance {
  let history = [GitHubStep(resolution)]
  history.append(self.history)
  { ..self, history, }
}

///|
pub(all) struct GitHubArchive {
  repository : GitHubRepository
  reference : GitHubAssetRef
  format : ArchiveFormat
  expected_digest : ContentDigest?
} derive(Eq, Debug)

///|
fn github_segment(text : String) -> String {
  let out = StringBuilder()
  let hex = "0123456789ABCDEF"
  for byte in @utf8.encode(text) {
    let n = byte.to_int()
    if (n >= 65 && n <= 90) ||
      (n >= 97 && n <= 122) ||
      (n >= 48 && n <= 57) ||
      "-._~".contains(n.unsafe_to_char().to_string()) {
      out.write_char(n.unsafe_to_char())
    } else {
      out.write_string(
        "%" +
        hex[n / 16:n / 16 + 1].to_owned() +
        hex[n % 16:n % 16 + 1].to_owned(),
      )
    }
  }
  out.to_string()
}

///|
fn github_id(json : Json) -> Int64? {
  guard json is Number(n, ..) else { return None }
  if n >= 1 && n <= 9007199254740991.0 && n.to_int64().to_double() == n {
    Some(n.to_int64())
  } else {
    None
  }
}

///|
fn github_json(bytes : Bytes, origin : Provenance) -> Json raise ResourceError {
  @json.parse(@utf8.decode(bytes)) catch {
    _ =>
      raise ResourceError(InvalidResolution, origin, "Invalid GitHub API JSON")
  }
}

///|
/// Resolve a public release by tag, enumerate assets in bounded pages and match
/// one exact name. Metadata and archive bytes share the verified HTTP cache.
pub fn GitHubArchive::open(
  self : GitHubArchive,
  transport : HttpTransport,
  api~ : HttpUrl = HttpUrl::parse("https://api.github.com").unwrap(),
  acquisition_limits~ : AcquisitionLimits = AcquisitionLimits::new().unwrap(),
  limits~ : Limits = Limits::new(),
  cache~ : VerifiedCache? = None,
  mode~ : AcquisitionMode = Online,
) -> EntryTree raise ResourceError {
  self.open_resolved(
    transport,
    api~,
    acquisition_limits~,
    limits~,
    cache~,
    mode~,
  ).1
}

///|
fn GitHubArchive::open_resolved(
  self : GitHubArchive,
  transport : HttpTransport,
  api~ : HttpUrl = HttpUrl::parse("https://api.github.com").unwrap(),
  acquisition_limits~ : AcquisitionLimits = AcquisitionLimits::new().unwrap(),
  limits~ : Limits = Limits::new(),
  cache~ : VerifiedCache? = None,
  mode~ : AcquisitionMode = Online,
) -> (GitHubResolution, EntryTree) raise ResourceError {
  let origin = Provenance::new(api.location()).github_requested(
    self.repository,
    self.reference,
  )
  check_limits(limits, api.location())
  if limits.max_archive_bytes == 0 {
    raise ResourceError(ResourceLimit, origin, "Archive byte limit is zero")
  }
  let base = api.to_string().trim_end(chars="/").to_owned()
  if base.contains("?") {
    raise ResourceError(
      InvalidResolution,
      origin,
      "GitHub API base must not contain a query",
    )
  }
  let prefix = base + "/repos/" + self.repository.value + "/releases/"
  let metadata_limits = {
    ..acquisition_limits,
    max_bytes: Int32::min(acquisition_limits.max_bytes, 1048576),
  }
  fn metadata(path : String) -> Json raise ResourceError {
    let checked_transport : HttpTransport = (url, bounds) => {
      let response = transport(url, bounds)
      if response.body.length() > bounds.max_bytes {
        raise ResourceError(
          ResourceLimit,
          Provenance::new(url.location()),
          "GitHub metadata exceeds byte limit",
        )
      }
      if response.status == 403 {
        let text = @utf8.decode(response.body) catch { _ => "" }
        if text.contains("rate limit") {
          raise ResourceError(
            RateLimited,
            Provenance::new(response.resolved.location()),
            "GitHub API rate limit exceeded",
          )
        }
      }
      response
    }
    guard HttpUrl::parse(prefix + path) is Some(requested) else {
      raise ResourceError(
        InvalidResolution,
        origin,
        "GitHub API URL exceeds supported URL bounds",
      )
    }
    let acquired = acquire(
      requested,
      checked_transport,
      limits=metadata_limits,
      cache~,
      mode~,
    ) catch {
      ResourceError(code, at, message) =>
        raise ResourceError(code, at.through(origin), message)
    }
    github_json(
      acquired.body,
      Provenance::new(acquired.metadata.resolved.location())
      .acquired(acquired.metadata)
      .through(origin),
    )
  }
  let release = metadata("tags/" + github_segment(self.reference.tag.value)) catch {
    ResourceError(MissingAsset, at, message) =>
      raise ResourceError(MissingRelease, at, message)
    error => raise error
  }
  guard release is { "id": id, "tag_name": String(tag), "draft": False, .. } &&
    github_id(id) is Some(id) &&
    tag == self.reference.tag.value else {
    raise ResourceError(
      InvalidResolution,
      origin,
      "GitHub release must have a positive ID, matching tag and draft=false",
    )
  }
  let release_id : GitHubReleaseId = { value: id, }
  let matches : Array[Json] = []
  for page = 1; ; page = page + 1 {
    if page > 10 {
      raise ResourceError(
        ResourceLimit,
        origin,
        "GitHub asset enumeration exceeds ten pages",
      )
    }
    guard metadata(
        release_id.to_string() + "/assets?per_page=100&page=" + page.to_string(),
      )
      is Array(assets) &&
      assets.length() <= 100 else {
      raise ResourceError(
        InvalidResolution,
        origin,
        "Expected a GitHub asset page of at most 100 entries",
      )
    }
    for asset in assets {
      guard asset is { "name": String(name), .. } else {
        raise ResourceError(
          InvalidResolution,
          origin,
          "Expected a GitHub asset name",
        )
      }
      if name == self.reference.asset.value {
        matches.push(asset)
      }
    }
    if assets.length() < 100 {
      break
    }
  }
  if matches.is_empty() {
    raise ResourceError(
      MissingAsset,
      origin,
      "No GitHub asset named `" +
      self.reference.asset.value +
      "` in tag `" +
      self.reference.tag.value +
      "`",
    )
  }
  if matches.length() != 1 {
    raise ResourceError(
      AmbiguousAsset,
      origin,
      "Multiple GitHub assets have the exact requested name",
    )
  }
  let asset = matches[0]
  guard asset
    is {
      "id": asset_id,
      "browser_download_url": String(download),
      "state": "uploaded",
      ..
    } &&
    github_id(asset_id) is Some(asset_id) &&
    HttpUrl::parse(download) is Some(download) else {
    raise ResourceError(
      InvalidResolution,
      origin,
      "GitHub asset requires a positive ID, uploaded state and credential-free download URL",
    )
  }
  let resolution : GitHubResolution = {
    repository: self.repository,
    requested: self.reference,
    release_id,
    asset_id: { value: asset_id, },
    download,
  }
  let provenance = origin.github(resolution)
  let api_digest = match asset {
    { "digest": Null, .. } => None
    { "digest": String(text), .. } => {
      guard ContentDigest::parse(text) is Some(digest) else {
        raise ResourceError(
          InvalidResolution,
          provenance,
          "Invalid GitHub asset SHA-256 digest",
        )
      }
      Some(digest)
    }
    Object(fields) => {
      if fields.contains("digest") {
        raise ResourceError(
          InvalidResolution,
          provenance,
          "Invalid GitHub asset digest",
        )
      }
      None
    }
    _ => None
  }
  if api_digest is Some(digest) &&
    self.expected_digest is Some(expected) &&
    digest != expected {
    raise ResourceError(
      IntegrityFailure,
      provenance,
      "Expected digest differs from GitHub asset digest",
    )
  }
  let tree = PublicArchive::{
    url: download,
    format: self.format,
    expected_digest: if self.expected_digest is Some(_) {
      self.expected_digest
    } else {
      api_digest
    },
  }.open(transport, acquisition_limits~, limits~, cache~, mode~) catch {
    ResourceError(code, at, message) =>
      raise ResourceError(code, at.through(provenance), message)
  }
  (resolution, { ..tree, provenance: tree.provenance.github(resolution), })
}

///|
/// Repository location is owner/repository; artifact keys come from GitHubAssetRef.
pub fn register_github(
  registry : Registry,
  transport : HttpTransport,
  api~ : HttpUrl = HttpUrl::parse("https://api.github.com").unwrap(),
  format~ : ArchiveFormat = Zip,
  expected_digest~ : ContentDigest? = None,
  acquisition_limits~ : AcquisitionLimits = AcquisitionLimits::new().unwrap(),
  limits~ : Limits = Limits::new(),
  cache~ : VerifiedCache? = None,
  mode~ : AcquisitionMode = Online,
) -> Registry raise ResourceError {
  registry.register_provider(ProviderId::parse("github").unwrap(), (
    repository,
    reference,
  ) => {
    guard GitHubRepository::parse(repository.location.to_string())
      is Some(coordinate) &&
      GitHubAssetRef::from_key(reference.key) is Some(requested) else {
      raise ResourceError(
        InvalidResolution,
        Provenance::new(Location::Source(repository.location)),
        "GitHub requires owner/repository and an exact tag/asset key",
      )
    }
    let (resolution, tree) = GitHubArchive::{
      repository: coordinate,
      reference: requested,
      format,
      expected_digest,
    }.open_resolved(
      transport,
      api~,
      acquisition_limits~,
      limits~,
      cache~,
      mode~,
    )
    {
      reference,
      identity: ArtifactIdentity::parse(resolution.to_string()).unwrap(),
      tree,
    }
  })
}
