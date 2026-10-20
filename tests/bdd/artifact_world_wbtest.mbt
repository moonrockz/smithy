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
      assert_eq(kind, "zip")
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
      @resources.EntryTree::zip(
        archive.to_bytes(),
        @resources.Location::parse("fixture.zip").unwrap(),
      )
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
