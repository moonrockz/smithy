///|
fn github_request(
  format~ : @resources.ArchiveFormat = @resources.Zip,
) -> @resources.GitHubArchive {
  {
    repository: @resources.GitHubRepository::parse("owner/models").unwrap(),
    reference: {
      tag: @resources.GitHubTag::parse("v1/é?#").unwrap(),
      asset: @resources.GitHubAssetName::parse("models.zip").unwrap(),
    },
    format,
    expected_digest: None,
  }
}

///|
fn github_asset(
  name~ : String = "models.zip",
  id~ : Int32 = 42,
  digest~ : Json = Json::null(),
) -> Json {
  {
    "id": id,
    "name": name,
    "state": "uploaded",
    "browser_download_url": "https://example.test/download",
    "digest": digest,
  }
}

///|
fn github_transport(
  body : Bytes,
  assets~ : Json = Json::array([github_asset()]),
  release~ : Json = { "id": 7, "tag_name": "v1/é?#", "draft": false },
  calls~ : Array[String] = [],
) -> @resources.HttpTransport {
  (requested, _) => {
    let text = requested.to_string()
    calls.push(text)
    let (resolved, bytes) = if text.contains("/tags/") {
      (requested.url, @utf8.encode(release.stringify()))
    } else if text.contains("/assets?") {
      (requested.url, @utf8.encode(assets.stringify()))
    } else {
      (url("https://cdn.example.test/exact.zip"), body)
    }
    { resolved, status: 200, body: bytes, }
  }
}

///|
fn github_code(
  action : () -> @resources.EntryTree raise @resources.ResourceError,
) -> @resources.ResourceCode? {
  try action() catch {
    @resources.ResourceError(code, _, _) => Some(code)
  } noraise {
    _ => None
  }
}

///|
test "GitHub provider resolves exact names with typed identity and shared offline cache" {
  let body = archive({ "models/a.txt": b"hello" })
  let calls = []
  let values = Map([])
  let cache = memory_cache(values)
  let request = github_request()
  let digest = @resources.ContentDigest::sha256(body)
  let transport = github_transport(
    body,
    assets=Json::array([
      github_asset(name="models.zip.sig"),
      github_asset(digest=Json::string(digest.to_string())),
    ]),
    calls~,
  )
  let registry = @resources.register_github(
    @resources.Registry::new(),
    transport,
    cache=Some(cache),
  ).add_repository({
    id: @resources.RepositoryId::parse("fixture").unwrap(),
    provider: @resources.ProviderId::parse("github").unwrap(),
    location: @resources.RepositoryLocation::parse("owner/models").unwrap(),
  })
  let artifact = registry.resolve({
    repository: @resources.RepositoryId::parse("fixture").unwrap(),
    key: request.reference.key(),
  })
  assert_eq(artifact.tree.text(entry("models/a.txt")), "hello")
  assert_eq(artifact.tree.digest, Some(digest))
  assert_eq(
    artifact.identity.to_string(),
    "github:owner/models tag=v1/é?# release=7 asset=models.zip id=42",
  )
  assert_eq(calls, [
    "https://api.github.com/repos/owner/models/releases/tags/v1%2F%C3%A9%3F%23",
    "https://api.github.com/repos/owner/models/releases/7/assets?per_page=100&page=1",
    "https://example.test/download",
  ])
  let offline = request.open(
    (_, _) => abort("offline transport called"),
    cache=Some(cache),
    mode=@resources.Offline,
  )
  assert_eq(offline.read(entry("models/a.txt")), b"hello")
  assert_eq(
    offline.provenance().steps(),
    artifact.tree.provenance().steps()[1:].to_owned(),
  )
  let text = offline.provenance().to_string()
  for
    part in [
      "tag=v1/é?#",
      "release=7",
      "asset=models.zip id=42",
      digest.to_string(),
      "https://example.test/download",
      "https://cdn.example.test/exact.zip",
    ] {
    assert_true(text.contains(part), msg=part)
  }
  assert_eq(calls.length(), 3)
  assert_eq(
    github_code(() => request.open(transport, mode=@resources.Offline)),
    Some(@resources.OfflineMiss),
  )
  let changed = {
    ..request,
    expected_digest: Some(@resources.ContentDigest::sha256(b"wrong")),
  }
  assert_eq(
    github_code(() => {
      changed.open(transport, cache=Some(cache), mode=@resources.Offline)
    }),
    Some(@resources.IntegrityFailure),
  )
}

