///|
fn entry(text : String) -> @resources.EntryPath {
  @resources.EntryPath::parse(text).unwrap()
}

///|
fn logical(text : String) -> @resources.ResourceName {
  @resources.ResourceName::parse(text).unwrap()
}

///|
fn location(text : String) -> @resources.Location {
  @resources.Location::parse(text).unwrap()
}

///|
fn directory(
  paths : Array[String],
  read : (String) -> Bytes raise @resources.ResourceError,
  origin : String,
  limits~ : @resources.Limits = @resources.Limits::new(),
) -> @resources.EntryTree raise @resources.ResourceError {
  @resources.EntryTree::directory(
    paths.map(entry),
    path => read(path.to_string()),
    location(origin),
    limits~,
  )
}

///|
fn archive(files : Map[String, Bytes], deflated~ : Bool = false) -> Bytes raise {
  let archive = @zipc.Archive::empty()
  for path, bytes in files {
    let file = if deflated {
      @zipc.File::deflate_from_bytes(bytes)
    } else {
      @zipc.File::stored_from_bytes(bytes)
    }
    ignore(archive.add(@zipc.Member::make(path, @zipc.File(file))))
  }
  archive.to_bytes()
}

///|
test "independent directory and ZIP consumers load equivalent logical resources" {
  let files = { "nested/message.txt": b"hello" }
  let directory = directory(["nested/message.txt"], path => files[path], "tree")
  for
    tree in [
      directory,
      @resources.EntryTree::zip(archive(files), location("package.jar")),
    ] {
    let loaded = @resources.load_resources(tree, [
      { name: logical("greeting"), path: entry("nested/message.txt"), },
    ])
    assert_eq(loaded[0].name.to_string(), "greeting")
    assert_eq(loaded[0].path.to_string(), "nested/message.txt")
    assert_eq(loaded[0].text(), "hello")
    assert_true(loaded[0].origin.to_string().contains("nested/message.txt"))
  }
}

///|
test "provider registration preserves references identity tree digest and error chain" {
  let bytes = archive({ "value": b"hello" })
  let registry = @resources.Registry::new()
    .register_provider(@resources.ProviderId::parse("fixture").unwrap(), (
      repository,
      reference,
    ) => {
      reference,
      identity: @resources.ArtifactIdentity::parse("fixture@1").unwrap(),
      tree: @resources.EntryTree::zip(
        bytes,
        location(
          repository.location.to_string() + "/" + reference.key.to_string(),
        ),
      ),
    })
    .add_repository({
      id: @resources.RepositoryId::parse("fixtures").unwrap(),
      provider: @resources.ProviderId::parse("fixture").unwrap(),
      location: @resources.RepositoryLocation::parse("memory").unwrap(),
    })
  let reference : @resources.ArtifactRef = {
    repository: @resources.RepositoryId::parse("fixtures").unwrap(),
    key: @resources.ArtifactKey::parse("package@1").unwrap(),
  }
  let resolved = registry.resolve(reference)
  assert_eq(resolved.reference, reference)
  assert_eq(resolved.identity.to_string(), "fixture@1")
  assert_true(resolved.tree.digest.unwrap().to_string().has_prefix("sha256:"))
  assert_eq(resolved.tree.read(entry("value")), b"hello")
  let resource = @resources.load_resources(resolved.tree, [
      { name: logical("value"), path: entry("value"), },
    ])[0]
  assert_eq(resource.origin.to_string(), "memory/package@1!/value")
  assert_eq(
    resource.provenance.to_string(),
    "fixtures[package@1] -> fixture@1 -> memory/package@1!/value",
  )
  try resolved.tree.read(entry("missing")) catch {
    @resources.ResourceError(_, origin, _) =>
      assert_eq(
        origin.to_string(),
        "fixtures[package@1] -> fixture@1 -> memory/package@1!/missing",
      )
  } noraise {
    _ => fail("expected missing entry")
  }
  let broken = @resources.Registry::new()
    .register_provider(@resources.ProviderId::parse("fixture").unwrap(), (_, _) => {
      raise @resources.ResourceError(
        @resources.ProviderFailure,
        @resources.Provenance::new(location("memory")),
        "no bytes",
      )
    })
    .add_repository({
      id: @resources.RepositoryId::parse("fixtures").unwrap(),
      provider: @resources.ProviderId::parse("fixture").unwrap(),
      location: @resources.RepositoryLocation::parse("memory").unwrap(),
    })
  try broken.resolve(reference) catch {
    @resources.ResourceError(code, origin, _) => {
      assert_eq(code.to_string(), "provider-failure")
      assert_eq(origin.to_string(), "fixtures[package@1] -> memory")
    }
  } noraise {
    _ => fail("expected provider error")
  }
}

