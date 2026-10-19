///|
fn plugin_failure_model() -> @smithy.Model {
  @smithy.Loader::new()
  .add_idl("input.smithy", "$version: \"2\"\nnamespace example\nstring Name\n")
  .assemble().model.unwrap()
}

///|
test "plugin callback failures retain builtins and later successful plugins in the same projection" {
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"plugins\":{\"aaa\":{},\"zzz\":{}}}",
  )
  let executed : Array[String] = []
  let runner = @build.BuildRunner::new(config)
    .register_plugin("aaa", (_, _) => {
      executed.push("aaa")
      raise @build.InvalidBuildConfig("aaa failed")
    })
    .register_plugin("zzz", (_, _) => {
      executed.push("zzz")
      { "result.txt": "healthy" }
    })
  let result = runner.run_result(plugin_failure_model())
  assert_eq(executed, ["aaa", "zzz"])
  assert_eq(result.errors.length(), 1)
  assert_true(result.errors[0].contains("aaa failed"))
  assert_eq(result.artifacts.get("source/zzz/result.txt"), Some("healthy"))
  assert_true(result.artifacts.contains("source/model/model.json"))
  assert_true(
    result.artifacts.contains("source/build-info/smithy-build-info.json"),
  )
  assert_true(result.artifacts.contains("source/sources/manifest"))
}

///|
test "invalid plugin filenames preserve healthy plugins and aggregate all execution errors" {
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"plugins\":{\"aaa\":{},\"bbb\":{},\"zzz\":{}}}",
  )
  let executed : Array[String] = []
  let runner = @build.BuildRunner::new(config)
    .register_plugin("aaa", (_, _) => {
      executed.push("aaa")
      { "../escape.txt": "invalid", "valid.txt": "must not write" }
    })
    .register_plugin("bbb", (_, _) => {
      executed.push("bbb")
      raise @build.InvalidBuildConfig("bbb failed")
    })
    .register_plugin("zzz", (_, _) => {
      executed.push("zzz")
      { "result.txt": "healthy" }
    })
  let result = runner.run_result(plugin_failure_model())
  assert_eq(executed, ["aaa", "bbb", "zzz"])
  assert_eq(result.errors.length(), 1)
  assert_true(result.errors[0].contains("../escape.txt"))
  assert_true(result.errors[0].contains("bbb failed"))
  assert_false(
    result.artifacts.keys().any(name => name.has_prefix("source/aaa/")),
  )
  assert_eq(result.artifacts.get("source/zzz/result.txt"), Some("healthy"))
  assert_true(result.artifacts.contains("source/model/model.json"))
  assert_true(
    result.artifacts.contains("source/build-info/smithy-build-info.json"),
  )
}

///|
test "empty source manifests contain the final newline for defaults and aliases" {
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"plugins\":{\"sources::copy\":{}}}",
  )
  let result = @build.BuildRunner::new(config).run(plugin_failure_model())
  assert_eq(result.get("source/sources/manifest"), Some("\n"))
  assert_eq(result.get("source/copy/manifest"), Some("\n"))
}
