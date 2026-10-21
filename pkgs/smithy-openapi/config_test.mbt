///|
test "service and protocol identities reject relative IDs and member shapes" {
  for
    text in [
      "Service", "example#", "example#Service$member", "example#Service/other",
    ] {
    assert_true(@openapi.ServiceId::parse(text) is None)
    assert_true(@openapi.ProtocolId::parse(text) is None)
  }
  let service = @openapi.ServiceId::parse("example#Service").unwrap()
  assert_eq(
    service.shape_id(),
    @smithy.ShapeId::parse("example#Service").unwrap(),
  )
  assert_eq(service.to_string(), "example#Service")
  assert_eq(
    @openapi.ProtocolId::parse("aws.protocols#restJson1").unwrap().to_string(),
    "aws.protocols#restJson1",
  )
}

///|
test "OpenAPI configuration selects an exact supported document version" {
  let config = @openapi.Config::from_json(
    @json.parse(
      "{\"service\":\"example#Service\",\"version\":\"3.1.0\",\"onHttpPrefixHeaders\":\"WARN\"}",
    ),
  )
  assert_eq(config.service().to_string(), "example#Service")
  assert_eq(config.version(), @openapi.V3_1_0)
  let defaults = @openapi.Config::new(
    @openapi.ServiceId::parse("example#Service").unwrap(),
  )
  assert_eq(defaults.version(), @openapi.V3_0_2)
}

///|
test "malformed plugin settings fail at the configuration boundary" {
  for
    text in [
      "null", "{}", "{\"service\":\"example#Service$member\"}", "{\"service\":\"example#Service\",\"version\":\"3.0.0\"}",
      "{\"service\":\"example#Service\",\"tags\":\"true\"}", "{\"service\":\"example#Service\",\"protocol\":\"relative\"}",
      "{\"service\":\"example#Service\",\"supportedTags\":[false]}", "{\"service\":\"example#Service\",\"onHttpPrefixHeaders\":\"IGNORE\"}",
    ] {
    let failed = try @openapi.Config::from_json(@json.parse(text)) catch {
      @openapi.InvalidConfiguration(_) => true
      _ => false
    } noraise {
      _ => false
    }
    assert_true(failed, msg=text)
  }
}
