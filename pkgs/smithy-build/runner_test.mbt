///|
test "invalid projected models still write build info and preserve successful projections" {
  let model = @smithy.Loader::new()
  .add_idl(
    "input.smithy", "$version: \"2\"\nmetadata validators = [{name: \"EmitNoneSelector\", configuration: {selector: \"structure\"}}]\nnamespace example\nstructure Thing {}",
  )
  .assemble().model.unwrap()
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"projections\":{\"broken\":{\"transforms\":[{\"name\":\"excludeShapesBySelector\",\"args\":{\"selector\":\"structure\"}}]},\"good\":{}}}",
  )
  let runner = @build.BuildRunner::new(config)
  let result = runner.run_result(model)
  assert_false(result.errors.is_empty())
  assert_true(
    result.artifacts.contains("broken/build-info/smithy-build-info.json"),
  )
  assert_false(result.artifacts.contains("broken/model/model.json"))
  assert_true(result.artifacts.contains("good/model/model.json"))
}

///|
test "projected sources include original sources and new shapes but omit imports" {
  let source = "$version: \"2\"\nmetadata local = true\nnamespace source\nstructure Original { value: imported#Value }"
  let imported = "$version: \"2\"\nmetadata imported = true\nnamespace imported\nstring Value"
  let model = @smithy.Loader::new()
  .add_idl("source.smithy", source)
  .add_idl("imported.smithy", imported)
  .assemble().model.unwrap()
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"projections\":{\"copy\":{}}}",
  )
  let artifacts = @build.BuildRunner::new(config)
    .add_source("source.smithy", source)
    .run(model)
  let projected = @json.parse(artifacts["copy/sources/model.json"])
  assert_true(
    projected
    is {
      "shapes": { "source#Original": _, .. },
      "metadata": { "local": _, .. },
      ..
    },
  )
  assert_false(projected is { "shapes": { "imported#Value": _, .. }, .. })
  assert_false(projected is { "metadata": { "imported": _, .. }, .. })
  assert_true(artifacts["copy/model/model.json"].contains("imported#Value"))
}

///|
test "projection imports merge only into their projection" {
  let model = @smithy.Loader::new()
  .add_idl("base.smithy", "$version: \"2\"\nnamespace example\nstring Original")
  .assemble().model.unwrap()
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"projections\":{\"extra\":{\"imports\":[\"extra.smithy\"]},\"plain\":{}}}",
  )
  assert_eq(config.projections[0].imports, [
    @build.BuildInput::from_path("extra.smithy"),
  ])
  let runner = @build.BuildRunner::new(config).add_projection_import(
    "extra",
    @smithy.ModelInput::Idl(
      name="extra.smithy",
      text="$version: \"2\"\nnamespace extra\nstructure Added {}",
    ),
  )
  let artifacts = runner.run(model)
  assert_true(artifacts["extra/model/model.json"].contains("extra#Added"))
  assert_false(artifacts["plain/model/model.json"].contains("extra#Added"))
  assert_false(artifacts["source/model/model.json"].contains("extra#Added"))
}

///|
test "build runner writes source and transformed model projections" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@documentation("visible")
    #|string Name
  let loaded = @smithy.Loader::new().add_idl("input.smithy", source).assemble()
  guard loaded.model is Some(model) else { fail("model did not assemble") }
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"projections\":{\"filtered\":{\"transforms\":[{\"name\":\"excludeTraits\",\"args\":{\"traits\":[\"documentation\"]}}]},\"hidden\":{\"abstract\":true}}}",
  )
  let outputs = @build.BuildRunner::new(config).run(model)
  assert_true(outputs.get("source/model/model.json") is Some(_))
  guard outputs.get("filtered/model/model.json") is Some(filtered) else {
    fail("missing filtered model")
  }
  assert_false(filtered.contains("smithy.api#documentation"))
  assert_false(outputs.keys().any(key => key.has_prefix("hidden/")))
}

