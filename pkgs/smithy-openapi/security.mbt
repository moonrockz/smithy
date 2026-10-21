///|
priv enum AuthScheme {
  Basic
  Bearer
  Digest
  ApiKey
} derive(Eq, Hash)

///|
fn AuthScheme::id(self : AuthScheme) -> @smithy.ShapeId {
  @smithy.ShapeId::parse(
    match self {
      Basic => "smithy.api#httpBasicAuth"
      Bearer => "smithy.api#httpBearerAuth"
      Digest => "smithy.api#httpDigestAuth"
      ApiKey => "smithy.api#httpApiKeyAuth"
    },
  ).unwrap()
}

///|
fn AuthScheme::component(self : AuthScheme) -> String {
  let id = self.id()
  id.namespace() + "." + id.name()
}

///|
fn Context::effective_auth(
  self : Context,
  subject : @smithy.Shape,
) -> Array[AuthScheme] {
  let available = [Basic, Bearer, Digest, ApiKey].filter(scheme => {
    self.service.traits.contains(scheme.id())
  })
  let auth = match subject.trait_value("smithy.api#auth") {
    Some(@smithy.Array(values)) => Some(values)
    _ if subject.id != self.service.id =>
      match self.service.trait_value("smithy.api#auth") {
        Some(@smithy.Array(values)) => Some(values)
        _ => None
      }
    _ => None
  }
  match auth {
    None => available
    Some(values) => {
      let selected : Set[@smithy.ShapeId] = Set([])
      for value in values {
        if value is @smithy.String(name) &&
          @smithy.ShapeId::parse(name) is Some(id) {
          selected.add(id)
        }
      }
      available.filter(scheme => selected.contains(scheme.id()))
    }
  }
}

///|
fn Context::security_requirements(
  self : Context,
  schemes : Array[AuthScheme],
) -> Json {
  Json::array(
    schemes.map(scheme => {
      self.auth_used.add(scheme)
      let requirement : Map[String, Json] = Map([])
      requirement[scheme.component()] = Json::array([])
      Json::object(requirement)
    }),
  )
}

///|
fn Context::operation_security(
  self : Context,
  operation : @smithy.Shape,
  fields : Map[String, Json],
) -> Unit {
  let effective = self.effective_auth(operation)
  if operation.trait_value("smithy.api#auth") == Some(@smithy.Array([])) ||
    effective != self.effective_auth(self.service) {
    fields["security"] = self.security_requirements(effective)
  }
}

///|
fn Context::security_schemes(
  self : Context,
) -> Map[String, Json] raise OpenApiError {
  let schemas : Map[String, Json] = Map([])
  for scheme in [Basic, Bearer, Digest, ApiKey] {
    if !self.auth_used.contains(scheme) {
      continue
    }
    let fields : Map[String, Json] = { "type": Json::string("http") }
    match scheme {
      Basic => {
        fields["scheme"] = Json::string("Basic")
        fields["description"] = Json::string("HTTP Basic authentication")
      }
      Bearer => {
        fields["scheme"] = Json::string("Bearer")
        fields["description"] = Json::string("HTTP Bearer authentication")
      }
      Digest => {
        fields["scheme"] = Json::string("Digest")
        fields["description"] = Json::string("HTTP Digest authentication")
      }
      ApiKey => {
        guard self.service.traits.get(scheme.id())
          is Some(@smithy.Object(trait_fields)) &&
          trait_fields.get("name") is Some(@smithy.String(name)) &&
          trait_fields.get("in") is Some(@smithy.String(location)) else {
          raise InvalidConfiguration(
            "HTTP API key authentication requires name and in",
          )
        }
        fields["type"] = Json::string("apiKey")
        fields["name"] = Json::string(name)
        fields["in"] = Json::string(location)
        fields["description"] = Json::string(
          "API key authentication via the '" +
          name +
          "' " +
          (if location == "query" {
            " query string parameter"
          } else {
            location
          }),
        )
        if trait_fields.get("scheme") is Some(@smithy.String(scheme_name)) {
          fields["type"] = Json::string("http")
          fields["scheme"] = Json::string(scheme_name)
        }
      }
    }
    schemas[scheme.component()] = Json::object(fields)
  }
  schemas
}
