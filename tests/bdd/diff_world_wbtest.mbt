///|
struct DiffWorld {
  mut old_model : @smithy.Model?
  mut new_model : @smithy.Model?
  mut result : @diff.Result?
}

///|
fn DiffWorld::new() -> DiffWorld {
  { old_model: None, new_model: None, result: None, }
}

///|
fn diff_model(name : String) -> @smithy.Model raise {
  let result = @smithy.Loader::new()
    .add_idl(name, @xfs.read_file_to_string("tck/diff/" + name))
    .assemble()
  guard result.model is Some(model) else { fail("Could not load " + name) }
  model
}

///|
impl @moonspec.World for DiffWorld with fn configure(self, setup) {
  setup.given1("the old diff model {string}", fn(name : String) raise {
    self.old_model = Some(diff_model(name))
  })
  setup.given1("the new diff model {string}", fn(name : String) raise {
    self.new_model = Some(diff_model(name))
  })
  setup.when0("I compare the models", fn() {
    self.result = Some(
      @diff.compare(self.old_model.unwrap(), self.new_model.unwrap()),
    )
  })
  setup.then3("the diff contains {string} on {string} at severity {string}", fn(
    id : String,
    shape : String,
    severity : String,
  ) raise {
    assert_true(
      self.result.unwrap().events
      .iter()
      .any(e => {
        e.id == id &&
        e.shape.map(s => s.to_string()) == Some(shape) &&
        e.severity == severity
      }),
    )
  })
  setup.then0("the diff is breaking", fn() raise {
    assert_true(self.result.unwrap().is_breaking())
  })
  setup.then0("the diff is empty", fn() raise {
    assert_true(self.result.unwrap().events.is_empty())
  })
}

///|
async test "Model diff feature" {
  @moonspec.run_or_fail(
    DiffWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/diff.feature"),
    ]),
  )
  |> ignore
}
