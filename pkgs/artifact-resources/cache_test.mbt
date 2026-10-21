///|
fn memory_cache(
  values : Map[@resources.CacheKey, Bytes],
) -> @resources.VerifiedCache {
  @resources.VerifiedCache::new({
    read: (key, _) => values.get(key),
    publish: (key, bytes) => values[key] = bytes,
  })
}

///|
fn acquisition_code(
  action : () -> @resources.AcquiredBytes raise @resources.ResourceError,
) -> @resources.ResourceCode? {
  try action() catch {
    @resources.ResourceError(code, _, _) => Some(code)
  } noraise {
    _ => None
  }
}

///|
test "verified cache reuses remote identities online and offline without transport" {
  let values = Map([])
  let cache = memory_cache(values)
  let requested = url("https://example.test/archive?v=1")
  let resolved = url("https://cdn.example.test/models.zip")
  let body = archive({ "model.smithy": b"namespace example\nstring A" })
  let digest = @resources.ContentDigest::sha256(body)
  let calls = []
  let transport : @resources.HttpTransport = (seen, _) => {
    calls.push(seen.url)
    { resolved, status: 200, body, }
  }
  let request : @resources.PublicArchive = {
    url: requested,
    format: @resources.Zip,
    expected_digest: Some(digest),
  }
  let online = request.open(transport, cache=Some(cache))
  let reused = request.open(transport, cache=Some(cache))
  let offline = request.open(
    (_, _) => {
      raise @resources.ResourceError(
        @resources.TransportFailure,
        @resources.Provenance::new(url("https://unexpected.test").location()),
        "offline called transport",
      )
    },
    cache=Some(cache),
    mode=@resources.Offline,
  )
  assert_eq(calls, [requested])
  assert_eq(online.provenance(), offline.provenance())
  assert_eq(online.provenance(), reused.provenance())
  assert_eq(offline.origin, resolved.location())
  assert_eq(
    offline.read(entry("model.smithy")),
    online.read(entry("model.smithy")),
  )
  assert_eq(values.length(), 2)
}

///|
test "cache misses corruption and expected digest mismatch fail closed in both modes" {
  let values = Map([])
  let cache = memory_cache(values)
  let requested = url("https://example.test/archive")
  let body = b"verified bytes"
  let digest = @resources.ContentDigest::sha256(body)
  let transport : @resources.HttpTransport = (_, _) => {
    resolved: requested,
    status: 200,
    body,
  }
  assert_eq(
    acquisition_code(() => {
      @resources.acquire(
        requested,
        transport,
        cache=Some(cache),
        mode=@resources.Offline,
      )
    }),
    Some(@resources.OfflineMiss),
  )
  assert_eq(
    acquisition_code(() => {
      @resources.acquire(requested, transport, mode=@resources.Offline)
    }),
    Some(@resources.OfflineMiss),
  )
  let wrong = @resources.ContentDigest::sha256(b"different")
  assert_eq(
    acquisition_code(() => {
      @resources.acquire(
        requested,
        transport,
        cache=Some(cache),
        expected_digest=Some(wrong),
      )
    }),
    Some(@resources.IntegrityFailure),
  )
  assert_eq(values.length(), 0)
  ignore(@resources.acquire(requested, transport, cache=Some(cache)))
  let no_transport : @resources.HttpTransport = (_, _) => {
    raise @resources.ResourceError(
      @resources.TransportFailure,
      @resources.Provenance::new(url("https://unexpected.test").location()),
      "cache failure called transport",
    )
  }
  for mode in [@resources.Online, @resources.Offline] {
    assert_eq(
      acquisition_code(() => {
        @resources.acquire(
          requested,
          no_transport,
          cache=Some(cache),
          mode~,
          expected_digest=Some(wrong),
        )
      }),
      Some(@resources.IntegrityFailure),
    )
  }
  assert_eq(
    acquisition_code(() => {
      @resources.acquire(
        requested,
        no_transport,
        cache=Some(cache),
        mode=@resources.Offline,
        limits=@resources.AcquisitionLimits::new(max_bytes=1).unwrap(),
      )
    }),
    Some(@resources.ResourceLimit),
  )
  values[@resources.CacheKey::content(digest)] = b"damaged"
  for mode in [@resources.Online, @resources.Offline] {
    assert_eq(
      acquisition_code(() => {
        @resources.acquire(requested, no_transport, cache=Some(cache), mode~)
      }),
      Some(@resources.CacheCorrupt),
    )
  }
  values.remove(@resources.CacheKey::content(digest))
  assert_eq(
    acquisition_code(() => {
      @resources.acquire(
        requested,
        no_transport,
        cache=Some(cache),
        mode=@resources.Offline,
      )
    }),
    Some(@resources.CacheCorrupt),
  )
  let key = @resources.CacheKey::reference(
    @resources.ProviderId::parse("public-http").unwrap(),
    @resources.ArtifactKey::parse(requested.to_string()).unwrap(),
  )
  for
    invalid in [
      b"partial", b"{}", b"{\"version\":1,\"requested\":\"https://other.test/a\",\"resolved\":\"file:///tmp/a\",\"digest\":\"bad\"}",
    ] {
    values[key] = invalid
    assert_eq(
      acquisition_code(() => {
        @resources.acquire(
          requested,
          no_transport,
          cache=Some(cache),
          mode=@resources.Offline,
        )
      }),
      Some(@resources.CacheCorrupt),
    )
  }
}

