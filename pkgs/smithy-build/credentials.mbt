///|
/// An environment variable name, never its secret value.
pub struct CredentialVariable {
  priv name : String
} derive(Eq, Debug)

///|
pub fn CredentialVariable::parse(text : String) -> CredentialVariable? {
  if text.is_empty() || text.length() > 128 {
    return None
  }
  for i, c in text.iter() {
    if !(c == '_' ||
      (c >= 'A' && c <= 'Z') ||
      (c >= 'a' && c <= 'z') ||
      (i > 0 && c >= '0' && c <= '9')) {
      return None
    }
  }
  Some({ name: text, })
}

///|
pub fn CredentialVariable::to_string(self : CredentialVariable) -> String {
  self.name
}

///|
pub(all) enum CredentialSource {
  BearerEnvironment(CredentialVariable)
  BasicEnvironment(CredentialVariable, CredentialVariable)
} derive(Eq, Debug)

///|
pub(all) struct CredentialBinding {
  origin : @resources.HttpOrigin
  source : CredentialSource
} derive(Eq, Debug)

///|
fn config_credentials(
  document : Json,
) -> Array[CredentialBinding] raise BuildError {
  let values = match config_field(document, "credentials") {
    None => return []
    Some(Array(values)) => values
    _ =>
      raise InvalidBuildConfig(
        "Expected credentials to be an array of origin and environment-variable bindings",
      )
  }
  if values.length() > 32 {
    raise InvalidBuildConfig("At most 32 credential origins are supported")
  }
  let result : Array[CredentialBinding] = []
  fn variable(
    value : Json,
    field : String,
  ) -> CredentialVariable raise BuildError {
    guard config_optional_string(value, field) is Some(text) &&
      CredentialVariable::parse(text) is Some(name) else {
      raise InvalidBuildConfig(
        "Credential references must be literal environment variable names",
      )
    }
    name
  }
  for value in values {
    guard value is Object(fields) &&
      config_optional_string(value, "origin") is Some(origin) &&
      @resources.HttpOrigin::parse(origin) is Some(origin) else {
      raise InvalidBuildConfig(
        "Credential bindings require an HTTP(S) origin without path, query or user information",
      )
    }
    if result.any(binding => binding.origin == origin) {
      raise InvalidBuildConfig("Duplicate credential origin")
    }
    // Validate transport security at the same boundary as the library constructor.
    if !origin.permits_credentials() {
      raise InvalidBuildConfig(
        "Credentials require HTTPS, except for loopback fixture origins",
      )
    }
    let source = if fields.contains("bearerTokenEnv") && fields.length() == 2 {
      BearerEnvironment(variable(value, "bearerTokenEnv"))
    } else if fields.contains("usernameEnv") &&
      fields.contains("passwordEnv") &&
      fields.length() == 3 {
      BasicEnvironment(
        variable(value, "usernameEnv"),
        variable(value, "passwordEnv"),
      )
    } else {
      raise InvalidBuildConfig(
        "Expected only origin with bearerTokenEnv, or origin with usernameEnv and passwordEnv; literal secrets and mixed methods are unsupported",
      )
    }
    result.push({ origin, source, })
  }
  result
}

///|
/// Resolve secrets only at invocation time. The BuildConfig retains references.
pub fn BuildConfig::resolve_credentials(
  self : BuildConfig,
  environment : Map[String, String],
) -> @resources.Credentials raise BuildError {
  fn secret(name : CredentialVariable) -> String raise BuildError {
    guard environment.get(name.name) is Some(value) && !value.is_empty() else {
      raise InvalidBuildConfig(
        "A configured credential environment variable is missing or empty",
      )
    }
    value
  }
  let entries = self.credentials.map(binding => {
    let authorization = match binding.source {
      BearerEnvironment(name) => @resources.Authorization::bearer(secret(name))
      BasicEnvironment(user, password) =>
        @resources.Authorization::basic(secret(user), secret(password))
    }
    guard authorization is Some(authorization) else {
      raise InvalidBuildConfig("A configured credential has an invalid value")
    }
    (binding.origin, authorization)
  })
  @resources.Credentials::new(entries~).unwrap()
}
