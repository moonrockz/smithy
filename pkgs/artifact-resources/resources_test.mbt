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
  let directory = @resources.EntryTree::directory(
    ["nested/message.txt"],
    path => files[path],
    "tree",
  )
  for
    tree in [
      directory,
      @resources.EntryTree::zip(archive(files), "package.jar"),
    ] {
    let loaded = @resources.load_resources(tree, [
      { name: "greeting", path: "nested/message.txt", },
    ])
    assert_eq(loaded[0].name, "greeting")
    assert_eq(loaded[0].path, "nested/message.txt")
    assert_eq(loaded[0].text(), "hello")
    assert_true(loaded[0].origin.contains("nested/message.txt"))
  }
}

///|
test "provider registration preserves references identity tree digest and error chain" {
  let bytes = archive({ "value": b"hello" })
  let registry = @resources.Registry::new()
    .register_provider("fixture", (repository, reference) => {
      reference,
      identity: "fixture@1",
      tree: @resources.EntryTree::zip(
        bytes,
        repository.location + "/" + reference.key,
      ),
    })
    .add_repository({ id: "fixtures", provider: "fixture", location: "memory", })
  let reference : @resources.ArtifactRef = {
    repository: "fixtures",
    key: "package@1",
  }
  let resolved = registry.resolve(reference)
  assert_eq(resolved.reference, reference)
  assert_eq(resolved.identity, "fixture@1")
  assert_true(resolved.tree.digest.unwrap().has_prefix("sha256:"))
  assert_eq(resolved.tree.read("value"), b"hello")
  let resource = @resources.load_resources(resolved.tree, [
      { name: "value", path: "value", },
    ])[0]
  assert_eq(resource.origin, "memory/package@1!/value")
  assert_eq(
    resource.provenance,
    "fixtures[package@1] -> fixture@1 -> memory/package@1!/value",
  )
  try resolved.tree.read("missing") catch {
    @resources.ResourceError(_, origin, _) =>
      assert_eq(
        origin, "fixtures[package@1] -> fixture@1 -> memory/package@1!/missing",
      )
  } noraise {
    _ => fail("expected missing entry")
  }
  let broken = @resources.Registry::new()
    .register_provider("fixture", (_, _) => {
      raise @resources.ResourceError("fixture-failed", "memory", "no bytes")
    })
    .add_repository({ id: "fixtures", provider: "fixture", location: "memory", })
  try broken.resolve(reference) catch {
    @resources.ResourceError(code, origin, _) => {
      assert_eq(code, "fixture-failed")
      assert_eq(origin, "fixtures[package@1] -> memory")
    }
  } noraise {
    _ => fail("expected provider error")
  }
}

///|
test "stable resource errors for duplicates missing entries and unsafe paths" {
  let tree = @resources.EntryTree::directory(
    ["physical"],
    _ => b"ok",
    "fixture",
  )
  let cases : Array[(Array[@resources.Declaration], String)] = [
    (
      [{ name: "a", path: "physical", }, { name: "a", path: "physical", }],
      "duplicate-resource",
    ),
    ([{ name: "a", path: "missing", }], "missing-resource"),
    ([{ name: "a", path: "../physical", }], "unsafe-path"),
    ([{ name: "../a", path: "physical", }], "unsafe-path"),
  ]
  for (declarations, expected) in cases {
    try @resources.load_resources(tree, declarations) catch {
      @resources.ResourceError(code, origin, _) => {
        assert_eq(code, expected)
        assert_true(origin.has_prefix("fixture"))
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
    let tree = @resources.EntryTree::zip(bytes, "fixture.jar")
    assert_eq(tree.text("nested/model"), text)
  }
  for bytes in [b"not ZIP", b"PK\\x03\\x04"] {
    try @resources.EntryTree::zip(bytes, "bad.jar") catch {
      @resources.ResourceError(code, origin, _) => {
        assert_eq(code, "invalid-archive")
        assert_eq(origin, "bad.jar")
      }
    } noraise {
      _ => fail("expected malformed ZIP")
    }
  }
}

///|
fn error_code(action : () -> Unit raise @resources.ResourceError) -> String {
  try action() catch {
    @resources.ResourceError(code, _, _) => code
  } noraise {
    _ => "none"
  }
}

///|
test "unsafe and duplicate physical paths cannot be hidden by a directory reader" {
  for paths in [["../bad"], ["/bad"], ["a\\b"], ["a//b"], ["a/./b"], ["a", "a"]] {
    let expected = if paths == ["a", "a"] {
      "duplicate-entry"
    } else {
      "unsafe-path"
    }
    assert_eq(
      error_code(() => {
        ignore(@resources.EntryTree::directory(paths, _ => b"", "tree"))
      }),
      expected,
    )
  }
  let paths = ["ok"]
  let tree = @resources.EntryTree::directory(paths, _ => b"yes", "tree")
  paths[0] = "../bad"
  tree.entries().clear()
  assert_eq(tree.entries(), ["ok"])
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
        ignore(@resources.EntryTree::zip(bytes, "limit.zip", limits~))
      }),
      "resource-limit",
    )
  }
  let tree = @resources.EntryTree::directory(
    ["a", "b"],
    _ => b"abc",
    "tree",
    limits=@resources.Limits::new(max_total_bytes=5),
  )
  assert_eq(
    error_code(() => {
      ignore(
        @resources.load_resources(tree, [
          { name: "a", path: "a", },
          { name: "b", path: "b", },
        ]),
      )
    }),
    "resource-limit",
  )
  assert_eq(
    error_code(() => {
      ignore(
        @resources.EntryTree::directory(
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
      ignore(@resources.EntryTree::zip(duplicate, "duplicate.jar"))
    }),
    "duplicate-entry",
  )
  let unsafe_zip = changed(
    bytes,
    Map([(offsets[0] + 46, b'/'), (offsets[0] + 47, b'x')]),
  )
  assert_eq(
    error_code(() => ignore(@resources.EntryTree::zip(unsafe_zip, "unsafe.jar"))),
    "unsafe-path",
  )
  let crc = offsets[0] + 16
  let corrupt = changed(
    bytes,
    Map([(crc, (bytes[crc].to_int() ^ 1).to_byte())]),
  )
  let tree = @resources.EntryTree::zip(corrupt, "corrupt.jar")
  let name = @utf8.decode(bytes[offsets[0] + 46:offsets[0] + 48].to_owned())
  assert_eq(error_code(() => ignore(tree.read(name))), "integrity-failure")
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
  let tree = @resources.EntryTree::zip(forged, "forged.jar")
  assert_eq(error_code(() => ignore(tree.read("model"))), "integrity-failure")
}

///|
test "UTF8 decoding is optional for binary resources" {
  let tree = @resources.EntryTree::directory(["binary"], _ => b"\xff", "tree")
  assert_eq(tree.read("binary"), b"\xff")
  assert_eq(error_code(() => ignore(tree.text("binary"))), "invalid-utf8")
}

///|
test "nested archive resources preserve physical origins and the full provider chain" {
  let inner = archive({ "data": b"nested" })
  let outer = archive({ "lib/inner.jar": inner })
  let registry = @resources.Registry::new()
    .register_provider("fixture", (_, reference) => {
      reference,
      identity: "outer@1",
      tree: @resources.EntryTree::zip(outer, "outer.jar"),
    })
    .add_repository({ id: "fixtures", provider: "fixture", location: "memory", })
  let nested = registry.resolve({ repository: "fixtures", key: "outer", }).tree.open_zip(
    "lib/inner.jar",
  )
  let resource = @resources.load_resources(nested, [
      { name: "data", path: "data", },
    ])[0]
  assert_eq(resource.text(), "nested")
  assert_eq(resource.origin, "outer.jar!/lib/inner.jar!/data")
  assert_eq(
    resource.provenance,
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
        ignore(@resources.EntryTree::zip(prefix, "truncated.jar"))
      }),
      "invalid-archive",
    )
  }
}

