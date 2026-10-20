///|
/// An absolute, ASCII HTTP(S) URL without credentials or fragments.
/// Non-ASCII path/query characters must be percent-encoded by the caller.
pub struct HttpUrl {
  priv value : String
} derive(Eq, Debug)

///|
pub fn HttpUrl::parse(text : String) -> HttpUrl? {
  let start = if text.has_prefix("https://") {
    8
  } else if text.has_prefix("http://") {
    7
  } else {
    return None
  }
  if text.length() > 8192 ||
    text
    .iter()
    .any(c => {
      c.to_int() <= 32 || c.to_int() >= 127 || "\\\"<>#".contains(c.to_string())
    }) {
    return None
  }
  let rest = text[start:]
  let authority = rest.split("/").next().unwrap().split("?").next().unwrap()
  if authority.is_empty() || authority.contains("@") || authority.contains("%") {
    return None
  }
  let (host, port) = if authority.has_prefix("[") {
    guard authority.find("]") is Some(end) else { return None }
    let host = authority[1:end]
    if !host.contains(":") ||
      host.iter().any(c => !"0123456789abcdefABCDEF:.".contains(c.to_string())) {
      return None
    }
    let suffix = authority[end + 1:]
    if suffix != "" && !suffix.has_prefix(":") {
      return None
    }
    (host, if suffix == "" { None } else { Some(suffix[1:]) })
  } else {
    let parts = authority.split(":").to_array()
    if parts.length() > 2 {
      return None
    }
    let host = parts[0]
    if host
      .iter()
      .any(c => {
        !"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_".contains(
          c.to_string(),
        )
      }) {
      return None
    }
    (host, if parts.length() == 2 { Some(parts[1]) } else { None })
  }
  if host.is_empty() {
    return None
  }
  if port is Some(port) {
    if port.is_empty() || port.length() > 5 {
      return None
    }
    let mut number = 0
    for c in port.iter() {
      let digit = c.to_int() - 48
      if digit < 0 || digit > 9 {
        return None
      }
      number = number * 10 + digit
    }
    if number == 0 || number > 65535 {
      return None
    }
  }
  for i in 0..<text.length() {
    if text.code_unit_at(i) == 37 &&
      (
        i + 2 >= text.length() ||
        !"0123456789abcdefABCDEF".contains(text[i + 1:i + 2].to_owned()) ||
        !"0123456789abcdefABCDEF".contains(text[i + 2:i + 3].to_owned())
      ) {
      return None
    }
  }
  Some({ value: text, })
}

///|
pub fn HttpUrl::to_string(self : HttpUrl) -> String {
  self.value
}

///|
pub fn HttpUrl::location(self : HttpUrl) -> Location {
  Location::parse(self.value).unwrap()
}

///|
pub(all) enum ArchiveFormat {
  Zip
  Tar
  Tgz
} derive(Eq, Debug)

///|
/// Transport implementations must enforce these bounds while receiving bytes.
pub struct AcquisitionLimits {
  max_bytes : Int32
  timeout_seconds : Int32
} derive(Eq, Debug)

///|
pub fn AcquisitionLimits::new(
  max_bytes~ : Int32 = 67108864,
  timeout_seconds~ : Int32 = 30,
) -> AcquisitionLimits? {
  if max_bytes <= 0 ||
    max_bytes > 1073741824 ||
    timeout_seconds <= 0 ||
    timeout_seconds > 3600 {
    None
  } else {
    Some({ max_bytes, timeout_seconds, })
  }
}

///|
pub(all) struct HttpResponse {
  resolved : HttpUrl
  status : Int32
  body : Bytes
}

///|
/// A synchronous host boundary, independent of archive and resource discovery.
/// Follow at most five redirects, prohibit credentials and non-HTTP schemes,
/// preserve TLS certificate verification, and enforce the total time/byte bounds.
pub type HttpTransport = (HttpUrl, AcquisitionLimits) -> HttpResponse raise ResourceError

///|
pub(all) struct PublicArchive {
  url : HttpUrl
  format : ArchiveFormat
  expected_digest : ContentDigest?
} derive(Eq, Debug)

///|
pub(all) struct Acquisition {
  requested : HttpUrl
  resolved : HttpUrl
  digest : ContentDigest
} derive(Eq, Debug)

///|
/// Acquire and verify before parsing any archive bytes. The transport owns I/O;
/// this layer owns status policy, integrity, archive interpretation and provenance.
pub fn PublicArchive::open(
  self : PublicArchive,
  transport : HttpTransport,
  acquisition_limits~ : AcquisitionLimits = AcquisitionLimits::new().unwrap(),
  limits~ : Limits = Limits::new(),
  cache~ : VerifiedCache? = None,
  mode~ : AcquisitionMode = Online,
) -> EntryTree raise ResourceError {
  check_limits(limits, self.url.location())
  let origin = Provenance::new(self.url.location())
  if limits.max_archive_bytes == 0 {
    raise ResourceError(ResourceLimit, origin, "Archive byte limit is zero")
  }
  let acquisition_limits = {
    ..acquisition_limits,
    max_bytes: Int32::min(
      acquisition_limits.max_bytes,
      limits.max_archive_bytes,
    ),
  }
  let acquired = acquire(
    self.url,
    transport,
    expected_digest=self.expected_digest,
    limits=acquisition_limits,
    cache~,
    mode~,
  )
  let response : HttpResponse = {
    resolved: acquired.metadata.resolved,
    status: 200,
    body: acquired.body,
  }
  let provenance = Provenance::new(response.resolved.location()).acquired(
    acquired.metadata,
  )
  let tree = try {
    match self.format {
      Zip =>
        EntryTree::zip(response.body, response.resolved.location(), limits~)
      Tar =>
        EntryTree::tar(response.body, response.resolved.location(), limits~)
      Tgz =>
        EntryTree::tgz(response.body, response.resolved.location(), limits~)
    }
  } catch {
    ResourceError(code, at, message) =>
      raise ResourceError(code, at.through(provenance), message)
  }
  { ..tree, provenance, }
}

///|
/// A repository location is a complete URL; its only artifact key is `.`.
pub fn register_public_http(
  registry : Registry,
  transport : HttpTransport,
  format~ : ArchiveFormat = Zip,
  expected_digest~ : ContentDigest? = None,
  acquisition_limits~ : AcquisitionLimits = AcquisitionLimits::new().unwrap(),
  limits~ : Limits = Limits::new(),
  cache~ : VerifiedCache? = None,
  mode~ : AcquisitionMode = Online,
) -> Registry raise ResourceError {
  registry.register_provider(ProviderId::parse("public-http").unwrap(), (
    repository,
    reference,
  ) => {
    let origin = Provenance::new(Location::Source(repository.location))
    guard reference.key.to_string() == "." &&
      HttpUrl::parse(repository.location.to_string()) is Some(url) else {
      raise ResourceError(
        InvalidResolution,
        origin,
        "Public HTTP repositories require an absolute credential-free URL and artifact key `.`",
      )
    }
    let tree = PublicArchive::{ url, format, expected_digest, }.open(
      transport,
      acquisition_limits~,
      limits~,
      cache~,
      mode~,
    )
    {
      reference,
      identity: ArtifactIdentity::parse(tree.origin.to_string()).unwrap(),
      tree,
    }
  })
}