///|
test "GitHub assets reuse each portable archive reader" {
  let tar = tar_record("a.txt", b"hello") + tar_end()
  for
    (format, body) in [
      (@resources.Zip, archive({ "a.txt": b"hello" })),
      (@resources.Tar, tar),
      (@resources.Tgz, @gzip.gzip_compress(tar)),
    ] {
    let request = github_request(format~)
    let tree = request.open(github_transport(body))
    assert_eq(tree.text(entry("a.txt")), "hello")
    assert_eq(tree.digest, Some(@resources.ContentDigest::sha256(body)))
  }
}

///|
test "GitHub rejects missing ambiguous malformed or mismatched metadata before downloads" {
  for
    (assets, expected) in [
      (Json::array([]), @resources.MissingAsset),
      (Json::array([github_asset(name="MODELS.zip")]), @resources.MissingAsset),
      (
        Json::array([github_asset(), github_asset(id=43)]),
        @resources.AmbiguousAsset,
      ),
      (Json::object({}), @resources.InvalidResolution),
      (Json::array([Json::object({})]), @resources.InvalidResolution),
      (
        Json::array([
          {
            "id": -1,
            "name": "models.zip",
            "state": "uploaded",
            "browser_download_url": "https://example.test/a",
          },
        ]),
        @resources.InvalidResolution,
      ),
      (
        Json::array([
          {
            "id": 1.5,
            "name": "models.zip",
            "state": "uploaded",
            "browser_download_url": "https://example.test/a",
          },
        ]),
        @resources.InvalidResolution,
      ),
      (
        Json::array([
          {
            "id": 1,
            "name": "models.zip",
            "state": "new",
            "browser_download_url": "https://example.test/a",
          },
        ]),
        @resources.InvalidResolution,
      ),
      (
        Json::array([
          {
            "id": 1,
            "name": "models.zip",
            "state": "uploaded",
            "browser_download_url": "https://user:pass@example.test/a",
          },
        ]),
        @resources.InvalidResolution,
      ),
      (
        Json::array([github_asset(digest=Json::string("bad"))]),
        @resources.InvalidResolution,
      ),
    ] {
    let calls = []
    assert_eq(
      github_code(() => {
        github_request().open(github_transport(b"unused", assets~, calls~))
      }),
      Some(expected),
    )
    assert_eq(calls.length(), 2)
  }
  let releases : Array[Json] = [
    { "id": 7, "tag_name": "other", "draft": false },
    { "id": 7, "tag_name": "v1/é?#", "draft": true },
    { "id": 0, "tag_name": "v1/é?#", "draft": false },
  ]
  for release in releases {
    let calls = []
    assert_eq(
      github_code(() => {
        github_request().open(github_transport(b"unused", release~, calls~))
      }),
      Some(@resources.InvalidResolution),
    )
    assert_eq(calls.length(), 1)
  }
}

///|
test "GitHub paginates exact selection and detects duplicates across pages" {
  for duplicate in [false, true] {
    let calls = []
    let first = Array::make(100, github_asset(name="other.zip"))
    if duplicate {
      first[0] = github_asset()
    }
    let delegate = github_transport(archive({ "a.txt": b"hello" }), calls~)
    let transport : @resources.HttpTransport = (requested, limits) => {
      if requested.to_string().contains("/assets?") {
        calls.push(requested.to_string())
        {
          resolved: requested.url,
          status: 200,
          body: @utf8.encode(
            Json::array(
              if requested.to_string().has_suffix("page=1") {
                first
              } else {
                [github_asset()]
              },
            ).stringify(),
          ),
        }
      } else {
        delegate(requested, limits)
      }
    }
    if duplicate {
      assert_eq(
        github_code(() => github_request().open(transport)),
        Some(@resources.AmbiguousAsset),
      )
    } else {
      assert_eq(github_request().open(transport).text(entry("a.txt")), "hello")
    }
    assert_true(
      calls.contains(
        "https://api.github.com/repos/owner/models/releases/7/assets?per_page=100&page=2",
      ),
    )
  }
}

