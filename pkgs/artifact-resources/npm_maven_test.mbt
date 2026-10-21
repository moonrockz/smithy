///|
fn npm_reference(
  name~ : String = "@acme/models",
  version~ : String = "1.2.3-rc.1+build.1",
) -> @resources.NpmPackageRef {
  {
    name: @resources.NpmPackageName::parse(name).unwrap(),
    version: @resources.NpmVersion::parse(version).unwrap(),
  }
}

///|
fn npm_request(
  reference~ : @resources.NpmPackageRef = npm_reference(),
) -> @resources.NpmArchive {
  {
    registry: @resources.RepositoryUrl::parse("https://registry.test/npm").unwrap(),
    reference,
    expected_digest: None,
  }
}

///|
fn npm_sri(
  body : Bytes,
  algorithm~ : @resources.ChecksumAlgorithm = @resources.Sha512,
) -> String {
  let digest = match algorithm {
    @resources.Sha1 => @crypto.sha1(body)
    @resources.Sha256 => @crypto.sha256(body)
    @resources.Sha512 => @crypto.sha512(body)
  }
  algorithm.to_string() +
  "-" +
  @base64.encode(Bytes::from_array(digest.iter().to_array())[:])
}

///|
fn npm_metadata(
  reference : @resources.NpmPackageRef,
  body : Bytes,
  integrity~ : String? = None,
) -> Json {
  {
    "name": reference.name.to_string(),
    "version": reference.version.to_string(),
    "dist": {
      "tarball": "https://archive.test/models.tgz",
      "integrity": integrity.unwrap_or(npm_sri(body)),
    },
    "scripts": { "install": "must never execute" },
  }
}

///|
fn npm_transport(
  body : Bytes,
  reference~ : @resources.NpmPackageRef = npm_reference(),
  metadata~ : Json? = None,
  calls~ : Array[String] = [],
) -> @resources.HttpTransport {
  (requested, _) => {
    calls.push(requested.to_string())
    let is_metadata = requested.to_string().has_prefix("https://registry.test/")
    {
      resolved: if is_metadata {
        requested
      } else {
        url("https://cdn.test/pinned.tgz")
      },
      status: 200,
      body: if is_metadata {
        @utf8.encode(
          metadata.unwrap_or(npm_metadata(reference, body)).stringify(),
        )
      } else {
        body
      },
    }
  }
}

///|
fn maven_coordinates(
  classifier~ : String? = None,
) -> @resources.MavenCoordinates {
  {
    group: @resources.MavenGroupId::parse("org.example").unwrap(),
    artifact: @resources.MavenArtifactId::parse("models").unwrap(),
    version: @resources.MavenVersion::parse("1.2.3.Final").unwrap(),
    classifier: classifier.map(text => {
      @resources.MavenClassifier::parse(text).unwrap()
    }),
  }
}

///|
fn maven_request() -> @resources.MavenArchive {
  {
    repository: @resources.RepositoryUrl::parse("https://repo.test/maven2").unwrap(),
    coordinates: maven_coordinates(),
    checksum: @resources.Sha1Sidecar,
    expected_digest: None,
  }
}

///|
fn maven_transport(
  body : Bytes,
  calls~ : Array[String] = [],
) -> @resources.HttpTransport {
  (requested, _) => {
    let text = requested.to_string()
    calls.push(text)
    let data = if text.has_suffix(".sha1") {
      @utf8.encode(@crypto.bytes_to_hex_string(@crypto.sha1(body)) + "\n")
    } else if text.has_suffix(".sha256") {
      @utf8.encode(
        @resources.ContentDigest::sha256(body).to_string()[7:].to_owned(),
      )
    } else {
      body
    }
    { resolved: requested, status: 200, body: data, }
  }
}

///|
fn repository_code(
  action : () -> @resources.EntryTree raise @resources.ResourceError,
) -> @resources.ResourceCode? {
  try action() catch {
    @resources.ResourceError(code, _, _) => Some(code)
  } noraise {
    _ => None
  }
}

