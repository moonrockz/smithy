///|
fn tar_header(
  name : String,
  size : Int32,
  kind~ : Byte = b'0',
  prefix~ : String = "",
  v7~ : Bool = false,
) -> Bytes {
  let bytes : Array[Byte] = Array::make(512, 0)
  fn put(at : Int32, text : String) {
    for i, b in @utf8.encode(text) {
      bytes[at + i] = b
    }
  }
  put(0, name)
  put(100, "0000644")
  put(108, "0000000")
  put(116, "0000000")
  let octal = size.to_string(radix=8)
  put(124, "0".repeat(11 - octal.length()) + octal)
  put(136, "00000000000")
  for i in 148..<156 {
    bytes[i] = b' '
  }
  bytes[156] = kind
  if !v7 {
    put(257, "ustar")
    put(263, "00")
    put(345, prefix)
  }
  let mut sum = 0
  for b in bytes {
    sum += b.to_int()
  }
  let checksum = sum.to_string(radix=8)
  put(148, "0".repeat(6 - checksum.length()) + checksum)
  bytes[154] = 0
  Bytes::from_array(bytes)
}

///|
fn tar_record(
  name : String,
  data : Bytes,
  kind~ : Byte = b'0',
  prefix~ : String = "",
  v7~ : Bool = false,
) -> Bytes {
  tar_header(name, data.length(), kind~, prefix~, v7~) +
  data +
  Bytes::make((512 - data.length() % 512) % 512, 0)
}

///|
fn tar_end() -> Bytes {
  Bytes::make(1024, 0)
}

///|
fn pax_record(key : String, value : String) -> Bytes {
  let content = key + "=" + value + "\n"
  let body = @utf8.encode(content)
  let mut length = body.length() + 2
  while length != body.length() + length.to_string().length() + 1 {
    length = body.length() + length.to_string().length() + 1
  }
  @utf8.encode(length.to_string() + " ") + body
}

///|
test "V7 ustar and pax preserve root-relative resources and physical origins" {
  let long = "nested/".repeat(20) + "message.txt"
  let pax = tar_record(
    "PaxHeader",
    pax_record("path", "package/" + long) + pax_record("size", "5"),
    kind=b'x',
  )
  for
    (data, path) in [
      (
        tar_record("package/message.txt", b"hello", v7=true) + tar_end(),
        "message.txt",
      ),
      (
        tar_record("message.txt", b"hello", prefix="package") + tar_end(),
        "message.txt",
      ),
      (
        pax +
        tar_header("placeholder", 0) +
        b"hello" +
        Bytes::make(507, 0) +
        tar_end(),
        long,
      ),
      (tar_record("package/雪.txt", b"hello") + tar_end(), "雪.txt"),
    ] {
    for
      tree in [
        @resources.EntryTree::tar(data, location("models.tar")),
        @resources.EntryTree::tgz(
          @gzip.gzip_compress(data),
          location("models.tgz"),
        ),
      ] {
      let selection = @resources.Selection::new(
        @resources.ResourceRoot::parse("package").unwrap(),
        [@resources.Exact(entry(path))],
      ).unwrap()
      let resources = @resources.select_resources(tree, selection)
      assert_eq(resources[0].text(), "hello")
      assert_eq(resources[0].name.to_string(), path)
      assert_eq(resources[0].path.to_string(), "package/" + path)
      assert_eq(
        resources[0].origin,
        tree.origin.archive_entry(entry("package/" + path)),
      )
      assert_eq(
        tree.digest,
        Some(
          @resources.ContentDigest::sha256(
            if tree.origin.to_string() == "models.tar" {
              data
            } else {
              @gzip.gzip_compress(data)
            },
          ),
        ),
      )
    }
  }
}

///|
fn tar_code(
  data : Bytes,
  limits~ : @resources.Limits = @resources.Limits::new(),
) -> String {
  error_code(() => {
    ignore(@resources.EntryTree::tar(data, location("bad.tar"), limits~))
  })
}

///|
fn tgz_code(
  data : Bytes,
  limits~ : @resources.Limits = @resources.Limits::new(),
) -> String {
  error_code(() => {
    ignore(@resources.EntryTree::tgz(data, location("bad.tgz"), limits~))
  })
}

