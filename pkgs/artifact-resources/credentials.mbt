///|
/// A normalized scheme/host/port identity. Paths and queries are not origins.
pub struct HttpOrigin {
  priv value : String
} derive(Eq, Debug)

///|
pub fn HttpUrl::origin(self : HttpUrl) -> HttpOrigin {
  let text = self.to_string()
  let scheme_end = text.find("://").unwrap() + 3
  let authority = text[scheme_end:]
    .split("/")
    .next()
    .unwrap()
    .split("?")
    .next()
    .unwrap()
    .to_owned()
    .to_lower()
  let scheme = text[:scheme_end].to_owned()
  let port_at = if authority.has_prefix("[") {
    authority.find("]:").map(i => i + 1)
  } else {
    authority.find(":")
  }
  let authority = match port_at {
    None => authority
    Some(at) => {
      let mut port = 0
      for digit in authority[at + 1:].iter() {
        port = port * 10 + digit.to_int() - 48
      }
      let host = authority[:at].to_owned()
      if (scheme == "https://" && port == 443) ||
        (scheme == "http://" && port == 80) {
        host
      } else {
        host + ":" + port.to_string()
      }
    }
  }
  { value: scheme + authority, }
}

///|
pub fn HttpOrigin::parse(text : String) -> HttpOrigin? {
  guard HttpUrl::parse(text) is Some(url) else { return None }
  let origin = url.origin()
  let text = url.to_string()
  let authority_start = text.find("://").unwrap() + 3
  let parts = text[authority_start:].split("/").to_array()
  if text.contains("?") ||
    parts.length() > 2 ||
    (parts.length() == 2 && parts[1] != "") {
    return None
  }
  Some(origin)
}

///|
pub fn HttpOrigin::to_string(self : HttpOrigin) -> String {
  self.value
}

///|
pub fn HttpOrigin::permits_credentials(self : HttpOrigin) -> Bool {
  if self.value.has_prefix("https://") {
    return true
  }
  let host = self.value[7:].to_owned()
  host == "localhost" ||
  host.has_prefix("localhost:") ||
  host == "127.0.0.1" ||
  host.has_prefix("127.0.0.1:") ||
  host == "[::1]" ||
  host.has_prefix("[::1]:")
}

///|
/// Secret authorization material. Debug and Show never render the value.
pub struct Authorization {
  priv header : String
} derive(Eq)

///|
pub fn Authorization::bearer(token : String) -> Authorization? {
  if token.is_empty() || token.length() > 4096 {
    return None
  }
  let mut padding = false
  for c in token.iter() {
    if c == '=' {
      padding = true
    } else if padding ||
      !"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~+/".contains(
        c.to_string(),
      ) {
      return None
    }
  }
  if token.code_unit_at(0) == 61 {
    return None
  }
  Some({ header: "Bearer " + token, })
}

///|
pub fn Authorization::basic(
  username : String,
  password : String,
) -> Authorization? {
  if username.is_empty() ||
    password.is_empty() ||
    username.contains(":") ||
    username.length() + password.length() > 4096 ||
    (username + password).iter().any(c => c.to_int() < 32 || c.to_int() == 127) {
    return None
  }
  Some({
    header: "Basic " +
    @base64.encode(@utf8.encode(username + ":" + password)[:]),
  })
}

///|
/// Only host adapters should call this at the wire boundary. Never log it.
pub fn Authorization::header_value(self : Authorization) -> String {
  self.header
}

///|
pub impl Debug for Authorization with fn to_repr(_) {
  @debug.Repr::literal("<redacted>")
}

///|
pub impl Show for Authorization with fn output(_, logger) {
  logger.write_string("<redacted>")
}

///|
/// One explicit authorization per origin. No ambient credentials are discovered.
pub struct Credentials {
  priv entries : Array[(HttpOrigin, Authorization)]
} derive(Eq, Debug)

///|
pub fn Credentials::new(
  entries~ : Array[(HttpOrigin, Authorization)] = [],
) -> Credentials? {
  if entries.length() > 32 {
    return None
  }
  for i, (origin, _) in entries {
    if !origin.permits_credentials() ||
      entries[:i].any(pair => pair.0 == origin) {
      return None
    }
  }
  Some({ entries: entries.copy(), })
}

///|
pub fn Credentials::for_url(
  self : Credentials,
  url : HttpUrl,
) -> Authorization? {
  for (origin, authorization) in self.entries {
    if origin == url.origin() {
      return Some(authorization)
    }
  }
  None
}

///|
pub(all) enum HttpAccept {
  AnyContent
  OctetStream
} derive(Eq, Debug)

///|
/// Authorization is never part of a URL or provenance. Redirects must strip it
/// when the destination's origin differs, even if another credential is configured.
pub(all) struct HttpRequest {
  url : HttpUrl
  authorization : Authorization?
  accept : HttpAccept
} derive(Eq, Debug)

///|
pub fn HttpRequest::anonymous(url : HttpUrl) -> HttpRequest {
  { url, authorization: None, accept: AnyContent, }
}

///|
pub fn HttpRequest::to_string(self : HttpRequest) -> String {
  self.url.to_string()
}

///|
pub fn HttpRequest::location(self : HttpRequest) -> Location {
  self.url.location()
}
