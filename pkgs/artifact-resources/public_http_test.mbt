///|
fn url(text : String) -> @resources.HttpUrl {
  @resources.HttpUrl::parse(text).unwrap()
}

///|
test "public acquisition reuses tar and gzip readers and records compressed digest" {
  let tar = tar_record("package/a.txt", b"hello") + tar_end()
  for
    (format, body) in [
      (@resources.Tar, tar),
      (@resources.Tgz, @gzip.gzip_compress(tar)),
    ] {
    let requested = url("https://example.test/archive")
    let digest = @resources.ContentDigest::sha256(body)
    let request : @resources.PublicArchive = {
      url: requested,
      format,
      expected_digest: Some(digest),
    }
    let tree = request.open((_, _) => {
      resolved: requested,
      status: 200,
      body,
    })
    assert_eq(tree.digest, Some(digest))
    assert_eq(tree.text(entry("package/a.txt")), "hello")
    assert_eq(tree.provenance().steps(), [
      @resources.AcquisitionStep({ requested, resolved: requested, digest, }),
    ])
  }
}

///|
test "archive limits are applied before I/O and malformed archive diagnostics retain acquisition" {
  let requested = url("https://example.test/archive")
  let request : @resources.PublicArchive = {
    url: requested,
    format: @resources.Zip,
    expected_digest: None,
  }
  let calls = []
  let transport : @resources.HttpTransport = (_, limits) => {
    calls.push(limits.max_bytes)
    { resolved: requested, status: 200, body: b"invalid", }
  }
  let code = try
    request.open(transport, limits=@resources.Limits::new(max_archive_bytes=0))
  catch {
    @resources.ResourceError(code, _, _) => Some(code)
  } noraise {
    _ => None
  }
  assert_eq(code, Some(@resources.ResourceLimit))
  assert_eq(calls, [])
  let code = try
    request.open(transport, limits=@resources.Limits::new(max_archive_bytes=10))
  catch {
    @resources.ResourceError(code, at, _) => {
      assert_true(at.steps()[0] is @resources.AcquisitionStep(_))
      Some(code)
    }
  } noraise {
    _ => None
  }
  assert_eq(code, Some(@resources.InvalidArchive))
  assert_eq(calls, [10])
}

///|
test "public HTTP provider retains reference resolved URL digest and resource origin" {
  let bytes = archive({ "models/a.smithy": b"namespace example\nstring A" })
  let requested = url("https://example.test/download?id=1")
  let resolved = url("https://cdn.example.test/exact.zip")
  let digest = @resources.ContentDigest::sha256(bytes)
  let calls = []
  let registry = @resources.register_public_http(
    @resources.Registry::new(),
    (seen, limits) => {
      calls.push((seen.url, limits.max_bytes))
      { resolved, status: 200, body: bytes, }
    },
    expected_digest=Some(digest),
  ).add_repository({
    id: @resources.RepositoryId::parse("models").unwrap(),
    provider: @resources.ProviderId::parse("public-http").unwrap(),
    location: @resources.RepositoryLocation::parse(requested.to_string()).unwrap(),
  })
  let reference : @resources.ArtifactRef = {
    repository: @resources.RepositoryId::parse("models").unwrap(),
    key: @resources.ArtifactKey::parse(".").unwrap(),
  }
  let artifact = registry.resolve(reference)
  assert_eq(calls, [(requested, 67108864)])
  assert_eq(artifact.reference, reference)
  assert_eq(artifact.identity.to_string(), resolved.to_string())
  assert_eq(artifact.tree.digest, Some(digest))
  let selection = @resources.Selection::new(
    @resources.ResourceRoot::parse("models").unwrap(),
    [@resources.Exact(entry("a.smithy"))],
  ).unwrap()
  let resource = @resources.select_resources(artifact.tree, selection)[0]
  assert_eq(
    resource.origin,
    resolved.location().archive_entry(entry("models/a.smithy")),
  )
  assert_eq(resource.provenance.steps(), [
    @resources.ResolutionStep({ reference, identity: Some(artifact.identity), }),
    @resources.AcquisitionStep({ requested, resolved, digest, }),
  ])
  assert_eq(resource.text(), "namespace example\nstring A")
}

///|
test "HTTP status and integrity policy runs before archive or model parsing" {
  let requested = url("http://example.test/a.zip")
  let request : @resources.PublicArchive = {
    url: requested,
    format: @resources.Zip,
    expected_digest: None,
  }
  for
    (status, code) in [
      (401, @resources.AuthenticationRequired),
      (403, @resources.AuthenticationRequired),
      (404, @resources.MissingAsset),
      (410, @resources.MissingAsset),
      (500, @resources.HttpStatus),
      (206, @resources.HttpStatus),
      (302, @resources.HttpStatus),
    ] {
    let seen = try
      request.open((_, _) => {
        resolved: requested,
        status,
        body: b"not an archive",
      })
    catch {
      @resources.ResourceError(found, at, _) => {
        assert_true(at.steps()[0] is @resources.AcquisitionStep(_))
        Some(found)
      }
    } noraise {
      _ => None
    }
    assert_eq(seen, Some(code))
  }
  let checked : @resources.PublicArchive = {
    ..request,
    expected_digest: Some(@resources.ContentDigest::sha256(b"trusted")),
  }
  let seen = try
    checked.open((_, _) => {
      resolved: requested,
      status: 200,
      body: b"invalid archive",
    })
  catch {
    @resources.ResourceError(code, _, _) => Some(code)
  } noraise {
    _ => None
  }
  assert_eq(seen, Some(@resources.IntegrityFailure))
  let seen = try
    request.open(
      (_, _) => { resolved: requested, status: 200, body: b"12345", },
      acquisition_limits=@resources.AcquisitionLimits::new(max_bytes=4).unwrap(),
    )
  catch {
    @resources.ResourceError(code, _, _) => Some(code)
  } noraise {
    _ => None
  }
  assert_eq(seen, Some(@resources.ResourceLimit))
  let seen = try
    request.open((_, _) => {
      raise @resources.ResourceError(
        @resources.TransportFailure,
        @resources.Provenance::new(requested.location()),
        "fixture disconnect",
      )
    })
  catch {
    @resources.ResourceError(code, _, _) => Some(code)
  } noraise {
    _ => None
  }
  assert_eq(seen, Some(@resources.TransportFailure))
}

///|
test "public HTTP URL and acquisition boundary validation" {
  for
    invalid in [
      "http://:80/a", "http://host:abc/a", "http://host:65536/a", "http://host:0/a",
      "http://host:/a", "http://host/%", "http://host/%2G", "http://[::1/a", "http://[::1]bad/a",
    ] {
    assert_eq(@resources.HttpUrl::parse(invalid), None, msg=invalid)
  }
  assert_true(@resources.HttpUrl::parse("http://[::1]:8080/a.zip") is Some(_))
  for
    invalid in [
      "", "file:///a.zip", "https:///empty", "https://user:pass@example.test/a",
      "https://example.test/a#fragment", "https://example.test/\n", "https://example.test/a b",
      "https://example.test/é", "https://example.test/\\path", "https://user%40host/a",
    ] {
    assert_eq(@resources.HttpUrl::parse(invalid), None, msg=invalid)
  }
  assert_true(
    @resources.HttpUrl::parse("https://example.test/a%20b.zip?q=1&v=2")
    is Some(_),
  )
  assert_eq(@resources.AcquisitionLimits::new(max_bytes=0), None)
  assert_eq(@resources.AcquisitionLimits::new(timeout_seconds=0), None)
  assert_eq(@resources.AcquisitionLimits::new(max_bytes=1073741825), None)
}