///|
test "GitHub status policy distinguishes release missing auth rate limits and invalid JSON" {
  for
    (status, body, expected) in [
      (404, b"missing", @resources.MissingRelease),
      (401, b"auth", @resources.AuthenticationRequired),
      (403, b"forbidden", @resources.AuthenticationRequired),
      (
        403,
        b"{\"message\":\"API rate limit exceeded\"}",
        @resources.RateLimited,
      ),
      (429, b"slow down", @resources.RateLimited),
      (500, b"failure", @resources.HttpStatus),
      (200, b"not json", @resources.InvalidResolution),
    ] {
    let code = github_code(() => {
      github_request().open((requested, _) => {
        resolved: requested.url,
        status,
        body,
      })
    })
    assert_eq(code, Some(expected))
  }
  let request = {
    ..github_request(),
    expected_digest: Some(@resources.ContentDigest::sha256(b"wrong")),
  }
  let body = archive({ "a.txt": b"hello" })
  assert_eq(
    github_code(() => request.open(github_transport(body))),
    Some(@resources.IntegrityFailure),
  )
}

///|
test "GitHub boundaries validate coordinates and keep tag asset keys collision free" {
  for
    value in [
      "", "owner", "owner/repo/extra", "/repo", "owner/..", "owner/repo?x", "https://github.com/owner/repo",
    ] {
    assert_eq(@resources.GitHubRepository::parse(value), None)
  }
  for value in ["", ".", "..", "../a", "a/b", "a\\b", "a\n"] {
    assert_eq(@resources.GitHubAssetName::parse(value), None)
  }
  for value in ["", ".", "..", "a\n"] {
    assert_eq(@resources.GitHubTag::parse(value), None)
  }
  let request = github_request()
  assert_eq(
    @resources.GitHubAssetRef::from_key(request.reference.key()),
    Some(request.reference),
  )
  assert_eq(
    @resources.GitHubAssetRef::from_key(
      @resources.ArtifactKey::parse("v1:models.zip").unwrap(),
    ),
    None,
  )
  let calls = []
  assert_eq(
    github_code(() => {
      request.open(
        github_transport(b"unused", calls~),
        limits=@resources.Limits::new(max_archive_bytes=0),
      )
    }),
    Some(@resources.ResourceLimit),
  )
  assert_eq(calls.length(), 0)
}

///|
test "GitHub bounds metadata enumeration and rejects oversized constructed URLs" {
  let request = github_request()
  let calls = []
  let delegate = github_transport(b"unused", calls~)
  let full = @utf8.encode(
    Json::array(Array::make(100, github_asset(name="other"))).stringify(),
  )
  let transport : @resources.HttpTransport = (requested, limits) => {
    if requested.to_string().contains("/assets?") {
      calls.push(requested.to_string())
      { resolved: requested.url, status: 200, body: full, }
    } else {
      delegate(requested, limits)
    }
  }
  assert_eq(
    github_code(() => request.open(transport)),
    Some(@resources.ResourceLimit),
  )
  assert_eq(calls.length(), 11)
  assert_eq(
    github_code(() => {
      request.open(
        (requested, _) => {
          resolved: requested.url,
          status: 403,
          body: Bytes::make(65, 65),
        },
        acquisition_limits=@resources.AcquisitionLimits::new(max_bytes=64).unwrap(),
      )
    }),
    Some(@resources.ResourceLimit),
  )
  assert_eq(
    github_code(() => {
      request.open(
        delegate,
        api=url("https://example.test/" + "a".repeat(8170)),
      )
    }),
    Some(@resources.InvalidResolution),
  )
  assert_eq(
    github_code(() => {
      request.open(delegate, api=url("https://example.test?query=1"))
    }),
    Some(@resources.InvalidResolution),
  )
  assert_eq(calls.length(), 11)
}

///|
test "GitHub offline cache verifies both API metadata and archive content" {
  let body = archive({ "a.txt": b"hello" })
  for corrupt_metadata in [false, true] {
    let values = Map([])
    let cache = memory_cache(values)
    let request = github_request()
    ignore(request.open(github_transport(body), cache=Some(cache)))
    let digest = if corrupt_metadata {
      let release : Json = { "id": 7, "tag_name": "v1/é?#", "draft": false }
      @resources.ContentDigest::sha256(@utf8.encode(release.stringify()))
    } else {
      @resources.ContentDigest::sha256(body)
    }
    values[@resources.CacheKey::content(digest)] = b"corrupt"
    assert_eq(
      github_code(() => {
        request.open(
          (_, _) => abort("corrupt cache called transport"),
          cache=Some(cache),
          mode=@resources.Offline,
        )
      }),
      Some(@resources.CacheCorrupt),
    )
  }
}