///|
test "reference mappings and content are distinct and interrupted publication has no hit" {
  let values = Map([])
  let cache = memory_cache(values)
  let a = url("https://example.test/archive?v=1")
  let b = url("https://example.test/archive?v=2")
  for (requested, body) in [(a, b"one"), (b, b"two")] {
    ignore(
      @resources.acquire(
        requested,
        (_, _) => { resolved: requested, status: 200, body, },
        cache=Some(cache),
      ),
    )
  }
  for (requested, expected) in [(a, b"one"), (b, b"two")] {
    assert_eq(
      @resources.acquire(
        requested,
        (_, _) => {
          raise @resources.ResourceError(
            @resources.TransportFailure,
            @resources.Provenance::new(
              url("https://unexpected.test").location(),
            ),
            "unexpected transport",
          )
        },
        cache=Some(cache),
        mode=@resources.Offline,
      ).body,
      expected,
    )
  }
  assert_eq(values.length(), 4)
  let interrupted_values = Map([])
  let interrupted = @resources.VerifiedCache::new({
    read: (key, _) => interrupted_values.get(key),
    publish: (key, bytes) => {
      if key ==
        @resources.CacheKey::content(@resources.ContentDigest::sha256(b"one")) {
        interrupted_values[key] = bytes
      } else {
        raise @resources.ResourceError(
          @resources.CacheIo,
          @resources.Provenance::new(a.location()),
          "simulated interruption",
        )
      }
    },
  })
  assert_eq(
    acquisition_code(() => {
      @resources.acquire(
        a,
        (_, _) => { resolved: a, status: 200, body: b"one", },
        cache=Some(interrupted),
      )
    }),
    Some(@resources.CacheIo),
  )
  assert_eq(
    acquisition_code(() => {
      @resources.acquire(
        a,
        (_, _) => {
          raise @resources.ResourceError(
            @resources.TransportFailure,
            @resources.Provenance::new(
              url("https://unexpected.test").location(),
            ),
            "offline transport",
          )
        },
        cache=Some(interrupted),
        mode=@resources.Offline,
      )
    }),
    Some(@resources.OfflineMiss),
  )
  assert_true(
    @resources.CacheKey::reference(
      @resources.ProviderId::parse("a").unwrap(),
      @resources.ArtifactKey::parse("bc").unwrap(),
    ) !=
    @resources.CacheKey::reference(
      @resources.ProviderId::parse("ab").unwrap(),
      @resources.ArtifactKey::parse("c").unwrap(),
    ),
  )
}
