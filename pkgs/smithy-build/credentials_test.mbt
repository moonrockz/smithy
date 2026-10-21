///|
test "credential config keeps references and resolves redacted values at invocation" {
  let config = @build.BuildConfig::parse(
    "{\"version\":\"2.0\",\"credentials\":[{\"origin\":\"https://npm.test\",\"bearerTokenEnv\":\"NPM_TOKEN\"},{\"origin\":\"https://maven.test\",\"usernameEnv\":\"MAVEN_USER\",\"passwordEnv\":\"MAVEN_PASSWORD\"}]}",
  )
  assert_eq(config.credentials.length(), 2)
  let credentials = config.resolve_credentials({
    "NPM_TOKEN": "test-token",
    "MAVEN_USER": "user",
    "MAVEN_PASSWORD": "password",
  })
  assert_eq(
    credentials
    .for_url(@resources.HttpUrl::parse("https://npm.test/a").unwrap())
    .map(value => value.header_value()),
    Some("Bearer test-token"),
  )
  assert_eq(
    credentials
    .for_url(@resources.HttpUrl::parse("https://maven.test/a").unwrap())
    .map(value => value.header_value()),
    Some("Basic dXNlcjpwYXNzd29yZA=="),
  )
  for
    environment in [
      Map([]),
      { "NPM_TOKEN": "", "MAVEN_USER": "user", "MAVEN_PASSWORD": "password" },
      {
        "NPM_TOKEN": "secret\nheader",
        "MAVEN_USER": "user",
        "MAVEN_PASSWORD": "password",
      },
    ] {
    let error = try config.resolve_credentials(environment) catch {
      @build.InvalidBuildConfig(message) => Some(message)
    } noraise {
      _ => None
    }
    assert_true(error is Some(_))
    assert_false(error.unwrap().contains("secret"))
    assert_false(error.unwrap().contains("password"))
  }
}

///|
test "credential config rejects literals ambiguous methods and unsafe origins without echoing values" {
  for
    binding in [
      "{\"origin\":\"https://host\",\"token\":\"private-secret\"}", "{\"origin\":\"https://host\",\"bearerTokenEnv\":\"${TOKEN}\"}",
      "{\"origin\":\"http://host\",\"bearerTokenEnv\":\"TOKEN\"}", "{\"origin\":\"https://host/path\",\"bearerTokenEnv\":\"TOKEN\"}",
      "{\"origin\":\"https://host\",\"bearerTokenEnv\":\"TOKEN\",\"usernameEnv\":\"USER\",\"passwordEnv\":\"PASSWORD\"}",
      "{\"origin\":\"https://host\",\"usernameEnv\":\"USER\"}", "{\"origin\":\"https://private-secret@host\",\"bearerTokenEnv\":\"TOKEN\"}",
      "{\"origin\":\"https://host\",\"bearerTokenEnv\":1}",
    ] {
    let error = try
      @build.BuildConfig::parse(
        "{\"version\":\"2.0\",\"credentials\":[" + binding + "]}",
        environment={ "TOKEN": "private-secret" },
      )
    catch {
      @build.InvalidBuildConfig(message) => Some(message)
    } noraise {
      _ => None
    }
    assert_true(error is Some(_), msg=binding)
    assert_false(error.unwrap().contains("private-secret"))
  }
}