///|
test "build runner invokes registered plugins for each concrete projection" {
  let source = "$version: \"2\"\nnamespace example\nstring Name\n"
  let loaded = @smithy.Loader::new().add_idl("input.smithy", source).assemble()
  guard loaded.model is Some(model) else { fail("model did not assemble") }
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"plugins\":{\"custom\":{\"tag\":\"ok\"}}}",
  )
  let runner = @build.BuildRunner::new(config).register_plugin("custom", (
    _,
    settings,
  ) => {
    let files : Map[String, String] = Map([])
    files["result.json"] = settings.stringify()
    files
  })
  let artifacts = runner.run(model)
  assert_eq(
    artifacts.get("source/custom/result.json"),
    Some("{\"tag\":\"ok\"}"),
  )
}

///|
test "build runner stops before artifacts when model validation fails" {
  let source =
    #|$version: "2"
    #|metadata validators = [{name: "EmitNoneSelector", configuration: {selector: "service"}}]
    #|namespace example
    #|string Name
  let loaded = @smithy.Loader::new().add_idl("input.smithy", source).assemble()
  guard loaded.model is Some(model) else { fail("model did not assemble") }
  let config = @build.BuildConfig::parse("{\"version\":\"1.0\"}")
  let failed = try @build.BuildRunner::new(config).run(model) catch {
    @build.InvalidBuildConfig(message) => message.contains("EmitNoneSelector")
  } noraise {
    _ => false
  }
  assert_true(failed)
}

///|
test "vendored simple build projection keeps tagged shapes" {
  let model_source = @fs.read_file_to_string(
    "../../tests/tck/build/simple-model.json",
  )
  let config_source = @fs.read_file_to_string(
    "../../tests/tck/build/simple-config.json",
  )
  let loaded = @smithy.Loader::new()
    .add_json("simple-model.json", model_source)
    .assemble()
  guard loaded.model is Some(model) else { fail("model did not assemble") }
  let artifacts = @build.BuildRunner::new(
    @build.BuildConfig::parse(config_source),
  ).run(model)
  guard artifacts.get("a/model/model.json") is Some(text) else {
    fail("missing a model")
  }
  assert_true(text.contains("ns.foo#String1"))
  assert_true(text.contains("ns.foo#String3"))
  assert_false(text.contains("ns.foo#String2"))
}

///|
test "apply runs abstract projection transforms in order" {
  let source = "$version: \"2\"\nnamespace example\n@documentation(\"docs\")\nstring Name\n"
  let loaded = @smithy.Loader::new().add_idl("input.smithy", source).assemble()
  guard loaded.model is Some(model) else { fail("model did not assemble") }
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"projections\":{\"base\":{\"abstract\":true,\"transforms\":[{\"name\":\"excludeTraits\",\"args\":{\"traits\":[\"documentation\"]}}]},\"concrete\":{\"transforms\":[{\"name\":\"apply\",\"args\":{\"projections\":[\"base\"]}}]}}}",
  )
  let artifacts = @build.BuildRunner::new(config).run(model)
  guard artifacts.get("concrete/model/model.json") is Some(text) else {
    fail("missing concrete model")
  }
  assert_false(text.contains("smithy.api#documentation"))
}

///|
test "apply rejects projection cycles" {
  let source = "$version: \"2\"\nnamespace example\nstring Name\n"
  let loaded = @smithy.Loader::new().add_idl("input.smithy", source).assemble()
  guard loaded.model is Some(model) else { fail("model did not assemble") }
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"projections\":{\"a\":{\"transforms\":[{\"name\":\"apply\",\"args\":{\"projections\":[\"b\"]}}]},\"b\":{\"transforms\":[{\"name\":\"apply\",\"args\":{\"projections\":[\"a\"]}}]}}}",
  )
  let failed = try @build.BuildRunner::new(config).run(model) catch {
    @build.InvalidBuildConfig(message) => message.contains("cycle")
  } noraise {
    _ => false
  }
  assert_true(failed)
}

///|
test "build info lists projected services and operations" {
  let source =
    #|$version: "2"
    #|namespace example
    #|service Api { version: "1", operations: [Get] }
    #|operation Get {}
  let loaded = @smithy.Loader::new().add_idl("input.smithy", source).assemble()
  guard loaded.model is Some(model) else { fail("model did not assemble") }
  let config = @build.BuildConfig::parse("{\"version\":\"1.0\"}")
  let artifacts = @build.BuildRunner::new(config).run(model)
  guard artifacts.get("source/build-info/smithy-build-info.json") is Some(info) else {
    fail("missing build info")
  }
  assert_true(info.contains("example#Api"))
  assert_true(info.contains("example#Get"))
}
