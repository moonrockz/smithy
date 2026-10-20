///|
test "build config rejects wrongly typed fields instead of using defaults" {
  for
    field in [
      "\"version\":1", "\"version\":null", "\"version\":true", "\"outputDirectory\":false",
      "\"outputDirectory\":null", "\"outputDirectory\":\"\"", "\"ignoreMissingPlugins\":\"true\"",
      "\"ignoreMissingPlugins\":null", "\"sources\":\"model\"", "\"sources\":[false]",
      "\"imports\":null", "\"plugins\":{\"model\":null}", "\"plugins\":{\"model\":[]}",
      "\"projections\":{\"bad\":{\"abstract\":\"true\"}}", "\"projections\":{\"bad\":{\"abstract\":null}}",
      "\"projections\":{\"bad\":{\"plugins\":{\"model\":true}}}", "\"projections\":{\"bad\":{\"transforms\":[{\"name\":\"apply\",\"args\":null}]}}",
      "\"projections\":{\"bad\":{\"transforms\":[{\"name\":\"apply\",\"args\":false}]}}",
      "\"maven\":{\"dependencies\":false}", "\"maven\":{\"repositories\":{}}", "\"maven\":{\"repositories\":[{}]}",
      "\"maven\":{\"repositories\":[{\"url\":false}]}", "\"maven\":{\"repositories\":[{\"url\":\"https://example.com\",\"id\":false}]}",
      "\"maven\":{\"repositories\":[{\"url\":\"https://example.com\",\"httpCredentials\":\"missing-colon\"}]}",
    ] {
    let input = if field.has_prefix("\"version\"") {
      "{" + field + "}"
    } else {
      "{\"version\":\"1.0\"," + field + "}"
    }
    let rejected = try @build.BuildConfig::parse(input) catch {
      @build.InvalidBuildConfig(_) => true
    } noraise {
      _ => false
    }
    assert_true(rejected, msg=input)
  }
}

///|
test "abstract projections reject imports and plugins" {
  for extra in ["\"imports\":[\"input.smithy\"]", "\"plugins\":{\"model\":{}}"] {
    let rejected = try
      @build.BuildConfig::parse(
        "{\"version\":\"1.0\",\"projections\":{\"base\":{\"abstract\":true," +
        extra +
        "}}}",
      )
    catch {
      @build.InvalidBuildConfig(_) => true
    } noraise {
      _ => false
    }
    assert_true(rejected, msg=extra)
  }
}

///|
test "valid explicit defaults and legacy transform arrays remain accepted" {
  let config = @build.BuildConfig::parse(
    "{\"version\":\"2.0\",\"ignoreMissingPlugins\":false,\"maven\":{\"dependencies\":[],\"repositories\":[{\"url\":\"https://example.com\",\"httpCredentials\":\"user:password\"}]},\"projections\":{\"base\":{\"abstract\":false,\"transforms\":[{\"name\":\"includeNamespaces\",\"args\":[\"example\"]}]}}}",
  )
  assert_eq(config.output_directory, "build/smithy")
  assert_false(config.ignore_missing_plugins)
  assert_false(config.projections[0].is_abstract)
}

///|
test "model plugin rejects a wrongly typed prelude setting" {
  let model = @smithy.Loader::new()
  .add_idl("input.smithy", "$version: \"2\"\nnamespace example\nstring Name")
  .assemble().model.unwrap()
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"projections\":{\"bad\":{\"plugins\":{\"model\":{\"includePreludeShapes\":\"true\"}}}}}",
  )
  let result = @build.BuildRunner::new(config).run_result(model)
  assert_true(
    result.errors
    .iter()
    .any(message => message.contains("includePreludeShapes")),
  )
  assert_false(result.artifacts.contains("bad/model/model.json"))
  assert_true(result.artifacts.contains("source/model/model.json"))
}

///|
test "duplicate source filenames from separate roots fail before plugins run" {
  let first_path = "../../tests/tck/build/plugins/sources/a.smithy"
  let second_path = "../../tests/tck/build/plugins/conflicting/a.smithy"
  let first = @fs.read_file_to_string(first_path)
  let second = @fs.read_file_to_string(second_path)
  let model = @smithy.Loader::new()
  .add_idl(first_path, first)
  .add_idl(second_path, second)
  .assemble().model.unwrap()
  let calls : Array[String] = []
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"plugins\":{\"record\":{}}}",
  )
  let result = @build.BuildRunner::new(config)
    .register_plugin("record", (_, _) => {
      calls.push("called")
      { "output": "unexpected" }
    })
    .add_source("a.smithy", first, source_file=Some(first_path))
    .add_source("a.smithy", second, source_file=Some(second_path))
    .run_result(model)
  assert_true(result.artifacts.is_empty())
  assert_true(result.errors.iter().any(message => message.contains("a.smithy")))
  assert_true(calls.is_empty())
}

///|
test "cache and offline configuration validates boundary values" {
  let defaults = @build.BuildConfig::parse("{\"version\":\"2.0\"}")
  assert_eq(defaults.cache_directory.to_string(), ".smithy/cache")
  assert_false(defaults.offline)
  let configured = @build.BuildConfig::parse(
    "{\"version\":\"2.0\",\"cacheDirectory\":\"${CACHE}\",\"offline\":true}",
    environment={ "CACHE": "artifacts" },
  )
  assert_eq(configured.cache_directory.to_string(), "artifacts")
  assert_true(configured.offline)
  for
    setting in [
      "\"offline\":1", "\"offline\":\"true\"", "\"cacheDirectory\":false", "\"cacheDirectory\":\"\"",
      "\"cacheDirectory\":\"a\\n\"",
    ] {
    let rejected = try
      @build.BuildConfig::parse("{\"version\":\"2.0\"," + setting + "}")
    catch {
      @build.InvalidBuildConfig(_) => true
    } noraise {
      _ => false
    }
    assert_true(rejected, msg=setting)
  }
}
