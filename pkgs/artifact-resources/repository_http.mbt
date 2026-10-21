///|
/// A credential-free HTTP repository base without query or fragment.
pub struct RepositoryUrl {
  priv url : HttpUrl
} derive(Eq, Debug)

///|
pub fn RepositoryUrl::parse(text : String) -> RepositoryUrl? {
  guard HttpUrl::parse(text) is Some(url) && !text.contains("?") else {
    return None
  }
  Some({
    url: HttpUrl::parse(url.to_string().trim_end(chars="/").to_owned()).unwrap(),
  })
}

///|
pub fn RepositoryUrl::to_string(self : RepositoryUrl) -> String {
  self.url.to_string()
}

///|
pub fn RepositoryUrl::location(self : RepositoryUrl) -> Location {
  self.url.location()
}

///|
fn RepositoryUrl::endpoint(
  self : RepositoryUrl,
  suffix : String,
) -> HttpUrl raise ResourceError {
  guard HttpUrl::parse(self.to_string() + "/" + suffix) is Some(url) else {
    raise ResourceError(
      InvalidResolution,
      Provenance::new(self.location()),
      "Repository endpoint exceeds supported URL bounds",
    )
  }
  url
}

///|
fn encode_repository_segment(text : String) -> String {
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
fn provider_json(data : AcquiredBytes) -> Json raise ResourceError {
  @json.parse(@utf8.decode(data.body)) catch {
    _ =>
      raise ResourceError(
        InvalidResolution,
        Provenance::new(data.metadata.resolved.location()).acquired(
          data.metadata,
        ),
        "Expected valid repository JSON metadata",
      )
  }
}