///|
test "stable resource errors for duplicates missing entries and unsafe paths" {
  let tree = directory(["physical"], _ => b"ok", "fixture")
  let cases : Array[(Array[@resources.Declaration], String)] = [
    (
      [
        { name: logical("a"), path: entry("physical"), },
        { name: logical("a"), path: entry("physical"), },
      ],
      "duplicate-resource",
    ),
    ([{ name: logical("a"), path: entry("missing"), }], "missing-resource"),
  ]
  for (declarations, expected) in cases {
    try @resources.load_resources(tree, declarations) catch {
      @resources.ResourceError(code, origin, _) => {
        assert_eq(code.to_string(), expected)
        assert_true(origin.to_string().has_prefix("fixture"))
      }
    } noraise {
      _ => fail("expected " + expected)
    }
  }
}

///|
test "ZIP stored and bounded deflate readers verify content and reject malformed inputs" {
  let text = "repeated text ".repeat(2000)
  for deflated in [false, true] {
    let bytes = archive({ "nested/model": @utf8.encode(text) }, deflated~)
    let tree = @resources.EntryTree::zip(bytes, location("fixture.jar"))
    assert_eq(tree.text(entry("nested/model")), text)
  }
  for bytes in [b"not ZIP", b"PK\\x03\\x04"] {
    try @resources.EntryTree::zip(bytes, location("bad.jar")) catch {
      @resources.ResourceError(code, origin, _) => {
        assert_eq(code.to_string(), "invalid-archive")
        assert_eq(origin.to_string(), "bad.jar")
      }
    } noraise {
      _ => fail("expected malformed ZIP")
    }
  }
}

///|
fn error_code(action : () -> Unit raise @resources.ResourceError) -> String {
  try action() catch {
    @resources.ResourceError(code, _, _) => code.to_string()
  } noraise {
    _ => "none"
  }
}

///|
test "unsafe physical paths cannot enter a directory tree" {
  for text in ["../bad", "/bad", "a\\b", "a//b", "a/./b"] {
    assert_true(@resources.EntryPath::parse(text) is None)
  }
  assert_eq(
    error_code(() => ignore(directory(["a", "a"], _ => b"", "tree"))),
    "duplicate-entry",
  )
  let paths = ["ok"]
  let tree = directory(paths, _ => b"yes", "tree")
  paths[0] = "../bad"
  tree.entries().clear()
  assert_eq(tree.entries(), [entry("ok")])
}

///|
test "limits apply before ZIP expansion and to selected directory resources" {
  let bytes = archive({ "a": b"abc", "b": b"de" })
  for
    limits in [
      @resources.Limits::new(max_archive_bytes=10),
      @resources.Limits::new(max_entries=1),
      @resources.Limits::new(max_entry_bytes=2),
      @resources.Limits::new(max_total_bytes=4),
    ] {
    assert_eq(
      error_code(() => {
        ignore(@resources.EntryTree::zip(bytes, location("limit.zip"), limits~))
      }),
      "resource-limit",
    )
  }
  let tree = directory(
    ["a", "b"],
    _ => b"abc",
    "tree",
    limits=@resources.Limits::new(max_total_bytes=5),
  )
  assert_eq(
    error_code(() => {
      ignore(
        @resources.load_resources(tree, [
          { name: logical("a"), path: entry("a"), },
          { name: logical("b"), path: entry("b"), },
        ]),
      )
    }),
    "resource-limit",
  )
  assert_eq(
    error_code(() => {
      ignore(
        directory(
          [],
          _ => b"",
          "tree",
          limits=@resources.Limits::new(max_entry_bytes=-1),
        ),
      )
    }),
    "invalid-limits",
  )
}

///|
fn central_offsets(bytes : Bytes) -> Array[Int32] {
  let offsets = []
  for i in 0..<(bytes.length() - 3) {
    if bytes[i] == 0x50 &&
      bytes[i + 1] == 0x4b &&
      bytes[i + 2] == 1 &&
      bytes[i + 3] == 2 {
      offsets.push(i)
    }
  }
  offsets
}

