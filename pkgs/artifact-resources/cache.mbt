///|
pub(all) enum AcquisitionMode {
  Online
  Offline
} derive(Eq, Debug)

///|
/// Versioned keys scoped by provider. Providers may add pinned-reference mappings
/// without using repository text or content digests as physical paths.
pub struct CacheKey {
  priv value : String
} derive(Eq, Hash, Debug)

///|
pub fn CacheKey::reference(
  provider : ProviderId,
  reference : ArtifactKey,
) -> CacheKey {
  let encoded = Json::array([
    Json::string(provider.to_string()),
    Json::string(reference.to_string()),
  ]).stringify()
  {
    value: "ref-v1-" +
    ContentDigest::sha256(@utf8.encode(encoded)).to_string()[7:].to_owned(),
  }
}

///|
pub fn CacheKey::content(digest : ContentDigest) -> CacheKey {
  { value: "sha256-" + digest.to_string()[7:].to_owned(), }
}

///|
pub fn CacheKey::to_string(self : CacheKey) -> String {
  self.value
}

///|
/// Host storage must publish complete values atomically. Missing values return
/// None; read/write failures raise CacheIo. Reads must enforce the supplied bound.
pub(all) struct CacheStore {
  read : (CacheKey, Int32) -> Bytes? raise ResourceError
  publish : (CacheKey, Bytes) -> Unit raise ResourceError
}

///|
pub struct VerifiedCache {
  priv store : CacheStore
}

///|
pub fn VerifiedCache::new(store : CacheStore) -> VerifiedCache {
  { store, }
}

///|
pub(all) struct AcquiredBytes {
  metadata : Acquisition
  body : Bytes
}

///|
fn http_cache_key(url : HttpUrl) -> CacheKey {
  CacheKey::reference(
    ProviderId::parse("public-http").unwrap(),
    ArtifactKey::parse(url.to_string()).unwrap(),
  )
}

///|
fn cache_metadata(
  bytes : Bytes,
  requested : HttpUrl,
) -> Acquisition raise ResourceError {
  fn decode() -> Acquisition? raise {
    let text = @utf8.decode(bytes)
    let json = @json.parse(text)
    guard json
      is {
        "version": 1,
        "requested": String(a),
        "resolved": String(b),
        "digest": String(c),
        ..
      } else {
      return None
    }
    guard HttpUrl::parse(a) is Some(a) &&
      a == requested &&
      HttpUrl::parse(b) is Some(b) &&
      ContentDigest::parse(c) is Some(c) else {
      return None
    }
    Some(Acquisition::{ requested: a, resolved: b, digest: c, })
  }
  let parsed = decode() catch { _ => None }
  guard parsed is Some(metadata) else {
    raise ResourceError(
      CacheCorrupt,
      Provenance::new(requested.location()),
      "Invalid cached acquisition metadata",
    )
  }
  metadata
}

///|
/// Shared byte acquisition policy, usable independently of archive decoding.
/// Online hits are reused without revalidation over HTTP. Corruption always fails
/// closed; callers must remove the damaged cache entry before fetching again.
pub fn acquire(
  requested : HttpUrl,
  transport : HttpTransport,
  expected_digest~ : ContentDigest? = None,
  limits~ : AcquisitionLimits = AcquisitionLimits::new().unwrap(),
  cache~ : VerifiedCache? = None,
  mode~ : AcquisitionMode = Online,
) -> AcquiredBytes raise ResourceError {
  let origin = Provenance::new(requested.location())
  if cache is Some(cache) &&
    (cache.store.read)(http_cache_key(requested), 32768) is Some(bytes) {
    let metadata = cache_metadata(bytes, requested)
    let at = Provenance::new(metadata.resolved.location()).acquired(metadata)
    guard (cache.store.read)(
        CacheKey::content(metadata.digest),
        limits.max_bytes,
      )
      is Some(body) else {
      raise ResourceError(
        CacheCorrupt,
        at,
        "Cached acquisition content is missing",
      )
    }
    if body.length() > limits.max_bytes {
      raise ResourceError(
        ResourceLimit,
        at,
        "Cached content exceeds archive byte limit",
      )
    }
    if ContentDigest::sha256(body) != metadata.digest {
      raise ResourceError(
        CacheCorrupt,
        at,
        "Cached content does not match its SHA-256 digest",
      )
    }
    if expected_digest is Some(expected) && expected != metadata.digest {
      raise ResourceError(
        IntegrityFailure,
        at,
        "Expected \{expected}, received \{metadata.digest}",
      )
    }
    return { metadata, body, }
  }
  if mode == Offline {
    raise ResourceError(
      OfflineMiss,
      origin,
      "No verified cached acquisition for requested URL",
    )
  }
  let response = transport(requested, limits)
  if response.body.length() > limits.max_bytes {
    raise ResourceError(
      ResourceLimit,
      origin,
      "Download exceeds archive byte limit",
    )
  }
  let metadata : Acquisition = {
    requested,
    resolved: response.resolved,
    digest: ContentDigest::sha256(response.body),
  }
  let at = Provenance::new(response.resolved.location()).acquired(metadata)
  if response.status != 200 {
    let code = match response.status {
      401 | 403 => AuthenticationRequired
      404 | 410 => MissingAsset
      _ => HttpStatus
    }
    raise ResourceError(code, at, "HTTP status \{response.status}")
  }
  if expected_digest is Some(expected) && expected != metadata.digest {
    raise ResourceError(
      IntegrityFailure,
      at,
      "Expected \{expected}, received \{metadata.digest}",
    )
  }
  if cache is Some(cache) {
    (cache.store.publish)(CacheKey::content(metadata.digest), response.body)
    let json : Json = {
      "version": 1,
      "requested": requested.to_string(),
      "resolved": metadata.resolved.to_string(),
      "digest": metadata.digest.to_string(),
    }
    (cache.store.publish)(
      http_cache_key(requested),
      @utf8.encode(json.stringify()),
    )
  }
  { metadata, body: response.body, }
}
