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
        files.keys().to_array(),
        path => files[path],
        "fixture-directory",
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
          .register_provider("fixture", (_, reference) => {
            reference,
            identity: "models@1",
            tree: @resources.EntryTree::zip(bytes, "fixture.jar"),
          })
          .add_repository({
            id: "fixtures",
            provider: "fixture",
            location: "memory",
          })
        registry.resolve({ repository: "fixtures", key: "models@1", }).tree
      } else {
        assert_eq(kind, "jar")
        @resources.EntryTree::zip(bytes, "fixture.jar")
      }
    }
    self.resources = @build.declared_models(tree)
    let loader = @smithy.Loader::new()
    for resource in self.resources {
      ignore(loader.add_idl(resource.origin, resource.text()))
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
    assert_eq(self.resources[0].name, name)
  })
  setup.then1("the resource provenance includes {string}", fn(
    chain : String,
  ) raise {
    assert_eq(self.resources[0].provenance, chain)
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