///|
fn changed(bytes : Bytes, replacements : Map[Int32, Byte]) -> Bytes {
  Bytes::makei(bytes.length(), i => replacements.get(i).unwrap_or(bytes[i]))
}

///|
test "ZIP duplicate names unsafe names and bad CRC have stable diagnostics" {
  let bytes = archive({ "aa": b"hello", "bb": b"world" })
  let offsets = central_offsets(bytes)
  let duplicate = changed(
    bytes,
    Map([
      (offsets[1] + 46, bytes[offsets[0] + 46]),
      (offsets[1] + 47, bytes[offsets[0] + 47]),
    ]),
  )
  assert_eq(
    error_code(() => {
      ignore(@resources.EntryTree::zip(duplicate, location("duplicate.jar")))
    }),
    "duplicate-entry",
  )
  let unsafe_zip = changed(
    bytes,
    Map([(offsets[0] + 46, b'/'), (offsets[0] + 47, b'x')]),
  )
  assert_eq(
    error_code(() => {
      ignore(@resources.EntryTree::zip(unsafe_zip, location("unsafe.jar")))
    }),
    "unsafe-path",
  )
  let crc = offsets[0] + 16
  let corrupt = changed(
    bytes,
    Map([(crc, (bytes[crc].to_int() ^ 1).to_byte())]),
  )
  let tree = @resources.EntryTree::zip(corrupt, location("corrupt.jar"))
  let name = @utf8.decode(bytes[offsets[0] + 46:offsets[0] + 48].to_owned())
  assert_eq(
    error_code(() => ignore(tree.read(entry(name)))),
    "integrity-failure",
  )
}

///|
test "deflated content cannot exceed a forged declared size" {
  let bytes = archive(
    { "model": @utf8.encode("long documentation ".repeat(3000)) },
    deflated=true,
  )
  let at = central_offsets(bytes)[0]
  let forged = changed(
    bytes,
    Map([
      (at + 24, b'\x01'),
      (at + 25, b'\x00'),
      (at + 26, b'\x00'),
      (at + 27, b'\x00'),
    ]),
  )
  let tree = @resources.EntryTree::zip(forged, location("forged.jar"))
  assert_eq(
    error_code(() => ignore(tree.read(entry("model")))),
    "integrity-failure",
  )
}

///|
test "UTF8 decoding is optional for binary resources" {
  let tree = directory(["binary"], _ => b"\xff", "tree")
  assert_eq(tree.read(entry("binary")), b"\xff")
  assert_eq(
    error_code(() => ignore(tree.text(entry("binary")))),
    "invalid-utf8",
  )
}

///|
test "nested archive resources preserve physical origins and the full provider chain" {
  let inner = archive({ "data": b"nested" })
  let outer = archive({ "lib/inner.jar": inner })
  let registry = @resources.Registry::new()
    .register_provider(@resources.ProviderId::parse("fixture").unwrap(), (
      _,
      reference,
    ) => {
      reference,
      identity: @resources.ArtifactIdentity::parse("outer@1").unwrap(),
      tree: @resources.EntryTree::zip(outer, location("outer.jar")),
    })
    .add_repository({
      id: @resources.RepositoryId::parse("fixtures").unwrap(),
      provider: @resources.ProviderId::parse("fixture").unwrap(),
      location: @resources.RepositoryLocation::parse("memory").unwrap(),
    })
  let nested = registry.resolve({
    repository: @resources.RepositoryId::parse("fixtures").unwrap(),
    key: @resources.ArtifactKey::parse("outer").unwrap(),
  }).tree.open_zip(entry("lib/inner.jar"))
  let resource = @resources.load_resources(nested, [
      { name: logical("data"), path: entry("data"), },
    ])[0]
  assert_eq(resource.text(), "nested")
  assert_eq(resource.origin.to_string(), "outer.jar!/lib/inner.jar!/data")
  assert_eq(
    resource.provenance.to_string(),
    "fixtures[outer] -> outer@1 -> outer.jar!/lib/inner.jar!/data",
  )
}

