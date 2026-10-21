///|
struct ArtifactWorld {
  mut text : String
  mut resources : Array[@resources.Resource]
  mut model : @smithy.Model?
}

///|
fn ArtifactWorld::new() -> ArtifactWorld {
  { text: "", resources: [], model: None, }
}

///|
impl @moonspec.World for ArtifactWorld with fn configure(self, setup) {
  setup.when0("I load the local npm model package without installation", fn() raise {
    let tree = @local_resources.open(
      @resources.RepositoryLocation::parse(
        "../examples/npm-archive/smithy-local-models-1.0.0.tgz",
      ).unwrap(),
    )
    let selection = @resources.Selection::new(
      @resources.ResourceRoot::parse("package").unwrap(),
      [
        @resources.Named(
          @resources.EntryPath::parse("models/service.smithy").unwrap(),
          @resources.ResourceName::parse("service.smithy").unwrap(),
        ),
        @resources.Exact(
          @resources.EntryPath::parse("imports/shared.smithy").unwrap(),
        ),
      ],
    ).unwrap()
    self.resources = @build.selected_models(tree, selection)
    let loader = @smithy.Loader::new()
    for resource in self.resources {
      ignore(loader.add_idl(resource.origin.to_string(), resource.text()))
    }
    let loaded = loader.assemble()
    assert_false(loaded.has_errors())
    self.model = loaded.model
  })
  setup.when0("I resolve the pinned npm model package offline", fn() raise {
    let bytes = @xfs.read_file_to_bytes(
      "../examples/npm-archive/smithy-local-models-1.0.0.tgz",
    )
    let request : @resources.NpmArchive = {
      registry: @resources.RepositoryUrl::parse("https://registry.fixture.test").unwrap(),
      reference: {
        name: @resources.NpmPackageName::parse("@fixture/models").unwrap(),
        version: @resources.NpmVersion::parse("1.0.0").unwrap(),
      },
      expected_digest: Some(@resources.ContentDigest::sha256(bytes)),
    }
    let values : Map[@resources.CacheKey, Bytes] = Map([])
    let cache = @resources.VerifiedCache::new({
      read: (key, _) => values.get(key),
      publish: (key, data) => values[key] = data,
    })
    let online = request.open(
      (url, _) => {
        let metadata : Json = {
          "name": "@fixture/models",
          "version": "1.0.0",
          "dist": {
            "tarball": "https://cdn.fixture.test/models.tgz",
            "shasum": @crypto.bytes_to_hex_string(@crypto.sha1(bytes)),
          },
        }
        {
          resolved: url,
          status: 200,
          body: if url.to_string().contains("registry.fixture.test") {
            @utf8.encode(metadata.stringify())
          } else {
            bytes
          },
        }
      },
      cache=Some(cache),
    )
    let offline = request.open(
      (_, _) => abort("offline npm called transport"),
      cache=Some(cache),
      mode=@resources.Offline,
    )
    assert_eq(online.provenance(), offline.provenance())
    self.resources = @build.selected_models(
      offline,
      @resources.Selection::new(
        @resources.ResourceRoot::parse("package").unwrap(),
        [
          @resources.Exact(
            @resources.EntryPath::parse("models/service.smithy").unwrap(),
          ),
          @resources.Exact(
            @resources.EntryPath::parse("imports/shared.smithy").unwrap(),
          ),
        ],
      ).unwrap(),
    )
    let loader = @smithy.Loader::new()
    for resource in self.resources {
      ignore(loader.add_idl(resource.origin.to_string(), resource.text()))
    }
    let assembled = loader.assemble()
    assert_false(assembled.has_errors())
    self.model = assembled.model
  })
  setup.when0("I resolve the pinned Maven JAR offline", fn() raise {
    let archive = @zipc.Archive::empty()
    for
      (path, text) in [
        ("META-INF/smithy/manifest", "nested/message.smithy\n"),
        ("META-INF/smithy/nested/message.smithy", self.text),
        (
          "META-INF/smithy/unlisted.smithy", "$version: \"2\"\nnamespace example.resources\nstring Unlisted",
        ),
      ] {
      ignore(
        archive.add(
          @zipc.Member::make(
            path,
            @zipc.File(@zipc.File::stored_from_bytes(@utf8.encode(text))),
          ),
        ),
      )
    }
    let bytes = archive.to_bytes()
    let request : @resources.MavenArchive = {
      repository: @resources.RepositoryUrl::parse(
        "https://repo.fixture.test/maven",
      ).unwrap(),
      coordinates: {
        group: @resources.MavenGroupId::parse("org.example").unwrap(),
        artifact: @resources.MavenArtifactId::parse("models").unwrap(),
        version: @resources.MavenVersion::parse("1.0.0").unwrap(),
        classifier: None,
      },
      checksum: @resources.Sha1Sidecar,
      expected_digest: Some(@resources.ContentDigest::sha256(bytes)),
    }
    let values : Map[@resources.CacheKey, Bytes] = Map([])
    let cache = @resources.VerifiedCache::new({
      read: (key, _) => values.get(key),
      publish: (key, data) => values[key] = data,
    })
    let online = request.open(
      (url, _) => { resolved: url, status: 200, body: bytes, },
      cache=Some(cache),
    )
    let offline = request.open(
      (_, _) => abort("offline Maven called transport"),
      cache=Some(cache),
      mode=@resources.Offline,
    )
    assert_eq(online.provenance(), offline.provenance())
    self.resources = @build.declared_models(offline)
    let loader = @smithy.Loader::new()
    for resource in self.resources {
      ignore(loader.add_idl(resource.origin.to_string(), resource.text()))
    }
    let assembled = loader.assemble()
    assert_false(assembled.has_errors())
    self.model = assembled.model
  })
  setup.given1("the declared artifact model:", fn(doc : @moonspec.DocString) {
    self.text = doc.content
  })
  setup.when1("I discover Smithy resources from a {string} container", fn(
    kind : String,
  ) raise {
    let files = {
      "META-INF/smithy/manifest": @utf8.encode(
        "# declared models\r\nnested/message.smithy\rnested/message.smithy\n",
      ),
      "META-INF/smithy/nested/message.smithy": @utf8.encode(self.text),
      "META-INF/smithy/unlisted.smithy": @utf8.encode(
        "$version: \"2\"\nnamespace example.resources\nstring Unlisted",
      ),
    }
    let tree = if kind == "directory" {
      @resources.EntryTree::directory(
        files
        .keys()
        .map(path => @resources.EntryPath::parse(path).unwrap())
        .to_array(),
        path => files[path.to_string()],
        @resources.Location::parse("fixture-directory").unwrap(),
      )
    } else {
      let zip = @zipc.Archive::empty()
      for path, bytes in files {
        ignore(
          zip.add(
            @zipc.Member::make(
              path,
              @zipc.File(@zipc.File::deflate_from_bytes(bytes)),
            ),
          ),
        )
      }
      let bytes = zip.to_bytes()
      if kind == "provider" {
        let registry = @resources.Registry::new()
          .register_provider(@resources.ProviderId::parse("fixture").unwrap(), (
            _,
            reference,
          ) => {
            reference,
            identity: @resources.ArtifactIdentity::parse("models@1").unwrap(),
            tree: @resources.EntryTree::zip(
              bytes,
              @resources.Location::parse("fixture.jar").unwrap(),
            ),
          })
          .add_repository({
            id: @resources.RepositoryId::parse("fixtures").unwrap(),
            provider: @resources.ProviderId::parse("fixture").unwrap(),
            location: @resources.RepositoryLocation::parse("memory").unwrap(),
          })
        registry.resolve({
          repository: @resources.RepositoryId::parse("fixtures").unwrap(),
          key: @resources.ArtifactKey::parse("models@1").unwrap(),
        }).tree
      } else {
        assert_eq(kind, "jar")
        @resources.EntryTree::zip(
          bytes,
          @resources.Location::parse("fixture.jar").unwrap(),
        )
      }
    }
    self.resources = @build.declared_models(tree)
    let loader = @smithy.Loader::new()
    for resource in self.resources {
      ignore(loader.add_idl(resource.origin.to_string(), resource.text()))
    }
    let loaded = loader.assemble()
    assert_false(loaded.has_errors())
    self.model = loaded.model
  })
  setup.when1("I explicitly select resources from a {string} source tree", fn(
    kind : String,
  ) raise {
    let files = {
      "module/models/nested/message.smithy": @utf8.encode(self.text),
      "module/unlisted.smithy": @utf8.encode(
        "$version: \"2\"\nnamespace example.resources\nstring Unlisted",
      ),
      "module/main.mbt": b"source code is never executed",
    }
    let tree = if kind == "directory" {
      @resources.EntryTree::directory(
        files
        .keys()
        .map(path => @resources.EntryPath::parse(path).unwrap())
        .to_array(),
        path => files[path.to_string()],
        @resources.Location::parse("fixture-directory").unwrap(),
      )
    } else {
      assert_true(kind == "zip" || kind == "github")
      let archive = @zipc.Archive::empty()
      for path, bytes in files {
        ignore(
          archive.add(
            @zipc.Member::make(
              path,
              @zipc.File(@zipc.File::deflate_from_bytes(bytes)),
            ),
          ),
        )
      }
      let bytes = archive.to_bytes()
      if kind == "github" {
        let request : @resources.GitHubArchive = {
          repository: @resources.GitHubRepository::parse("owner/models").unwrap(),
          reference: {
            tag: @resources.GitHubTag::parse("v1").unwrap(),
            asset: @resources.GitHubAssetName::parse("models.zip").unwrap(),
          },
          format: @resources.Zip,
          expected_digest: Some(@resources.ContentDigest::sha256(bytes)),
        }
        let values : Map[@resources.CacheKey, Bytes] = Map([])
        let cache = @resources.VerifiedCache::new({
          read: (key, _) => values.get(key),
          publish: (key, data) => values[key] = data,
        })
        let online = request.open(
          (url, _) => {
            let body = if url.to_string().contains("/tags/") {
              b"{\"id\":7,\"tag_name\":\"v1\",\"draft\":false}"
            } else if url.to_string().contains("/assets?") {
              b"[{\"id\":42,\"name\":\"models.zip\",\"state\":\"uploaded\",\"browser_download_url\":\"https://cdn.fixture.test/models.zip\"}]"
            } else {
              bytes
            }
            { resolved: url, status: 200, body, }
          },
          cache=Some(cache),
        )
        let offline = request.open(
          (_, _) => abort("offline acquisition attempted transport"),
          cache=Some(cache),
          mode=@resources.Offline,
        )
        assert_eq(online.provenance(), offline.provenance())
        offline
      } else {
        @resources.EntryTree::zip(
          bytes,
          @resources.Location::parse("fixture.zip").unwrap(),
        )
      }
    }
    let selection = @resources.Selection::new(
      @resources.ResourceRoot::parse("module/models").unwrap(),
      [
        @resources.Matching(
          @resources.GlobPattern::parse("**/*.smithy").unwrap(),
        ),
      ],
    ).unwrap()
    self.resources = @build.selected_models(tree, selection)
    let loader = @smithy.Loader::new()
    for resource in self.resources {
      ignore(loader.add_idl(resource.origin.to_string(), resource.text()))
    }
    let loaded = loader.assemble()
    assert_false(loaded.has_errors())
    self.model = loaded.model
  })
  setup.then1("the artifact model contains {string}", fn(id : String) raise {
    assert_true(self.model.unwrap().get(id) is Some(_))
  })
  setup.then1("the artifact model excludes {string}", fn(id : String) raise {
    assert_true(self.model.unwrap().get(id) is None)
  })
  setup.then1("the artifact model source is {string}", fn(
    origin : String,
  ) raise {
    assert_eq(
      self.model.unwrap().get("example.resources#Message").unwrap().source.file,
      origin,
    )
  })
  setup.then1("the resource logical name is {string}", fn(name : String) raise {
    assert_eq(self.resources.length(), 1)
    assert_eq(self.resources[0].name.to_string(), name)
  })
  setup.then1("the resource provenance includes {string}", fn(
    chain : String,
  ) raise {
    assert_eq(self.resources[0].provenance.to_string(), chain)
  })
}

///|
async test "artifact resources feature" {
  @moonspec.run_or_fail(
    ArtifactWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/artifact_resources.feature"),
    ]),
  )
  |> ignore
}
