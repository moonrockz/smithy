///|
fn fixture_suite(resolved_host~ : Bool = true) -> @protocoltests.Suite raise {
  let source =
    #|$version: "2"
    #|namespace example
    #|use smithy.test#httpRequestTests
    #|use smithy.test#httpResponseTests
    #|@trait @protocolDefinition structure FixtureProtocol {}
    #|@httpRequestTests([{id: "GreetingRequest", protocol: FixtureProtocol,
    #|  method: "POST", uri: "/greeting", host: "example.com", resolvedHost: "api.example.com",
    #|  params: {name: "Ada"}, queryParams: ["a=1", "a=2", "flag"],
    #|  requireQueryParams: ["token"], forbidQueryParams: ["secret"],
    #|  headers: {"X-Names": "Ada, Lin"}, requireHeaders: ["X-Token"], forbidHeaders: ["X-Secret"],
    #|  body: "{\"name\":\"Ada\",\"id\":9007199254740993}", bodyMediaType: "application/json", appliesTo: "client"}])
    #|@httpResponseTests([{id: "GreetingResponse", protocol: FixtureProtocol, code: 201,
    #|  params: {greeting: "Hello"}, headers: {"X-Answer": "yes"}}])
    #|operation Greet { input: Input, output: Output, errors: [BadName] }
    #|structure Input { @required name: String }
    #|structure Output { greeting: String }
    #|@error("client")
    #|@httpResponseTests([{id: "BadNameResponse", protocol: FixtureProtocol, code: 400,
    #|  params: {message: "bad"}, body: "", appliesTo: "server"}])
    #|structure BadName { message: String }
  let source = if resolved_host {
    source
  } else {
    source.replace_all(old="resolvedHost: \"api.example.com\",", new="")
  }
  let loaded = @protocoltests.loader()
    .add_idl("fixture.smithy", source)
    .assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.validation_events().map(e => e.message).join("\n"))
  }
  @protocoltests.Suite::from_model(model)
}

///|
fn case_named(id : String) -> @protocoltests.Case raise {
  fixture_suite().cases().filter(c => c.id().to_string() == id)[0]
}

///|
struct Fixture {
  message : @protocoltests.HttpMessage
}

///|
impl @protocoltests.Protocol for Fixture with fn produce(self, _case) {
  self.message
}

///|
test "a fixture protocol receives one typed case and matches a request" {
  let case_ = case_named("GreetingRequest")
  assert_eq(case_.protocol().to_string(), "example#FixtureProtocol")
  assert_true(
    case_.subject() is Request(operation~, input~) &&
    operation.to_string() == "example#Greet" &&
    input.to_string() == "example#Input",
  )
  assert_true(
    case_.params() is Object(fields) &&
    fields.get("name") == Some(String("Ada")),
  )
  let message = @protocoltests.HttpMessage::Request(
    verb="POST",
    uri="/greeting",
    host=Some("api.example.com"),
    query=["a=2", "token=anything", "a=1", "flag", "extra=allowed"],
    headers=[
      ("x-names", "Ada"),
      ("X-Names", "Lin"),
      ("x-token", "any"),
      ("Extra", "allowed"),
    ],
    body=b"{\"id\":9007199254740993, \"name\": \"Ada\"}",
  )
  assert_eq(
    @protocoltests.run(Fixture::{ message, }, case_, side=Client),
    Matched,
  )
  assert_eq(
    @protocoltests.run(Fixture::{ message, }, case_, side=Server),
    Skipped,
  )
  assert_eq(fixture_suite().cases().length(), 3)
}

///|
test "all request fields report structured differences" {
  let case_ = case_named("GreetingRequest")
  let message = @protocoltests.HttpMessage::Request(
    verb="GET",
    uri="/other",
    host=None,
    query=["a=1", "flag=", "secret=hidden"],
    headers=[("X-Names", "wrong"), ("x-secret", "")],
    body=b"{\"name\":\"Ada\",\"id\":9007199254740992}",
  )
  guard case_.compare(message) is Mismatched(differences) else {
    fail("Expected field differences")
  }
  let fields = differences.map(d => d.field)
  for
    wanted in [
      @protocoltests.Method,
      Uri,
      Host,
      QueryParameter("a"),
      QueryParameter("flag"),
      ForbiddenQueryParameter("secret"),
      RequiredQueryParameter("token"),
      Header("X-Names"),
      ForbiddenHeader("X-Secret"),
      RequiredHeader("X-Token"),
      Body,
    ] {
    assert_true(fields.contains(wanted))
  }
  assert_eq(fields.length(), 11)
}