///|
test "npm exact scoped and unscoped versions resolve with typed provenance and offline metadata" {
  let body = @gzip.gzip_compress(
    tar_record("package/models/a.txt", b"hello") +
    tar_record(
      "package/package.json", b"{\"scripts\":{\"install\":\"exit 99\"}}",
    ) +
    tar_end(),
  )
  for name in ["models", "@acme/models"] {
    let reference = npm_reference(name~)
    let calls = []
    let cache = memory_cache(Map([]))
    let request = npm_request(reference~)
    let registry = @resources.register_npm(
      @resources.Registry::new(),
      npm_transport(body, reference~, calls~),
      cache=Some(cache),
    ).add_repository({
      id: @resources.RepositoryId::parse("npm").unwrap(),
      provider: @resources.ProviderId::parse("npm").unwrap(),
      location: @resources.RepositoryLocation::parse(
        request.registry.to_string(),
      ).unwrap(),
    })
    let artifact = registry.resolve({
      repository: @resources.RepositoryId::parse("npm").unwrap(),
      key: reference.key(),
    })
    assert_eq(artifact.tree.text(entry("package/models/a.txt")), "hello")
    assert_eq(
      artifact.tree.digest,
      Some(@resources.ContentDigest::sha256(body)),
    )
    assert_eq(calls, [
      "https://registry.test/npm/" +
      (if name == "models" { "models" } else { "%40acme%2Fmodels" }) +
      "/1.2.3-rc.1%2Bbuild.1",
      "https://archive.test/models.tgz",
    ])
    let offline = request.open(
      (_, _) => abort("offline transport called"),
      cache=Some(cache),
      mode=@resources.Offline,
    )
    assert_eq(
      offline.provenance().steps(),
      artifact.tree.provenance().steps()[1:].to_owned(),
    )
    let at = offline.entry_origin(entry("package/models/a.txt"))
    assert_eq(
      at.to_string(),
      "https://cdn.test/pinned.tgz!/package/models/a.txt",
    )
    assert_true(offline.provenance().steps()[0] is @resources.NpmStep(_))
    assert_true(artifact.identity.to_string().contains(reference.to_string()))
    assert_eq(calls.length(), 2)
  }
}

///|
test "npm integrity strongest algorithm policy legacy shasum and unsupported metadata" {
  let body = @gzip.gzip_compress(
    tar_record("package/a.txt", b"hello") + tar_end(),
  )
  for algorithm in [@resources.Sha1, @resources.Sha256, @resources.Sha512] {
    let integrity = npm_sri(body, algorithm~)
    assert_eq(
      npm_request()
      .open(
        npm_transport(
          body,
          metadata=Some(
            npm_metadata(npm_reference(), body, integrity=Some(integrity)),
          ),
        ),
      )
      .text(entry("package/a.txt")),
      "hello",
    )
  }
  let reference = npm_reference()
  let legacy : Json = {
    "name": reference.name.to_string(),
    "version": reference.version.to_string(),
    "dist": {
      "tarball": "https://archive.test/models.tgz",
      "shasum": @crypto.bytes_to_hex_string(@crypto.sha1(body)),
    },
  }
  assert_eq(
    npm_request()
    .open(npm_transport(body, metadata=Some(legacy)))
    .text(entry("package/a.txt")),
    "hello",
  )
  for
    (integrity, expected) in [
      (
        npm_sri(body, algorithm=@resources.Sha1) + " " + npm_sri(b"wrong"),
        @resources.IntegrityFailure,
      ),
      (npm_sri(b"wrong"), @resources.IntegrityFailure),
      ("sha384-AAAA", @resources.UnsupportedIntegrity),
      ("sha512-not-base64!", @resources.UnsupportedIntegrity),
      ("sha512-AAAA", @resources.UnsupportedIntegrity),
      ("", @resources.UnsupportedIntegrity),
    ] {
    let values = Map([])
    let metadata = npm_metadata(reference, body, integrity=Some(integrity))
    assert_eq(
      repository_code(() => {
        npm_request().open(
          npm_transport(body, metadata=Some(metadata)),
          cache=Some(memory_cache(values)),
        )
      }),
      Some(expected),
    )
    assert_eq(
      values.get(
        @resources.CacheKey::content(@resources.ContentDigest::sha256(body)),
      ),
      None,
    )
  }
  let strongest = npm_sri(b"wrong", algorithm=@resources.Sha1) +
    "\t" +
    npm_sri(body)
  assert_true(@resources.NpmIntegrity::parse_sri(strongest) is Some(_))
  let parsed = @resources.NpmIntegrity::parse_sri(strongest).unwrap()
  parsed.verify(
    body,
    @resources.Provenance::new(url("https://fixture.test").location()),
  )
  let alternatives = npm_sri(b"wrong") + " " + npm_sri(body)
  @resources.NpmIntegrity::parse_sri(alternatives)
  .unwrap()
  .verify(
    body,
    @resources.Provenance::new(url("https://fixture.test").location()),
  )
}

