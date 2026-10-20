///|
test "build config parses local sources and ordered projections" {
  let input =
    #|{"version":"1.0","sources":["model.smithy"],"projections":{"alpha":{"transforms":[{"name":"excludeTraits","args":{"traits":["documentation"]}}]},"beta":{"abstract":true}}}
  let config = @build.BuildConfig::parse(input)
  assert_eq(config.version, "1.0")
  assert_eq(config.sources, [@build.BuildInput::from_path("model.smithy")])
  assert_eq(config.projections.length(), 2)
  assert_eq(config.projections[0].name, "alpha")
  assert_eq(config.projections[0].transforms[0].name, "excludeTraits")
  assert_true(config.projections[1].is_abstract)
}

///|
test "build config rejects unsupported dependency sources" {
  let input =
    #|{"version":"1.0","maven":{"dependencies":["foo:bar:1"]}}
  let failed = try @build.BuildConfig::parse(input) catch {
    @build.InvalidBuildConfig(_) => true
  } noraise {
    _ => false
  }
  assert_true(failed)
}

///|
test "build config permits comments outside JSON strings" {
  let input =
    #|{"version":"1.0", // config comment
    #|"sources":["https://example.com/model.smithy"] /* trailing */}
  let config = @build.BuildConfig::parse(input)
  assert_eq(config.sources, [
    @build.BuildInput::from_path("https://example.com/model.smithy"),
  ])
}

///|
test "resource input selections parse in every scope and roundtrip with aliases" {
  let input =
    #|{"version":"2.0","sources":[{"path":"${BUNDLE}","root":"package","paths":["a.smithy",{"path":"b.json","name":"renamed.json"}],"globs":["nested/**/*.smithy"]}],"imports":[{"path":"tree","root":".","globs":["*.json"]}],"projections":{"extra":{"imports":[{"path":"extra.zip","root":"data","paths":["extra.smithy"]}]}}}
  let config = @build.BuildConfig::parse(input, environment={
    "BUNDLE": "module.zip",
  })
  assert_eq(config.sources[0].location().to_string(), "module.zip")
  let encoded = config.sources[0].to_json().stringify()
  let roundtrip = @build.BuildConfig::parse(
    "{\"version\":\"2.0\",\"sources\":[" + encoded + "]}",
  )
  assert_eq(roundtrip.sources, config.sources)
  assert_eq(config.imports[0].location().to_string(), "tree")
  assert_eq(
    config.projections[0].imports[0].location().to_string(),
    "extra.zip",
  )
}

///|
test "resource config rejects ambiguous unsafe and empty selections" {
  for
    value in [
      "{}", "null", "17", "\"\"", "{\"path\":\"a.zip\",\"paths\":[\"a\"]}", "{\"path\":\"a.zip\",\"root\":\".\"}",
      "{\"path\":\"a.zip\",\"root\":\"../root\",\"paths\":[\"a\"]}", "{\"path\":\"a.zip\",\"root\":\".\",\"paths\":[\"../a\"]}",
      "{\"path\":\"a.zip\",\"root\":\".\",\"globs\":[\"a**b\"]}", "{\"path\":\"a.zip\",\"root\":\".\",\"globs\":\"**\"}",
      "{\"path\":\"a.zip\",\"root\":\".\",\"paths\":[{\"path\":\"a\",\"name\":\"/bad\"}]}",
      "{\"path\":\"a.zip\",\"root\":\".\",\"paths\":[\"a\"],\"typo\":true}",
    ] {
    let rejected = try
      @build.BuildConfig::parse(
        "{\"version\":\"2.0\",\"sources\":[" + value + "]}",
      )
    catch {
      @build.InvalidBuildConfig(_) => true
    } noraise {
      _ => false
    }
    assert_true(rejected, msg=value)
  }
}