///|
test "tar rejects truncation malformed headers checksums and trailing data" {
  let valid = tar_record("file", b"hello") + tar_end()
  for length in 0..<valid.length() {
    assert_eq(
      tar_code(valid[:length].to_owned()),
      "invalid-archive",
      msg=length.to_string(),
    )
  }
  assert_eq(tar_code(changed(valid, { 0: b'x' })), "integrity-failure")
  assert_eq(tar_code(valid + b"garbage"), "invalid-archive")
  assert_eq(tar_code(valid + Bytes::make(512, 0)), "none")
  // Recompute checksum to distinguish malformed numeric fields from integrity.
  let oversized = tar_header("file", 2147483647) + tar_end()
  assert_eq(tar_code(oversized), "resource-limit")
  assert_eq(
    tar_code(tar_record("folder/", b"x", kind=b'5') + tar_end()),
    "invalid-archive",
  )
}

///|
test "tar rejects unsafe paths and every unsupported entry type even when unselected" {
  for
    name in [
      "/abs", "../escape", "package/../escape", "a//b", "./file", "C:/file", "a\\b",
      "a\n", "file/",
    ] {
    assert_eq(
      tar_code(tar_record(name, b"") + tar_end()),
      "unsafe-path",
      msg=name,
    )
  }
  for kind in [b'1', b'2', b'3', b'4', b'6', b'7', b'S', b'L', b'K', b'g', b'z'] {
    assert_eq(
      tar_code(tar_record("entry", b"", kind~) + tar_end()),
      "invalid-archive",
    )
  }
  let unsafe_pax = tar_record("pax", pax_record("path", "../escape"), kind=b'x')
  assert_eq(
    tar_code(unsafe_pax + tar_record("safe", b"") + tar_end()),
    "unsafe-path",
  )
  let nul_path = tar_record("pax", pax_record("path", "file\u0000"), kind=b'x')
  assert_eq(
    tar_code(nul_path + tar_record("safe", b"") + tar_end()),
    "unsafe-path",
  )
}

///|
test "tar detects duplicates and counts directories metadata and unselected bytes against limits" {
  let file = tar_record("same", b"abc")
  assert_eq(tar_code(file + file + tar_end()), "duplicate-entry")
  assert_eq(
    tar_code(file + tar_record("same/", b"", kind=b'5') + tar_end()),
    "duplicate-entry",
  )
  let data = file + tar_record("other", b"abcd") + tar_end()
  assert_eq(
    tar_code(data, limits=@resources.Limits::new(max_entries=1)),
    "resource-limit",
  )
  assert_eq(
    tar_code(data, limits=@resources.Limits::new(max_entry_bytes=2)),
    "resource-limit",
  )
  assert_eq(
    tar_code(data, limits=@resources.Limits::new(max_total_bytes=6)),
    "resource-limit",
  )
  assert_eq(
    tar_code(data, limits=@resources.Limits::new(max_archive_bytes=1)),
    "resource-limit",
  )
  assert_eq(
    tar_code(data, limits=@resources.Limits::new(max_expanded_bytes=1)),
    "resource-limit",
  )
  assert_eq(
    tar_code(data, limits=@resources.Limits::new(max_expanded_bytes=-1)),
    "invalid-limits",
  )
  let directory = tar_record("package/", b"", kind=b'5')
  let tree = @resources.EntryTree::tar(
    directory + tar_end(),
    location("empty.tar"),
  )
  let selection = @resources.Selection::new(
    @resources.ResourceRoot::parse("package").unwrap(),
    [@resources.Matching(@resources.GlobPattern::parse("**").unwrap())],
  ).unwrap()
  assert_eq(
    error_code(() => ignore(tree.select(selection))),
    "missing-selection",
  )
  let metadata = tar_record("pax", pax_record("comment", "metadata"), kind=b'x')
  assert_eq(
    tar_code(
      metadata + file + tar_end(),
      limits=@resources.Limits::new(max_entries=1),
    ),
    "resource-limit",
  )
  assert_eq(
    tar_code(
      metadata + file + tar_end(),
      limits=@resources.Limits::new(max_entry_bytes=3),
    ),
    "resource-limit",
  )
}

///|
test "pax rejects malformed lengths unsupported semantics duplicate keys and dangling metadata" {
  for
    body in [
      b"99 path=x\n",
      b"0 path=x\n",
      b"x path=x\n",
      b"10 path=x!",
      b"12 nosplit!\n",
      pax_record("GNU.sparse.map", "0,10"),
      pax_record("linkpath", "target"),
      pax_record("path", "a") + pax_record("path", "b"),
    ] {
    let metadata = tar_record("pax", body, kind=b'x')
    assert_eq(
      tar_code(metadata + tar_record("file", b"") + tar_end()),
      "invalid-archive",
    )
  }
  let metadata = tar_record("pax", pax_record("path", "file"), kind=b'x')
  assert_eq(tar_code(metadata + tar_end()), "invalid-archive")
  assert_eq(
    tar_code(metadata + metadata + tar_record("file", b"") + tar_end()),
    "invalid-archive",
  )
  for value in ["-1", "2147483648", "", "1x"] {
    assert_eq(
      tar_code(
        tar_record("pax", pax_record("size", value), kind=b'x') +
        tar_record("file", b"") +
        tar_end(),
      ),
      "invalid-archive",
    )
  }
}