///|
test "all truncated prefixes of a valid ZIP fail without a panic" {
  let bytes = archive({ "data": b"content" })
  for length in 0..<bytes.length() {
    let prefix = bytes[:length].to_owned()
    assert_eq(
      error_code(() => {
        ignore(@resources.EntryTree::zip(prefix, location("truncated.jar")))
      }),
      "invalid-archive",
    )
  }
}

///|
test "registry rejects missing duplicate and mismatched registrations" {
  let registry = @resources.Registry::new()
  let reference : @resources.ArtifactRef = {
    repository: @resources.RepositoryId::parse("repo").unwrap(),
    key: @resources.ArtifactKey::parse("key").unwrap(),
  }
  assert_eq(
    error_code(() => ignore(registry.resolve(reference))),
    "unknown-repository",
  )
  ignore(
    registry.add_repository({
      id: @resources.RepositoryId::parse("repo").unwrap(),
      provider: @resources.ProviderId::parse("fixture").unwrap(),
      location: @resources.RepositoryLocation::parse("memory").unwrap(),
    }),
  )
  assert_eq(
    error_code(() => ignore(registry.resolve(reference))),
    "unknown-provider",
  )
  assert_eq(
    error_code(() => {
      ignore(
        registry.add_repository({
          id: @resources.RepositoryId::parse("repo").unwrap(),
          provider: @resources.ProviderId::parse("other").unwrap(),
          location: @resources.RepositoryLocation::parse("memory").unwrap(),
        }),
      )
    }),
    "duplicate-repository",
  )
  let tree = directory([], _ => b"", "memory")
  ignore(
    registry.register_provider(
      @resources.ProviderId::parse("fixture").unwrap(),
      (_, _) => {
        reference: {
          repository: @resources.RepositoryId::parse("repo").unwrap(),
          key: @resources.ArtifactKey::parse("other").unwrap(),
        },
        identity: @resources.ArtifactIdentity::parse("other").unwrap(),
        tree,
      },
    ),
  )
  assert_eq(
    error_code(() => ignore(registry.resolve(reference))),
    "invalid-resolution",
  )
  assert_eq(
    error_code(() => {
      ignore(
        registry.register_provider(
          @resources.ProviderId::parse("fixture").unwrap(),
          (_, reference) => {
            reference,
            identity: @resources.ArtifactIdentity::parse("key").unwrap(),
            tree,
          },
        ),
      )
    }),
    "duplicate-provider",
  )
}

///|
test "text preserves acquisition limit missing and integrity errors" {
  let missing = directory([], _ => b"", "tree")
  assert_eq(
    error_code(() => ignore(missing.text(entry("missing")))),
    "missing-resource",
  )
  let unreadable = directory(
    ["file"],
    _ => {
      raise @resources.ResourceError(
        @resources.LocalIo,
        @resources.Provenance::new(location("tree/file")),
        "unreadable",
      )
    },
    "tree",
  )
  assert_eq(
    error_code(() => ignore(unreadable.text(entry("file")))),
    "local-io",
  )
  let limited = directory(
    ["file"],
    _ => b"abc",
    "tree",
    limits=@resources.Limits::new(max_entry_bytes=1),
  )
  assert_eq(
    error_code(() => ignore(limited.text(entry("file")))),
    "resource-limit",
  )
  let bytes = archive({ "file": b"hello" })
  let at = central_offsets(bytes)[0] + 16
  let corrupt = changed(bytes, Map([(at, (bytes[at].to_int() ^ 1).to_byte())]))
  let tree = @resources.EntryTree::zip(corrupt, location("corrupt.jar"))
  assert_eq(
    error_code(() => ignore(tree.text(entry("file")))),
    "integrity-failure",
  )
}

///|
test "hosts preserve physical filenames independently of logical separators" {
  let tree = @resources.EntryTree::directory(
    [entry("nested/file.txt")],
    _ => b"hello",
    location("C:\\models"),
    style=@resources.Backslash,
  )
  let loaded = @resources.load_resources(tree, [
    { name: logical("greeting"), path: entry("nested/file.txt"), },
  ])
  assert_eq(loaded[0].name.to_string(), "greeting")
  assert_eq(loaded[0].path.to_string(), "nested/file.txt")
  assert_eq(loaded[0].origin.to_string(), "C:\\models\\nested\\file.txt")
  assert_eq(loaded[0].provenance.to_string(), "C:\\models\\nested\\file.txt")
}
