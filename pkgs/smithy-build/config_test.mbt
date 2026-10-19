///|
test "build config parses local sources and ordered projections" {
  let input =
    #|{"version":"1.0","sources":["model.smithy"],"projections":{"alpha":{"transforms":[{"name":"excludeTraits","args":{"traits":["documentation"]}}]},"beta":{"abstract":true}}}
  let config = @build.BuildConfig::parse(input)
  assert_eq(config.version, "1.0")
  assert_eq(config.sources, ["model.smithy"])
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
  assert_eq(config.sources, ["https://example.com/model.smithy"])
}