///|
test "npm rejects mismatched invalid metadata before archive parsing and enforces cached integrity" {
  let reference = npm_reference()
  let body = b"not an archive"
  let documents : Array[Json] = [
    {
      "name": "wrong",
      "version": reference.version.to_string(),
      "dist": { "tarball": "https://archive.test/a" },
    },
    {
      "name": reference.name.to_string(),
      "version": "9.9.9",
      "dist": { "tarball": "https://archive.test/a" },
    },
    {
      "name": reference.name.to_string(),
      "version": reference.version.to_string(),
      "dist": { "tarball": "https://user:password@archive.test/a" },
    },
  ]
  for metadata in documents {
    assert_eq(
      repository_code(() => {
        npm_request().open(npm_transport(body, metadata=Some(metadata)))
      }),
      Some(@resources.InvalidResolution),
    )
  }
  let values = Map([])
  let cache = memory_cache(values)
  let endpoint = url("https://archive.test/models.tgz")
  ignore(
    @resources.acquire(
      endpoint,
      (_, _) => { resolved: endpoint, status: 200, body, },
      cache=Some(cache),
    ),
  )
  let metadata = npm_metadata(
    reference,
    body,
    integrity=Some(npm_sri(b"different")),
  )
  assert_eq(
    repository_code(() => {
      npm_request().open(
        npm_transport(body, metadata=Some(metadata)),
        cache=Some(cache),
      )
    }),
    Some(@resources.IntegrityFailure),
  )
  assert_eq(
    repository_code(() => {
      npm_request().open(
        (_, _) => abort("offline called transport"),
        cache=Some(cache),
        mode=@resources.Offline,
      )
    }),
    Some(@resources.IntegrityFailure),
  )
  assert_eq(
    repository_code(() => {
      npm_request().open(npm_transport(body), mode=@resources.Offline)
    }),
    Some(@resources.OfflineMiss),
  )
}

///|
test "npm repository error status and metadata bounds are deterministic" {
  for
    (status, expected) in [
      (404, @resources.MissingPackageVersion),
      (401, @resources.AuthenticationRequired),
      (403, @resources.AuthenticationRequired),
      (429, @resources.RateLimited),
      (500, @resources.HttpStatus),
      (200, @resources.InvalidResolution),
    ] {
    assert_eq(
      repository_code(() => {
        npm_request().open((requested, _) => {
          resolved: requested,
          status,
          body: b"invalid",
        })
      }),
      Some(expected),
    )
  }
  assert_eq(
    repository_code(() => {
      npm_request().open(
        (requested, _) => {
          resolved: requested,
          status: 200,
          body: Bytes::make(65, 65),
        },
        acquisition_limits=@resources.AcquisitionLimits::new(max_bytes=64).unwrap(),
      )
    }),
    Some(@resources.ResourceLimit),
  )
}

