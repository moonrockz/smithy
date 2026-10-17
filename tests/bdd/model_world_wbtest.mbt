///|
struct ModelWorld {
  loader : @smithy.Loader
  mut result : @smithy.LoadResult?
}

///|
fn ModelWorld::new() -> ModelWorld {
  { loader: @smithy.Loader::new(), result: None, }
}

///|
fn ModelWorld::assembled(self : ModelWorld) -> @smithy.LoadResult raise {
  guard self.result is Some(result) else { fail("the model was not assembled") }
  result
}

///|
fn ModelWorld::model(self : ModelWorld) -> @smithy.Model raise {
  guard self.assembled().model is Some(model) else {
    fail(
      "assembly failed: " +
      self.assembled().diagnostics.map(d => d.message).join("\n"),
    )
  }
  model
}

///|
fn ModelWorld::shape(self : ModelWorld, id : String) -> @smithy.Shape raise {
  guard self.model().get(id) is Some(shape) else { fail("no shape " + id) }
  shape
}

///|
fn strings(value : @smithy.NodeValue) -> String raise {
  guard value is Array(values) else { fail("expected an array") }
  let out = []
  for value in values {
    guard value is String(value) else { fail("expected a string") }
    out.push(value)
  }
  out.join(", ")
}

///|
impl @moonspec.World for ModelWorld with fn configure(self, setup) {
  setup.then0("converting the model to IDL and back preserves the JSON AST", fn() raise {
    let model = self.model()
    let loader = @smithy.Loader::new()
    for ns, text in model.to_idl() {
      loader.add_idl(ns + ".smithy", text) |> ignore
    }
    let result = loader.assemble()
    assert_false(result.has_errors())
    assert_eq(
      @syntax.encode_json_ast(result.model.unwrap().to_json_ast()),
      @syntax.encode_json_ast(model.to_json_ast()),
    )
  })
  setup.then1("IDL conversion emits {int} namespace files", fn(
    count : Int32,
  ) raise {
    assert_eq(self.model().to_idl().length(), count)
  })
  setup.given2("the IDL model file {string}:", fn(
    name : String,
    doc : @moonspec.DocString,
  ) {
    self.loader.add_idl(name, doc.content) |> ignore
  })
  setup.given2("the JSON model file {string}:", fn(
    name : String,
    doc : @moonspec.DocString,
  ) {
    self.loader.add_json(name, doc.content) |> ignore
  })
  setup.when0("I assemble the semantic model", fn() {
    self.result = Some(self.loader.assemble())
  })
  setup.then0("the model has no errors", fn() raise {
    assert_true(!self.assembled().has_errors())
    self.model() |> ignore
  })
  setup.then2("the semantic member {string} targets {string}", fn(
    id : String,
    target : String,
  ) raise {
    guard self.shape(id).body is Member(target=actual) else {
      fail("expected member " + id)
    }
    assert_eq(actual.to_string(), target)
  })
  setup.then2("the semantic shape {string} has trait {string}", fn(
    id : String,
    trait_ : String,
  ) raise {
    assert_true(self.shape(id).trait_value(trait_) is Some(_))
  })
  setup.then2("the semantic shape {string} has documentation {string}", fn(
    id : String,
    value : String,
  ) raise {
    assert_eq(
      self.shape(id).trait_value("smithy.api#documentation"),
      Some(String(value)),
    )
  })
  setup.then2("the semantic shape {string} has tags {string}", fn(
    id : String,
    value : String,
  ) raise {
    assert_eq(
      strings(self.shape(id).trait_value("smithy.api#tags").unwrap()),
      value,
    )
  })
  setup.then2("the metadata {string} contains strings {string}", fn(
    key : String,
    value : String,
  ) raise {
    assert_eq(strings(self.model().metadata.get(key).unwrap()), value)
  })
  setup.then0("the assembled model exports and reloads unchanged", fn() raise {
    let document = self.model().to_json_ast()
    let result = @smithy.Loader::new()
      .add_ast("export.json", document)
      .assemble()
    guard result.model is Some(model) else { fail("export did not reload") }
    assert_eq(
      @syntax.encode_json_ast(model.to_json_ast()),
      @syntax.encode_json_ast(document),
    )
  })
  setup.then1("the model diagnostics include {string}", fn(
    code : String,
  ) raise {
    assert_true(self.assembled().diagnostics.iter().any(d => d.code == code))
  })
  setup.then0("no semantic model is returned", fn() raise {
    assert_eq(self.assembled().model, None)
  })
  setup.then1("the model errors name source {string}", fn(name : String) raise {
    assert_true(
      self.assembled().diagnostics
      .iter()
      .filter(d => d.severity == Error)
      .all(d => d.source.file == name),
    )
  })
}

///|
async test "semantic model feature" {
  @moonspec.run_or_fail(
    ModelWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/model.feature"),
    ]),
  )
  |> ignore
}
