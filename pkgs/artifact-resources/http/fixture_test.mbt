///|
/// The task-script fixture harness supplies a loopback server. Portable policy
/// tests run unconditionally in the parent package on all four backends.
test "controlled HTTP host fixture" {
  guard @env.get_env_var("SMITHY_HTTP_FIXTURE") is Some(base) else { return }
  let limits = @resources.AcquisitionLimits::new(
    max_bytes=1024,
    timeout_seconds=1,
  ).unwrap()
  for path in ["/bytes", "/relative", "/absolute", "/fragment"] {
    let response = @http.transport(
      @resources.HttpRequest::anonymous(
        @resources.HttpUrl::parse(base + path).unwrap(),
      ),
      limits,
    )
    assert_eq(response.body, b"fixture\n200\nhttps://fake.invalid/a\x00")
    assert_eq(response.status, 200)
    assert_eq(response.resolved.to_string(), base + "/bytes")
  }
  for
    (path, status) in [
      ("/missing", 404),
      ("/auth", 401),
      ("/forbidden", 403),
      ("/failure", 500),
    ] {
    let response = @http.transport(
      @resources.HttpRequest::anonymous(
        @resources.HttpUrl::parse(base + path).unwrap(),
      ),
      limits,
    )
    assert_eq(response.status, status)
  }
  for
    (path, code) in [
      ("/loop", @resources.TransportFailure),
      ("/disconnect", @resources.TransportFailure),
      ("/slow", @resources.AcquisitionTimeout),
      ("/slow-redirect", @resources.AcquisitionTimeout),
      ("/large", @resources.ResourceLimit),
      ("/stream", @resources.ResourceLimit),
      ("/file-redirect", @resources.TransportFailure),
      ("/credential-redirect", @resources.TransportFailure),
    ] {
    let actual = try
      @http.transport(
        @resources.HttpRequest::anonymous(
          @resources.HttpUrl::parse(base + path).unwrap(),
        ),
        limits,
      )
    catch {
      @resources.ResourceError(code, _, _) => Some(code)
    } noraise {
      _ => None
    }
    assert_eq(actual, Some(code), msg=path)
  }
  // HTTPS to a plain HTTP loopback peer must fail TLS, never silently fall back.
  let tls_url = base.replace(old="http://", new="https://") + "/bytes"
  let rejected = try
    @http.transport(
      @resources.HttpRequest::anonymous(
        @resources.HttpUrl::parse(tls_url).unwrap(),
      ),
      limits,
    )
  catch {
    @resources.ResourceError(_, _, _) => true
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "unsupported hosts fail explicitly without I/O" {
  if @env.get_env_var("SMITHY_UNSUPPORTED_HTTP_TEST") == Some("1") {
    let code = try
      @http.transport(
        @resources.HttpRequest::anonymous(
          @resources.HttpUrl::parse("https://example.invalid/a.zip").unwrap(),
        ),
        @resources.AcquisitionLimits::new().unwrap(),
      )
    catch {
      @resources.ResourceError(code, _, _) => Some(code)
    } noraise {
      _ => None
    }
    assert_eq(code, Some(@resources.UnsupportedTransport))
  }
}