///|
test "Maven direct JAR and classifier resolve through registry and offline checksums" {
  let body = archive({
    "META-INF/smithy/manifest": b"a.smithy\n",
    "META-INF/smithy/a.smithy": b"namespace example\nstring A",
  })
  for checksum in [@resources.Sha1Sidecar, @resources.Sha256Sidecar] {
    let request = {
      ..maven_request(),
      checksum,
      coordinates: maven_coordinates(classifier=Some("models")),
    }
    let calls = []
    let cache = memory_cache(Map([]))
    let registry = @resources.register_maven(
      @resources.Registry::new(),
      maven_transport(body, calls~),
      checksum~,
      cache=Some(cache),
    ).add_repository({
      id: @resources.RepositoryId::parse("central").unwrap(),
      provider: @resources.ProviderId::parse("maven").unwrap(),
      location: @resources.RepositoryLocation::parse(
        request.repository.to_string(),
      ).unwrap(),
    })
    let artifact = registry.resolve({
      repository: @resources.RepositoryId::parse("central").unwrap(),
      key: request.coordinates.key(),
    })
    assert_eq(
      artifact.tree.read(entry("META-INF/smithy/a.smithy")),
      b"namespace example\nstring A",
    )
    let root = "https://repo.test/maven2/org/example/models/1.2.3.Final/models-1.2.3.Final-models.jar"
    assert_eq(calls, [root + "." + checksum.algorithm().to_string(), root])
    let offline = request.open(
      (_, _) => abort("offline transport called"),
      cache=Some(cache),
      mode=@resources.Offline,
    )
    assert_eq(
      offline.provenance().steps(),
      artifact.tree.provenance().steps()[1:].to_owned(),
    )
    assert_eq(offline.digest, Some(@resources.ContentDigest::sha256(body)))
    assert_true(
      artifact.identity
      .to_string()
      .contains("org.example:models:1.2.3.Final:models"),
    )
    assert_true(offline.provenance().steps()[0] is @resources.MavenStep(_))
  }
}

///|
test "Maven explicit SHA256 takes precedence and bad checksums never populate archive cache" {
  let body = archive({ "a.txt": b"hello" })
  let calls = []
  let request = {
    ..maven_request(),
    expected_digest: Some(@resources.ContentDigest::sha256(body)),
  }
  assert_eq(
    request.open(maven_transport(body, calls~)).text(entry("a.txt")),
    "hello",
  )
  assert_eq(calls.length(), 1)
  assert_true(calls[0].has_suffix(".jar"))
  let bad = {
    ..request,
    expected_digest: Some(@resources.ContentDigest::sha256(b"wrong")),
  }
  assert_eq(
    repository_code(() => bad.open(maven_transport(body))),
    Some(@resources.IntegrityFailure),
  )
  for
    (sidecar, expected) in [
      (b"garbage", @resources.InvalidResolution),
      (@utf8.encode("0".repeat(40)), @resources.IntegrityFailure),
    ] {
    let values = Map([])
    let transport : @resources.HttpTransport = (requested, _) => {
      resolved: requested,
      status: 200,
      body: if requested.to_string().has_suffix(".sha1") {
        sidecar
      } else {
        body
      },
    }
    assert_eq(
      repository_code(() => {
        maven_request().open(transport, cache=Some(memory_cache(values)))
      }),
      Some(expected),
    )
    assert_eq(
      values.get(
        @resources.CacheKey::content(@resources.ContentDigest::sha256(body)),
      ),
      None,
    )
  }
}

