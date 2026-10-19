///|
fn misc_projection(
  model : @smithy.Model,
  transform : String,
) -> @smithy.Model raise {
  rewrite_projection(model, transform) catch {
    @build.InvalidBuildConfig(message) => fail(message)
    e => raise e
  }
}

///|
test "tag value transforms keep shapes and preserve empty tags traits" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@tags(["public", "internal"])
    #|string Tagged
    #|@tags(["internal"])
    #|string Internal
    #|string Untagged
  let model = rewrite_projection(
    rewrite_idl(source),
    "{\"name\":\"includeTags\",\"args\":[\"public\"]}",
  )
  assert_eq(
    model.get("example#Tagged").unwrap().trait_value("smithy.api#tags"),
    Some(@smithy.Array([@smithy.String("public")])),
  )
  assert_eq(
    model.get("example#Internal").unwrap().trait_value("smithy.api#tags"),
    Some(@smithy.Array([])),
  )
  assert_true(
    model.get("example#Untagged").unwrap().trait_value("smithy.api#tags")
    is None,
  )
  let model = rewrite_projection(
    rewrite_idl(source),
    "{\"name\":\"excludeTags\",\"args\":{\"tags\":[\"internal\"]}}",
  )
  assert_eq(
    model.get("example#Tagged").unwrap().trait_value("smithy.api#tags"),
    Some(@smithy.Array([@smithy.String("public")])),
  )
}

///|
test "trait tag transforms remove definitions and applications while preserving other shapes" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@trait @tags(["public"])
    #|structure publicTrait {}
    #|@trait @tags(["internal"])
    #|structure internalTrait {}
    #|@publicTrait @internalTrait
    #|string Value
  for
    transform in [
      "{\"name\":\"includeTraitsByTag\",\"args\":{\"tags\":[\"public\"]}}", "{\"name\":\"excludeTraitsByTag\",\"args\":{\"tags\":[\"internal\"]}}",
    ] {
    let model = rewrite_projection(rewrite_idl(source), transform)
    assert_true(model.get("example#internalTrait") is None)
    assert_true(model.get("example#publicTrait") is Some(_))
    assert_true(
      model.get("example#Value").unwrap().trait_value("example#internalTrait")
      is None,
    )
    assert_true(
      model.get("example#Value").unwrap().trait_value("example#publicTrait")
      is Some(_),
    )
    assert_true(model.get("smithy.api#documentation") is Some(_))
  }
}

///|
test "trait name transforms support namespaces and remove definitions" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@trait
    #|structure marker {}
    #|@documentation("docs") @marker
    #|string Value
  let model = rewrite_projection(
    rewrite_idl(source),
    "{\"name\":\"excludeTraits\",\"args\":{\"traits\":[\"example#\"]}}",
  )
  assert_true(model.get("example#marker") is None)
  assert_true(
    model.get("example#Value").unwrap().trait_value("example#marker") is None,
  )
  let model = rewrite_projection(
    rewrite_idl(source),
    "{\"name\":\"includeTraits\",\"args\":{\"traits\":[\"example#\"]}}",
  )
  assert_true(model.get("example#marker") is Some(_))
  assert_true(model.get("smithy.api#trait") is Some(_))
  assert_true(model.get("smithy.api#documentation") is None)
  assert_true(
    model.get("example#Value").unwrap().trait_value("smithy.api#documentation")
    is None,
  )
}

///|
test "idempotency tokens are client optional only when required" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@input
    #|structure Input { @required @idempotencyToken token: String, @required other: String }
    #|@input
    #|structure OptionalInput { @idempotencyToken optional: String }
  let model = misc_projection(
    rewrite_idl(source),
    "{\"name\":\"makeIdempotencyTokensClientOptional\"}",
  )
  assert_true(
    model
    .get("example#Input$token")
    .unwrap()
    .trait_value("smithy.api#clientOptional")
    is Some(_),
  )
  assert_true(
    model
    .get("example#OptionalInput$optional")
    .unwrap()
    .trait_value("smithy.api#clientOptional")
    is None,
  )
  assert_true(
    model
    .get("example#Input$other")
    .unwrap()
    .trait_value("smithy.api#clientOptional")
    is None,
  )
}

///|
test "flatten closure namespaces applies declared renames and preserves unrelated shapes" {
  let base = "../../tests/tck/build/transforms/"
  let loaded = @smithy.Loader::new()
    .add_idl(
      "closure.smithy",
      @fs.read_file_to_string(base + "flatten-closure-namespaces.smithy"),
    )
    .add_idl(
      "unrelated.smithy",
      @fs.read_file_to_string(
        base + "flatten-closure-namespaces-unrelated.smithy",
      ),
    )
    .assemble()
  guard loaded.model is Some(model) else { fail("model did not assemble") }
  let model = @build.apply_transform(model, {
    name: "flattenClosureNamespaces",
    args: Json::object({
      "namespace": Json::string("flattened"),
      "closure": Json::string("com.example#Shapes"),
    }),
  })
  assert_true(model.get("flattened#RenamedFoo") is Some(_))
  assert_true(model.get("flattened#RenamedFoo$bar") is Some(_))
  assert_true(model.get("flattened#Bar") is Some(_))
  assert_true(model.get("com.unrelated#Unrelated") is Some(_))
  guard model.metadata.get("shapeClosures")
    is Some(@smithy.Array([@smithy.Object(closure)])) &&
    closure.get("rename") is Some(@smithy.Object(renames)) else {
    fail("missing closure renames")
  }
  assert_true(renames.contains("flattened#RenamedFoo"))
  assert_false(renames.contains("com.example#Foo"))
}

