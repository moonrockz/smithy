///|
/// Native hosts and Node.js use curl on PATH, with its verified HTTPS stack.
/// Wasm hosts return unsupported-transport without attempting filesystem/network I/O.
fn transfer(
  request : @resources.HttpRequest,
  limits : @resources.AcquisitionLimits,
  milliseconds : Int32,
) -> (@resources.HttpResponse, String) raise @resources.ResourceError {
  let url = request.url
  let origin = @resources.Provenance::new(url.location())
  let header = match request.authorization {
    None => ""
    Some(auth) => "header = \"Authorization: " + auth.header_value() + "\"\n"
  }
  let config = header +
    (if request.accept == @resources.OctetStream {
      "header = \"Accept: application/octet-stream\"\n"
    } else {
      ""
    })
  let result = run(url.to_string(), limits.max_bytes, milliseconds, config)
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
  // Parse three trailing lines backwards, leaving the binary body untouched.
  let mut redirect_line = result.length() - 1
  while redirect_line >= 4 && result[redirect_line] != b'\n' {
    redirect_line -= 1
  }
  let mut url_line = redirect_line - 1
  while url_line >= 4 && result[url_line] != b'\n' {
    url_line -= 1
  }
  guard url_line >= 8 && result[url_line - 4] == b'\n' else {
    raise @resources.ResourceError(
      @resources.TransportFailure,
      origin,
      "Missing HTTP response metadata",
    )
  }
  let resolved_text = @utf8.decode(result[url_line + 1:redirect_line]) catch {
    _ =>
      raise @resources.ResourceError(
        @resources.TransportFailure,
        origin,
        "Invalid resolved URL encoding",
      )
  }
  let retrieval_url = resolved_text.split("#").next().unwrap().to_owned()
  guard @resources.HttpUrl::parse(retrieval_url) is Some(resolved) else {
    raise @resources.ResourceError(
      @resources.TransportFailure,
      origin,
      "Invalid resolved URL",
    )
  }
  let mut status = 0
  for byte in result[url_line - 3:url_line] {
    if byte < b'0' || byte > b'9' {
      raise @resources.ResourceError(
        @resources.TransportFailure,
        origin,
        "Invalid HTTP status",
      )
    }
    status = status * 10 + byte.to_int() - 48
  }
  let body = result[4:url_line - 4].to_owned()
  if body.length() > limits.max_bytes {
    raise @resources.ResourceError(
      @resources.ResourceLimit,
      origin,
      "Download exceeds byte limit",
    )
  }
  let redirect = @utf8.decode(result[redirect_line + 1:]) catch {
    _ =>
      raise @resources.ResourceError(
        @resources.TransportFailure,
        origin,
        "Invalid redirect encoding",
      )
  }
  ({ resolved, status, body, }, redirect)
}

///|
/// Follow redirects at the typed boundary. Only the initial origin may receive
/// authorization; another origin's configured credentials are never introduced.
pub fn transport(
  request : @resources.HttpRequest,
  limits : @resources.AcquisitionLimits,
) -> @resources.HttpResponse raise @resources.ResourceError {
  let origin = @resources.Provenance::new(request.url.location())
  if request.authorization is Some(_) &&
    !request.url.origin().permits_credentials() {
    raise @resources.ResourceError(
      @resources.InvalidResolution,
      origin,
      "Credentials require HTTPS, except on loopback",
    )
  }
  let deadline = now_ms() + limits.timeout_seconds.to_double() * 1000.0
  let mut current = request.url
  for redirects = 0; ; redirects = redirects + 1 {
    let remaining = deadline - now_ms()
    if remaining <= 0.0 {
      raise @resources.ResourceError(
        @resources.AcquisitionTimeout,
        origin,
        "HTTP acquisition deadline exceeded",
      )
    }
    let (response, redirect) = transfer(
      {
        ..request,
        url: current,
        authorization: if current.origin() == request.url.origin() {
          request.authorization
        } else {
          None
        },
      },
      limits,
      Int32::max(1, remaining.to_int()),
    )
    if now_ms() > deadline {
      raise @resources.ResourceError(
        @resources.AcquisitionTimeout,
        origin,
        "HTTP acquisition deadline exceeded",
      )
    }
    if ![301, 302, 303, 307, 308].contains(response.status) || redirect == "" {
      return response
    }
    if redirects == 5 {
      raise @resources.ResourceError(
        @resources.TransportFailure,
        origin,
        "HTTP acquisition exceeds five redirects",
      )
    }
    let retrieval = redirect.split("#").next().unwrap().to_owned()
    guard @resources.HttpUrl::parse(retrieval) is Some(next) &&
      !(current.to_string().has_prefix("https:") &&
      next.to_string().has_prefix("http:")) else {
      raise @resources.ResourceError(
        @resources.TransportFailure,
        origin,
        "Unsafe HTTP redirect destination",
      )
    }
    current = next
  }
}