///|
test "Maven repository selection isolates identical coordinates and cache references" {
  let values = Map([])
  let cache = memory_cache(values)
  let registry = @resources.register_maven(
    @resources.Registry::new(),
    (requested, _) => {
      let text = requested.to_string()
      let body = if text.has_prefix("https://one.test/") {
        b"one"
      } else {
        b"two"
      }
      { resolved: requested, status: 200, body, }
    },
    expected_digest=Some(@resources.ContentDigest::sha256(b"one")),
    cache=Some(cache),
  )
  for base in ["one", "two"] {
    ignore(
      registry.add_repository({
        id: @resources.RepositoryId::parse(base).unwrap(),
        provider: @resources.ProviderId::parse("maven").unwrap(),
        location: @resources.RepositoryLocation::parse(
          "https://" + base + ".test/maven2",
        ).unwrap(),
      }),
    )
  }
  // The first body's integrity succeeds and archive parsing fails; the second
  // repository must fetch its own bytes and fail integrity instead.
  for
    (name, expected) in [
      ("one", @resources.InvalidArchive),
      ("two", @resources.IntegrityFailure),
    ] {
    let code = try
      registry.resolve({
        repository: @resources.RepositoryId::parse(name).unwrap(),
        key: maven_coordinates().key(),
      })
    catch {
      @resources.ResourceError(code, _, _) => Some(code)
    } noraise {
      _ => None
    }
    assert_eq(code, Some(expected))
  }
}

///|
test "Maven statuses and all reference boundary constructors fail safely" {
  for
    (status, expected) in [
      (404, @resources.MissingArtifact),
      (401, @resources.AuthenticationRequired),
      (403, @resources.AuthenticationRequired),
      (429, @resources.RateLimited),
      (500, @resources.HttpStatus),
    ] {
    assert_eq(
      repository_code(() => {
        maven_request().open((requested, _) => {
          resolved: requested,
          status,
          body: b"error",
        })
      }),
      Some(expected),
    )
  }
  for
    invalid in [
      "", "@scope", "@scope/", "a/b", "../a", "UPPER", "_hidden", "node_modules",
      "name?query",
    ] {
    assert_eq(@resources.NpmPackageName::parse(invalid), None, msg=invalid)
  }
  for
    invalid in [
      "", "latest", "^1.2.3", "1.2", "v1.2.3", "01.2.3", "1.2.3-01", "1.2.3+", "1.2.3/../a",
    ] {
    assert_eq(@resources.NpmVersion::parse(invalid), None, msg=invalid)
  }
  for valid in ["1.2.3", "0.0.0", "1.2.3-beta.0+build.01"] {
    assert_true(@resources.NpmVersion::parse(valid) is Some(_))
  }
  for
    invalid in [
      "", "../a", "1.0-SNAPSHOT", "SNAPSHOT", "1.0-20261021.123456-1", "LATEST",
      "RELEASE", "[1,2)", "1.+", "a/b", "1.0?x",
    ] {
    assert_eq(@resources.MavenVersion::parse(invalid), None, msg=invalid)
  }
  for invalid in ["", ".org", "org..example", "org/example", "../org"] {
    assert_eq(@resources.MavenGroupId::parse(invalid), None, msg=invalid)
  }
  for invalid in ["", "../a", "a/b", "a?x"] {
    assert_eq(@resources.MavenArtifactId::parse(invalid), None)
    assert_eq(@resources.MavenClassifier::parse(invalid), None)
  }
  for
    invalid in [
      "https://user:pass@repo.test", "https://repo.test?query", "file:///repo",
    ] {
    assert_eq(@resources.RepositoryUrl::parse(invalid), None)
  }
  assert_eq(
    @resources.NpmPackageRef::from_key(npm_reference().key()),
    Some(npm_reference()),
  )
  assert_eq(
    @resources.MavenCoordinates::from_key(maven_coordinates().key()),
    Some(maven_coordinates()),
  )
  assert_eq(
    @resources.MavenCoordinates::from_key(
      maven_coordinates(classifier=Some("test")).key(),
    ),
    Some(maven_coordinates(classifier=Some("test"))),
  )
}