///|
test "filter suppressions matches vendored fixture matrix" {
  let base = "../../tests/tck/build/transforms/filtersuppressions/"
  for
    (name, variant) in [
      ("traits", "removeUnused"),
      ("traits", "eventIdAllowList"),
      ("traits", "eventIdDenyList"),
      ("namespaces", "filterByNamespaceAllowList"),
      ("namespaces", "removeReasons"),
      ("namespaces", "removeUnused"),
      ("namespaces", "namespaceDenyList"),
      ("namespaces", "detectsValidatorRemoval"),
      ("namespaces", "unchanged"),
      ("noSuppressions", "removeUnused"),
      ("eventHierarchy", "removeUnused"),
    ] {
    let loaded = @smithy.Loader::new()
      .add_idl(
        name + ".smithy",
        @fs.read_file_to_string(base + name + ".smithy"),
      )
      .assemble()
    guard loaded.model is Some(model) else { fail("model did not assemble") }
    let config = @build.BuildConfig::parse(
      @fs.read_file_to_string(base + name + "." + variant + ".json"),
    )
    let captured : Map[String, @smithy.Model] = Map([])
    let projections = config.projections.map(p => {
      ..p,
      plugins: { "capture": Json::object(Map([])) },
    })
    let runner = @build.BuildRunner::new({ ..config, projections, }).register_plugin(
      "capture",
      (model, _) => {
        captured["model"] = model
        Map([])
      },
    )
    let _ = runner.run(model)
    let actual = captured.get("model").unwrap()
    let expected = @smithy.Loader::new()
    .add_idl(
      "expected.smithy",
      @fs.read_file_to_string(base + name + "." + variant + ".smithy"),
    )
    .assemble().model.unwrap()
    assert_eq(
      actual.to_json_ast(),
      expected.to_json_ast(),
      msg=name + "." + variant,
    )
  }
}

///|
test "filter suppressions handles the combined imported models from reference fixtures" {
  let base = "../../tests/tck/build/transforms/filtersuppressions/"
  for variant in ["filterWithTopLevelImports", "filterWithProjectionImports"] {
    let loader = @smithy.Loader::new()
      .add_idl(
        "namespaces.smithy",
        @fs.read_file_to_string(base + "namespaces.smithy"),
      )
      .add_idl(
        "extra.smithy",
        @fs.read_file_to_string(base + "namespaces." + variant + ".2.smithy"),
      )
    guard loader.assemble().model is Some(model) else {
      fail("model did not assemble")
    }
    let actual = rewrite_projection(
      model, "{\"name\":\"filterSuppressions\",\"args\":{\"removeUnused\":true}}",
    )
    let expected = @smithy.Loader::new()
    .add_idl(
      "expected.smithy",
      @fs.read_file_to_string(base + "namespaces." + variant + ".smithy"),
    )
    .assemble().model.unwrap()
    assert_eq(actual.to_json_ast(), expected.to_json_ast(), msg=variant)
  }
}

///|
test "metadata transforms support legacy arrays and named arguments" {
  let model = rewrite_idl(
    "$version: \"2\"\nmetadata first = true\nmetadata second = false\nnamespace example\nstring Name\n",
  )
  let included = rewrite_projection(
    model, "{\"name\":\"includeMetadata\",\"args\":[\"first\"]}",
  )
  assert_eq(included.metadata.length(), 1)
  assert_true(included.metadata.contains("first"))
  let excluded = rewrite_projection(
    model, "{\"name\":\"excludeMetadata\",\"args\":{\"__args\":[\"first\"]}}",
  )
  assert_eq(excluded.metadata.length(), 1)
  assert_true(excluded.metadata.contains("second"))
}

///|
test "misc transforms reject conflicting suppression lists and invalid closure configuration" {
  let model = rewrite_idl("$version: \"2\"\nnamespace example\nstring Name\n")
  for
    transform in [
      "{\"name\":\"filterSuppressions\",\"args\":{\"eventIdAllowList\":[\"A\"],\"eventIdDenyList\":[\"B\"]}}",
      "{\"name\":\"filterSuppressions\",\"args\":{\"namespaceAllowList\":[\"A\"],\"namespaceDenyList\":[\"B\"]}}",
      "{\"name\":\"filterSuppressions\",\"args\":{\"removeUnused\":\"yes\"}}", "{\"name\":\"flattenClosureNamespaces\",\"args\":{\"namespace\":\"flat\"}}",
      "{\"name\":\"flattenClosureNamespaces\",\"args\":{\"namespace\":\"flat\",\"closure\":\"missing\"}}",
      "{\"name\":\"includeTags\",\"args\":{\"tags\":[true]}}", "{\"name\":\"excludeTraits\",\"args\":{\"traits\":[\"bad id\"]}}",
    ] {
    assert_true(
      try rewrite_projection(model, transform) catch {
        @build.InvalidBuildConfig(_) => true
        _ => false
      } noraise {
        _ => false
      },
    )
  }
}
