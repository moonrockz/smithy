///|
/// Native hosts and Node.js use curl on PATH, with its verified HTTPS stack.
/// Wasm hosts return unsupported-transport without attempting filesystem/network I/O.
pub fn transport(
  url : @resources.HttpUrl,
  limits : @resources.AcquisitionLimits,
) -> @resources.HttpResponse raise @resources.ResourceError {
  let origin = @resources.Provenance::new(url.location())
  let result = run(url.to_string(), limits.max_bytes, limits.timeout_seconds)
  guard result is [u32le(code), ..] else {
    raise @resources.ResourceError(
      @resources.TransportFailure,
      origin,
      "Invalid transport result",
    )
  }
  if code != 0 {
    if code == 255 {
      raise @resources.ResourceError(
        @resources.UnsupportedTransport,
        origin,
        "Public HTTP acquisition is unavailable on this backend; supply a host HttpTransport",
      )
    }
    let kind = match code {
      28 => @resources.AcquisitionTimeout
      63 => @resources.ResourceLimit
      _ => @resources.TransportFailure
    }
    raise @resources.ResourceError(
      kind,
      origin,
      "curl transport failed with code \{code}; native and Node.js hosts require curl on PATH",
    )
  }
  // curl appends metadata after the binary body. Parse backwards so arbitrary
  // archive bytes, including newlines and NULs, cannot become response metadata.
  let mut end = result.length() - 1
  while end >= 4 && result[end] != b'\n' {
    end -= 1
  }
  guard end >= 8 else {
    raise @resources.ResourceError(
      @resources.TransportFailure,
      origin,
      "Missing HTTP response metadata",
    )
  }
  let resolved_text = @utf8.decode(result[end + 1:]) catch {
    _ =>
      raise @resources.ResourceError(
        @resources.TransportFailure,
        origin,
        "Invalid resolved URL encoding",
      )
  }
  // A redirect fragment is client-side metadata and is not sent in the GET.
  let retrieval_url = resolved_text.split("#").next().unwrap().to_owned()
  guard @resources.HttpUrl::parse(retrieval_url) is Some(resolved) &&
    result[end - 4] == b'\n' else {
    raise @resources.ResourceError(
      @resources.TransportFailure,
      origin,
      "Invalid resolved URL or HTTP status",
    )
  }
  let mut status = 0
  for byte in result[end - 3:end] {
    if byte < b'0' || byte > b'9' {
      raise @resources.ResourceError(
        @resources.TransportFailure,
        origin,
        "Invalid HTTP status",
      )
    }
    status = status * 10 + byte.to_int() - 48
  }
  let body = result[4:end - 4].to_owned()
  if body.length() > limits.max_bytes {
    raise @resources.ResourceError(
      @resources.ResourceLimit,
      origin,
      "Download exceeds byte limit",
    )
  }
  { resolved, status, body, }
}
