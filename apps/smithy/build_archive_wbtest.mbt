///|
fn archive_test_bytes(
  manifest : String?,
  files : Map[String, String],
  deflated~ : Bool = false,
) -> Bytes raise {
  let archive = @zipc.Archive::empty()
  let files = files.copy()
  if manifest is Some(manifest) {
    files["manifest"] = manifest
  }
  for name, text in files {
    let bytes = @utf8.encode(text[:])
    let content = if deflated {
      @zipc.File::deflate_from_bytes(bytes)
    } else {
      @zipc.File::stored_from_bytes(bytes)
    }
    ignore(
      archive.add(
        @zipc.Member::make("META-INF/smithy/" + name, @zipc.File(content)),
      ),
    )
  }
  archive.to_bytes()
}

///|
test "archive models reads the upstream Java sources JAR fixture" {
  let models = build_archive_models(
    "../../tests/tck/build/plugins/sources/jar-import.jar",
  )
  let names = models.keys().to_array()
  names.sort()
  assert_eq(names, ["a.smithy", "b/b.smithy", "b/c/c.json"])
  assert_true(models["a.smithy"].contains("string A"))
  assert_true(models["b/b.smithy"].contains("string B"))
  assert_true(models["b/c/c.json"].contains("\"foo.baz#C\""))
  let loader = @smithy.Loader::new()
  for name, text in models {
    if name.has_suffix(".smithy") {
      ignore(loader.add_idl("jar-import.jar!/META-INF/smithy/" + name, text))
    } else {
      ignore(loader.add_json("jar-import.jar!/META-INF/smithy/" + name, text))
    }
  }
  let model = loader.assemble().model.unwrap()
  for id in ["foo.baz#A", "foo.baz#B", "foo.baz#C"] {
    assert_true(model.get(id) is Some(_))
  }
  let names = names.map(name => "jar-import/" + name)
  assert_eq(
    names.join("\n") + "\n",
    "jar-import/a.smithy\njar-import/b/b.smithy\njar-import/b/c/c.json\n",
  )
}

///|
test "archive discovery supports stored and deflated models and manifest line endings" {
  let text = "$version: \"2\"\nnamespace example\n@documentation(\"" +
    "long documentation ".repeat(40) +
    "\")\nstring Name\n"
  for deflated in [false, true] {
    let bytes = archive_test_bytes(
      Some("# models\r\na.smithy\rb/model.json\na.smithy\n"),
      {
        "a.smithy": text,
        "b/model.json": "{\"smithy\":\"2.0\",\"shapes\":{}}",
        "unlisted.smithy": "ignored",
      },
      deflated~,
    )
    if deflated {
      guard @zipc.Archive::from_bytes(bytes)
        .find("META-INF/smithy/a.smithy")
        .unwrap()
        .kind()
        is @zipc.File(file) else {
        fail("expected compressed model")
      }
      assert_true(file.compression() is @zipc.Deflate)
    }
    let models = @build.archive_models(bytes, "example.jar")
    assert_eq(models.length(), 2)
    assert_eq(models.get("a.smithy"), Some(text))
    assert_false(models.contains("unlisted.smithy"))
  }
}

///|
test "archives without a Smithy manifest contain no discovered models" {
  let bytes = archive_test_bytes(None, { "unlisted.smithy": "ignored" })
  assert_eq(@build.archive_models(bytes, "plain.jar").length(), 0)
}

///|
test "archive manifests reject unsafe entries missing files and unsupported model names" {
  for
    name in [
      "../outside.smithy", "nested/../outside.smithy", "/absolute.smithy", "back\\slash.smithy",
      "space name.smithy", "a//b.smithy", "./a.smithy", "a.smithy/", "a%20.smithy",
      "unknown.txt", "missing.smithy",
    ] {
    let bytes = archive_test_bytes(Some(name + "\n"), {
      "unknown.txt": "ignored",
    })
    assert_true(
      try @build.archive_models(bytes, "bad.jar") catch {
        @build.InvalidBuildConfig(message) => message.contains("bad.jar")
      } noraise {
        _ => false
      },
      msg=name,
    )
  }
}

///|
test "invalid archives fail with the origin in the error" {
  assert_true(
    try @build.archive_models(b"not a zip", "broken.jar") catch {
      @build.InvalidBuildConfig(message) => message.contains("broken.jar")
    } noraise {
      _ => false
    },
  )
}

///|
test "malformed ZIP directory offsets fail without indexing outside the archive" {
  let valid = archive_test_bytes(Some(""), Map([]))
  let bytes = Bytes::makei(valid.length(), i => {
    if i >= valid.length() - 6 && i < valid.length() - 2 {
      255
    } else {
      valid[i]
    }
  })
  assert_true(
    try @build.archive_models(bytes, "offset.jar") catch {
      @build.InvalidBuildConfig(message) => message.contains("offset.jar")
    } noraise {
      _ => false
    },
  )
}
