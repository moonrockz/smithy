///|
fn test_credentials(
  origin : String,
  token~ : String = "private-fixture-token",
) -> @resources.Credentials {
  @resources.Credentials::new(entries=[
    (
      @resources.HttpOrigin::parse(origin).unwrap(),
      @resources.Authorization::bearer(token).unwrap(),
    ),
  ]).unwrap()
}

///|
test "credentials validate secret boundaries normalize origins and redact debug" {
  let a = @resources.HttpOrigin::parse("https://EXAMPLE.test:443/").unwrap()
  assert_eq(a, @resources.HttpOrigin::parse("https://example.test").unwrap())
  for
    text in [
      "https://host/path", "https://user:pass@host", "https://host?query", "file:///tmp/x",
      "https://host/#fragment",
    ] {
    assert_eq(@resources.HttpOrigin::parse(text), None)
  }
  for
    text in [
      "", "bad\nheader", "two words", "bad\"quote", "=padding", "a=b", "\\option",
    ] {
    assert_eq(@resources.Authorization::bearer(text), None)
  }
  assert_eq(@resources.Authorization::basic("a:b", "secret"), None)
  assert_eq(@resources.Authorization::basic("a", "secret\r\nheader"), None)
  let auth = @resources.Authorization::basic("user", "private-password").unwrap()
  assert_eq(auth.header_value(), "Basic dXNlcjpwcml2YXRlLXBhc3N3b3Jk")
  let credentials = @resources.Credentials::new(entries=[(a, auth)]).unwrap()
  assert_eq(@resources.Credentials::new(entries=[(a, auth), (a, auth)]), None)
  assert_eq(
    @resources.Credentials::new(entries=[
      (@resources.HttpOrigin::parse("http://example.test").unwrap(), auth),
    ]),
    None,
  )
  assert_eq(credentials.for_url(url("https://example.test/a")), Some(auth))
  for
    text in [
      "http://example.test/a", "https://example.test:444/a", "https://other.test/a",
      "https://example.test.evil/a",
    ] {
    assert_eq(credentials.for_url(url(text)), None)
  }
  assert_eq(auth.to_string(), "<redacted>")
  let rendered = @debug.Repr(credentials).to_string()
  assert_false(rendered.contains("private-password"))
  assert_false(rendered.contains(auth.header_value()))
}

///|
test "authenticated acquisitions isolate cache lookups and content and retain offline provenance" {
  let values = Map([])
  let cache = Some(memory_cache(values))
  let requested = url("https://private.test/models.zip")
  let credentials = test_credentials("https://private.test")
  let body = b"private body"
  let calls = Ref(0)
  let transport : @resources.HttpTransport = (request, _) => {
    calls.val += 1
    if request.authorization != credentials.for_url(requested) {
      abort("wrong authorization")
    }
    { resolved: request.url, status: 200, body, }
  }
  let acquired = @resources.acquire(requested, transport, cache~, credentials~)
  let offline = @resources.acquire(
    requested,
    (_, _) => abort("offline network"),
    cache~,
    credentials~,
    mode=@resources.Offline,
  )
  assert_eq(offline.metadata, acquired.metadata)
  assert_eq(offline.body, body)
  assert_eq(calls.val, 1)
  for
    other in [
      @resources.Credentials::new().unwrap(),
      test_credentials("https://private.test", token="different-principal"),
      test_credentials("https://other.test"),
    ] {
    assert_eq(
      acquisition_code(() => {
        @resources.acquire(
          requested,
          transport,
          cache~,
          credentials=other,
          mode=@resources.Offline,
        )
      }),
      Some(@resources.OfflineMiss),
    )
  }
  // Reference keys, content keys and stored metadata do not serialize secrets.
  for key, value in values {
    assert_false(key.to_string().contains("private-fixture-token"))
    assert_false(key == @resources.CacheKey::content(acquired.metadata.digest))
    assert_false(@utf8.decode(value).contains("private-fixture-token"))
  }
  assert_eq(
    acquisition_code(() => {
      @resources.acquire(
        requested,
        transport,
        cache~,
        credentials~,
        accept=@resources.OctetStream,
        mode=@resources.Offline,
      )
    }),
    Some(@resources.OfflineMiss),
  )
}

///|
test "npm Maven and GitHub authenticate all acquisition steps and preserve offline loading" {
  let npm_body = @gzip.gzip_compress(
    tar_record("package/a.txt", b"hello") + tar_end(),
  )
  let jar = archive({ "a.txt": b"hello" })
  for provider in ["npm", "maven", "github"] {
    let origins = if provider == "npm" {
      ["https://registry.test", "https://archive.test"]
    } else if provider == "maven" {
      ["https://repo.test"]
    } else {
      ["https://api.test"]
    }
    let credentials = @resources.Credentials::new(
      entries=origins.map(origin => {
        (
          @resources.HttpOrigin::parse(origin).unwrap(),
          @resources.Authorization::bearer("provider-secret").unwrap(),
        )
      }),
    ).unwrap()
    let backend = match provider {
      "npm" => npm_transport(npm_body)
      "maven" => maven_transport(jar)
      _ => github_transport(jar)
    }
    let requests : Array[@resources.HttpRequest] = []
    let transport : @resources.HttpTransport = (request, bounds) => {
      requests.push(request)
      if request.authorization.map(auth => auth.header_value()) !=
        Some("Bearer provider-secret") {
        abort("wrong provider authorization")
      }
      backend(request, bounds)
    }
    let cache = Some(memory_cache(Map([])))
    fn open(
      transport : @resources.HttpTransport,
      mode : @resources.AcquisitionMode,
    ) -> @resources.EntryTree raise @resources.ResourceError {
      match provider {
        "npm" => npm_request().open(transport, cache~, mode~, credentials~)
        "maven" => maven_request().open(transport, cache~, mode~, credentials~)
        _ =>
          github_request().open(
            transport,
            api=url("https://api.test"),
            cache~,
            mode~,
            credentials~,
          )
      }
    }
    let tree = open(transport, @resources.Online)
    let path = entry(if provider == "npm" { "package/a.txt" } else { "a.txt" })
    assert_eq(tree.text(path), "hello")
    let offline = open(
      (_, _) => abort("provider used network offline"),
      @resources.Offline,
    )
    assert_eq(offline.provenance().steps(), tree.provenance().steps())
    assert_eq(offline.text(path), "hello")
    assert_eq(requests.length(), if provider == "github" { 3 } else { 2 })
    if provider == "github" {
      let last = requests.last().unwrap()
      assert_eq(
        last.url.to_string(),
        "https://api.test/repos/owner/models/releases/assets/42",
      )
      assert_eq(last.accept, @resources.OctetStream)
    }
    for status in [401, 403] {
      let failed : @resources.HttpTransport = (request, _) => {
        resolved: request.url,
        status,
        body: b"server body is not a diagnostic",
      }
      fn fail() -> @resources.EntryTree raise @resources.ResourceError {
        match provider {
          "npm" => npm_request().open(failed, credentials~)
          "maven" => maven_request().open(failed, credentials~)
          _ =>
            github_request().open(
              failed,
              api=url("https://api.test"),
              credentials~,
            )
        }
      }
      assert_eq(repository_code(fail), Some(@resources.AuthenticationRequired))
    }
  }
}
