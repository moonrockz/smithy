///|
test "vendored config expands object keys and compound array strings" {
  let config = @build.BuildConfig::parse(
    @fs.read_file_to_string("../../tests/tck/build/config-with-env.json"),
    environment={ "FOO": "Hi", "BAR": "TagFromEnv", "NAME_KEY": "name" },
  )
  let transform = config.projections[0].transforms[0]
  assert_eq(transform.name, "includeShapesByTag")
  assert_eq(
    transform.args,
    Json::object({
      "tags": Json::array(
        ["Hi", "compoundTagFromEnv", "HiAndTagFromEnv", "${BAZ}"].map(
          Json::string,
        ),
      ),
    }),
  )
}

///|
test "environment expansion applies throughout config and respects escaped placeholders" {
  let source =
    #|{"${VERSION_KEY}":"${VERSION}","outputDirectory":"build/${DIRECTORY}","projections":{"${PROJECTION}":{"plugins":{"model":{"nested":{"${KEY}":["${VALUE}","\\${MISSING}","${}","${UNFINISHED","${A}${B}","$literal"]}}}}}}
  let config = @build.BuildConfig::parse(source, environment={
    "VERSION_KEY": "version",
    "VERSION": "2.0",
    "DIRECTORY": "models",
    "PROJECTION": "expanded",
    "KEY": "values",
    "VALUE": "literal",
    "A": "first",
    "B": "second",
  })
  assert_eq(config.output_directory, "build/models")
  assert_eq(config.projections[0].name, "expanded")
  assert_eq(
    config.projections[0].plugins["model"],
    Json::object({
      "nested": Json::object({
        "values": Json::array(
          [
            "literal", "${MISSING}", "${}", "${UNFINISHED", "first${B}", "$literal",
          ].map(Json::string),
        ),
      }),
    }),
  )
}

///|
test "undefined environment variables fail even in object keys" {
  for
    source in [
      @fs.read_file_to_string(
        "../../tests/tck/build/config-with-invalid-env.json",
      ),
      "{\"version\":\"2.0\",\"outputDirectory\":\"${INVALID_KEY_DOES_NOT_EXIST}\"}",
    ] {
    let rejected = try @build.BuildConfig::parse(source) catch {
      @build.InvalidBuildConfig(message) =>
        message.contains("INVALID_KEY_DOES_NOT_EXIST")
    } noraise {
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "configs without placeholders retain escaped dollar signs" {
  let source =
    #|{"version":"2.0","plugins":{"model":{"price":"\\$10"}}}
  let config = @build.BuildConfig::parse(source)
  assert_eq(
    config.plugins["model"],
    Json::object({ "price": Json::string("\\$10") }),
  )
}
