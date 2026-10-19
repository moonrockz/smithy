///|
fn plugin_alias_model() -> @smithy.Model {
  @smithy.Loader::new()
  .add_idl("input.smithy", "$version: \"2\"\nnamespace example\nstring Name\n")
  .assemble().model.unwrap()
}

///|
test "vendored model aliases configure prelude inclusion independently" {
  let model = plugin_alias_model()
  for
    (fixture, artifact_name, included) in [
      ("include-prelude-shapes", "withPrelude", true),
      ("exclude-prelude-shapes", "withoutPrelude", false),
    ] {
    let config = @build.BuildConfig::parse(
      @fs.read_file_to_string("../../tests/tck/build/" + fixture + ".json"),
    )
    let artifacts = @build.BuildRunner::new(config).run(model)
    let document = @json.parse(
      artifacts["source/" + artifact_name + "/model.json"],
    )
    assert_eq(
      document is { "shapes": { "smithy.api#String": _, .. }, .. },
      included,
    )
    assert_true(artifacts.contains("source/model/model.json"))
  }
}

///|
test "registered plugin aliases keep independent settings and projection overrides" {
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"plugins\":{\"custom::one\":{\"tag\":\"root\"},\"custom::two\":{\"tag\":\"second\"}},\"projections\":{\"child\":{\"plugins\":{\"custom::one\":{\"tag\":\"child\"}}}}}",
  )
  let runner = @build.BuildRunner::new(config).register_plugin("custom", (
    _,
    settings,
  ) => { "result.json": settings.stringify() })
  let artifacts = runner.run(plugin_alias_model())
  assert_eq(artifacts["source/one/result.json"], "{\"tag\":\"root\"}")
  assert_eq(artifacts["source/two/result.json"], "{\"tag\":\"second\"}")
  assert_eq(artifacts["child/one/result.json"], "{\"tag\":\"child\"}")
  assert_eq(artifacts["child/two/result.json"], "{\"tag\":\"second\"}")
  assert_false(artifacts.keys().any(key => key.contains("custom::")))
}

///|
test "source and build info aliases retain default artifacts" {
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"plugins\":{\"sources::inputs\":{},\"build-info::report\":{}}}",
  )
  let artifacts = @build.BuildRunner::new(config)
    .add_source("input.smithy", "source content")
    .run(plugin_alias_model())
  assert_eq(artifacts["source/inputs/input.smithy"], "source content")
  assert_eq(artifacts["source/inputs/manifest"], "input.smithy\n")
  assert_eq(artifacts["source/sources/input.smithy"], "source content")
  assert_eq(
    artifacts["source/report/smithy-build-info.json"],
    artifacts["source/build-info/smithy-build-info.json"],
  )
}

///|
test "artifact aliases cannot collide with explicit or default artifacts" {
  for
    plugins in [
      "{\"unknown::same\":{},\"other::same\":{}}", "{\"unknown::model\":{}}", "{\"model::model\":{}}",
    ] {
    let config = @build.BuildConfig::parse(
      "{\"version\":\"1.0\",\"ignoreMissingPlugins\":true,\"plugins\":" +
      plugins +
      "}",
    )
    let rejected = try
      @build.BuildRunner::new(config).run(plugin_alias_model())
    catch {
      @build.InvalidBuildConfig(message) =>
        message.contains("same artifact name")
    } noraise {
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "missing aliased plugins honor ignoreMissingPlugins" {
  let ignored = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"ignoreMissingPlugins\":true,\"plugins\":{\"missing::alias\":{}}}",
  )
  let artifacts = @build.BuildRunner::new(ignored).run(plugin_alias_model())
  assert_true(artifacts.contains("source/model/model.json"))
  assert_false(artifacts.keys().any(key => key.has_prefix("source/alias/")))
  let strict = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"plugins\":{\"missing::alias\":{}}}",
  )
  let rejected = try
    @build.BuildRunner::new(strict).run(plugin_alias_model())
  catch {
    @build.InvalidBuildConfig(message) => message.contains("missing::alias")
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
test "global builtin defaults and projection settings match the reference" {
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"plugins\":{\"model\":{\"includePreludeShapes\":true}},\"projections\":{\"child\":{\"plugins\":{\"model\":{\"includePreludeShapes\":true}}}}}",
  )
  let artifacts = @build.BuildRunner::new(config).run(plugin_alias_model())
  assert_false(
    @json.parse(artifacts["source/model/model.json"])
    is { "shapes": { "smithy.api#String": _, .. }, .. },
  )
  assert_true(
    @json.parse(artifacts["child/model/model.json"])
    is { "shapes": { "smithy.api#String": _, .. }, .. },
  )
}

///|
test "malformed plugin aliases are rejected even when missing plugins are ignored" {
  for name in ["model::", "::artifact", "model::one::two", "model::../outside"] {
    let config = @build.BuildConfig::parse(
      "{\"version\":\"1.0\",\"ignoreMissingPlugins\":true,\"plugins\":{\"" +
      name +
      "\":{}}}",
    )
    let rejected = try
      @build.BuildRunner::new(config).run(plugin_alias_model())
    catch {
      @build.InvalidBuildConfig(_) => true
    } noraise {
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "registered plugins can only write relative files inside their artifact" {
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"plugins\":{\"custom\":{}}}",
  )
  for
    file in [
      "../outside", "/absolute", "C:\\absolute", "folder/../../outside", "folder\\..\\outside",
      "",
    ] {
    let runner = @build.BuildRunner::new(config).register_plugin("custom", (
      _,
      _,
    ) => Map([(file, "content")]))
    let rejected = try runner.run(plugin_alias_model()) catch {
      @build.InvalidBuildConfig(message) =>
        message.contains("relative artifact file")
    } noraise {
      _ => false
    }
    assert_true(rejected, msg=file)
  }
}