///|
test "missing body asserts nothing while empty body asserts empty bytes" {
  let success = case_named("GreetingResponse")
  let response = @protocoltests.HttpMessage::Response(
    code=201,
    headers=[("x-answer", "yes")],
    body=b"arbitrary bytes",
  )
  assert_eq(success.compare(response), Matched)
  assert_true(
    success.compare(
      @protocoltests.HttpMessage::Response(code=200, headers=[], body=b""),
    )
    is Mismatched(ds) &&
    ds.iter().any(d => d.field == Status),
  )
  let error_ = case_named("BadNameResponse")
  assert_true(
    error_.subject() is ErrorResponse(error~) &&
    error.to_string() == "example#BadName",
  )
  assert_eq(
    error_.compare(
      @protocoltests.HttpMessage::Response(code=400, headers=[], body=b""),
    ),
    Matched,
  )
  assert_true(
    error_.compare(
      @protocoltests.HttpMessage::Response(
        code=400,
        headers=[],
        body=b"unexpected",
      ),
    )
    is Mismatched(ds) &&
    ds.map(d => d.field) == [Body],
  )
  assert_true(
    error_.compare(
      @protocoltests.HttpMessage::Request(
        verb="GET",
        uri="/",
        host=None,
        query=[],
        headers=[],
        body=b"",
      ),
    )
    is Mismatched(ds) &&
    ds.map(d => d.field) == [MessageKind],
  )
}

///|
test "body comparison preserves exact JSON values and supports binary and custom formats" {
  assert_true(
    @protocoltests.default_body_matches(
      "1.00",
      b"1",
      Some("application/json; charset=utf-8"),
    ),
  )
  assert_false(
    @protocoltests.default_body_matches(
      "9007199254740993",
      b"9007199254740992",
      Some("application/problem+json"),
    ),
  )
  assert_false(
    @protocoltests.default_body_matches(
      "{}",
      b"not json",
      Some("application/json"),
    ),
  )
  assert_true(
    @protocoltests.default_body_matches(
      "AP8=",
      b"\x00\xff",
      Some("application/octet-stream"),
    ),
  )
  assert_true(
    @protocoltests.default_body_matches("text", b"text", Some("text/plain")),
  )
  assert_false(@protocoltests.default_body_matches("text", b"TEXT", None))
  let case_ = case_named("BadNameResponse")
  assert_eq(
    case_.compare(
      @protocoltests.HttpMessage::Response(code=400, headers=[], body=b"custom"),
      body_matches=(_, _, _) => true,
    ),
    Matched,
  )
  assert_true(@protocoltests.CaseId::parse("invalid-id") is None)
}

///|
suberror FixtureFailure {
  Broken
}

///|
struct BrokenFixture {}

///|
impl @protocoltests.Protocol for BrokenFixture with fn produce(_self, _case) {
  raise Broken
}

///|
test "adapter failures are findings and skipped cases never invoke the adapter" {
  let case_ = case_named("GreetingRequest")
  assert_eq(@protocoltests.run(BrokenFixture::{ }, case_, side=Server), Skipped)
  assert_true(
    @protocoltests.run(BrokenFixture::{ }, case_, side=Client) is Mismatched(ds) &&
    ds.map(d => d.field) == [Implementation],
  )
}

///|
test "input host configures the adapter without asserting a resolved host" {
  let case_ = fixture_suite(resolved_host=false)
    .cases()
    .filter(c => c.id().to_string() == "GreetingRequest")[0]
  let message = @protocoltests.HttpMessage::Request(
    verb="POST",
    uri="/greeting",
    host=Some("prefix.example.com"),
    query=["a=1", "a=2", "flag", "token"],
    headers=[("X-Names", "Ada, Lin"), ("X-Token", "")],
    body=b"{\"name\":\"Ada\",\"id\":9007199254740993}",
  )
  assert_eq(case_.compare(message), Matched)
  if case_.definition() is Object(fields) {
    fields["body"] = String("mutated")
  }
  assert_eq(case_.compare(message), Matched)
}

///|
test "a caller cannot replace standard traits with a weaker definition" {
  let loaded = @smithy.Loader::new()
    .add_idl(
      "weak.smithy", "$version: \"2\"\nnamespace smithy.test\n@trait(selector: \"operation\") document httpRequestTests",
    )
    .add_idl(
      "input.smithy", "$version: \"2\"\nnamespace example\n@trait @protocolDefinition structure Protocol {}\n@smithy.test#httpRequestTests([{id: \"MissingMethod\", protocol: Protocol}])\noperation Test {}",
    )
    .assemble()
  let rejected = try {
    ignore(@protocoltests.Suite::from_model(loaded.model.unwrap()))
    false
  } catch {
    @protocoltests.InvalidSuite(_) => true
  }
  assert_true(rejected)
}