///|
test "gzip rejects every truncated prefix corrupt trailers reserved flags and trailing fragments" {
  let data = tar_record("file", b"hello") + tar_end()
  let gzip = @gzip.gzip_compress(data)
  for length in 0..<gzip.length() {
    assert_true(
      tgz_code(gzip[:length].to_owned()) != "none",
      msg=length.to_string(),
    )
  }
  for at in [gzip.length() - 8, gzip.length() - 4] {
    assert_eq(
      tgz_code(changed(gzip, Map([(at, (gzip[at].to_int() ^ 1).to_byte())]))),
      "integrity-failure",
    )
  }
  assert_eq(tgz_code(changed(gzip, { 3: 0x20 })), "invalid-archive")
  for trailing in [b"x", b"\x1f\x8b", Bytes::make(10, 0)] {
    assert_eq(tgz_code(gzip + trailing), "invalid-archive")
  }
  assert_eq(
    tgz_code(gzip, limits=@resources.Limits::new(max_archive_bytes=1)),
    "resource-limit",
  )
  assert_eq(
    tgz_code(
      gzip,
      limits=@resources.Limits::new(max_expanded_bytes=data.length() - 1),
    ),
    "resource-limit",
  )
  assert_eq(
    tgz_code(gzip, limits=@resources.Limits::new(max_entry_bytes=4)),
    "resource-limit",
  )
}

///|
test "gzip optional headers verify CRC and concatenated members share one expanded budget" {
  let data = tar_record("file", b"hello") + tar_end()
  let gzip = @gzip.gzip_compress(data)
  let header = changed(gzip[:10].to_owned(), { 3: 0x1e }) +
    b"\x02\x00abname\x00comment\x00"
  let crc = @checksum.crc32(header)
  let decorated = header +
    Bytes::from_array([(crc & 255).to_byte(), ((crc >> 8) & 255).to_byte()]) +
    gzip[10:].to_owned()
  assert_eq(tgz_code(decorated), "none")
  for length in 0..<decorated.length() {
    assert_true(tgz_code(decorated[:length].to_owned()) != "none")
  }
  assert_eq(
    tgz_code(changed(decorated, { 10: 0xff, 11: 0xff })),
    "invalid-archive",
  )
  assert_eq(tgz_code(changed(decorated, { 12: b'X' })), "integrity-failure")
  let multi = @gzip.gzip_compress(data[:700].to_owned()) +
    @gzip.gzip_compress(data[700:].to_owned())
  assert_eq(tgz_code(multi), "none")
  assert_eq(
    tgz_code(
      multi,
      limits=@resources.Limits::new(max_expanded_bytes=data.length() - 1),
    ),
    "resource-limit",
  )
}

///|
fn tar_rechecksum(data : Bytes) -> Bytes {
  let mut sum = 0
  for i in 0..<512 {
    sum += if i >= 148 && i < 156 { 32 } else { data[i].to_int() }
  }
  let octal = sum.to_string(radix=8)
  let field = @utf8.encode("0".repeat(6 - octal.length()) + octal + "\u0000 ")
  Bytes::makei(data.length(), i => {
    if i >= 148 && i < 156 {
      field[i - 148]
    } else {
      data[i]
    }
  })
}

///|
test "tar validates octal encoding variant and UTF-8 independently of checksum" {
  let valid = tar_record("file", b"hello") + tar_end()
  for
    replacements in [
      { 124: b'9' },
      { 124: 0x80 },
      { 257: b'X' },
      { 263: b'1' },
      { 0: 0xff },
      { 99: b'x' },
    ] {
    let malformed = tar_rechecksum(changed(valid, replacements))
    assert_eq(tar_code(malformed), "invalid-archive")
  }
  assert_eq(tar_code(tar_rechecksum(changed(valid, { 156: 0 }))), "none")
}

///|
test "gzip streaming output stops before allocating an entire compression bomb" {
  let data = tar_record("large", Bytes::make(65536, b'a')) + tar_end()
  let compressed = @gzip.gzip_compress(data)
  assert_eq(tgz_code(compressed), "none")
  assert_eq(
    tgz_code(compressed, limits=@resources.Limits::new(max_expanded_bytes=8192)),
    "resource-limit",
  )
  let tree = @resources.EntryTree::tgz(compressed, location("large.tgz"))
  assert_eq(tree.read(entry("large")), Bytes::make(65536, b'a'))
}