///|
test "registry rejects missing duplicate and mismatched registrations" {
  let registry = @resources.Registry::new()
  let reference : @resources.ArtifactRef = { repository: "repo", key: "key", }
  assert_eq(
    error_code(() => ignore(registry.resolve(reference))),
    "unknown-repository",
  )
  ignore(
    registry.add_repository({
      id: "repo",
      provider: "fixture",
      location: "memory",
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
          id: "repo",
          provider: "other",
          location: "memory",
        }),
      )
    }),
    "duplicate-repository",
  )
  let tree = @resources.EntryTree::directory([], _ => b"", "memory")
  ignore(
    registry.register_provider("fixture", (_, _) => {
      reference: { repository: "repo", key: "other", },
      identity: "other",
      tree,
    }),
  )
  assert_eq(
    error_code(() => ignore(registry.resolve(reference))),
    "invalid-resolution",
  )
  assert_eq(
    error_code(() => {
      ignore(
        registry.register_provider("fixture", (_, reference) => {
          reference,
          identity: "key",
          tree,
        }),
      )
    }),
    "duplicate-provider",
  )
}

///|
test "text preserves acquisition limit missing and integrity errors" {
  let missing = @resources.EntryTree::directory([], _ => b"", "tree")
  assert_eq(
    error_code(() => ignore(missing.text("missing"))),
    "missing-resource",
  )
  let unreadable = @resources.EntryTree::directory(
    ["file"],
    _ => raise @resources.ResourceError("local-io", "tree/file", "unreadable"),
    "tree",
  )
  assert_eq(error_code(() => ignore(unreadable.text("file"))), "local-io")
  let limited = @resources.EntryTree::directory(
    ["file"],
    _ => b"abc",
    "tree",
    limits=@resources.Limits::new(max_entry_bytes=1),
  )
  assert_eq(error_code(() => ignore(limited.text("file"))), "resource-limit")
  let bytes = archive({ "file": b"hello" })
  let at = central_offsets(bytes)[0] + 16
  let corrupt = changed(bytes, Map([(at, (bytes[at].to_int() ^ 1).to_byte())]))
  let tree = @resources.EntryTree::zip(corrupt, "corrupt.jar")
  assert_eq(error_code(() => ignore(tree.text("file"))), "integrity-failure")
}

///|
test "hosts preserve physical filenames independently of logical separators" {
  let tree = @resources.EntryTree::directory(
    ["nested/file.txt"],
    _ => b"hello",
    "C:\\models",
    entry_origin=Some(path => {
      "C:\\models\\" + path.replace_all(old="/", new="\\")
    }),
  )
  let loaded = @resources.load_resources(tree, [
    { name: "greeting", path: "nested/file.txt", },
  ])
  assert_eq(loaded[0].name, "greeting")
  assert_eq(loaded[0].path, "nested/file.txt")
  assert_eq(loaded[0].origin, "C:\\models\\nested\\file.txt")
  assert_eq(loaded[0].provenance, "C:\\models\\nested\\file.txt")
}
