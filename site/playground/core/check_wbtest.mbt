///|
/// The model of `examples/validation-consumer/main.mbtx`.
let consumer : String =
  #|$version: "2"
  #|namespace example
  #|@range(min: 1, max: 100)
  #|integer Count
  #|structure Input { @required count: Count }

///|
fn check(
  value : String,
  shape~ : String = "example#Input",
  options~ : ValueOptions = ValueOptions::default(),
  model~ : String = consumer,
) -> Response {
  handle(
    Session::new(),
    CheckValue(
      seq=3,
      files=[("example.smithy", model)],
      shape~,
      value~,
      options~,
    ),
  )
}

///|
fn findings_of(response : Response) -> Array[DataFinding] raise {
  match response {
    DataChecked(findings~, ..) => findings
    other =>
      fail(
        "I expected DataChecked, but found \{@json.to_json(other).stringify()}",
      )
  }
}

///|
fn valid_of(response : Response) -> Bool raise {
  match response {
    DataChecked(valid~, ..) => valid
    other =>
      fail(
        "I expected DataChecked, but found \{@json.to_json(other).stringify()}",
      )
  }
}

///|
test "a valid value gives no finding" {
  assert_true(
    check("{\"count\":2}") is DataChecked(seq=3, valid=true, findings=[]),
  )
}

///|
test "a value out of range gives a Range finding at /count" {
  guard check("{\"count\":0}")
    is DataChecked(valid=false, findings=[finding], ..) else {
    fail("I expected one finding")
  }
  guard finding
    is Found(code="Range", severity="error", path="/count", offset=None, ..) else {
    fail(
      "I expected a Range finding at /count, but found \{@json.to_json(finding).stringify()}",
    )
  }
  assert_true(
    finding
    .cli_line(file="value.json")
    .has_prefix("value.json/count: error[Range] "),
  )
}

///|
test "a missing target stops with InvalidTarget at --shape" {
  guard check("{}", shape="example#Missing")
    is DataChecked(valid=false, findings=[finding], ..) else {
    fail("I expected one finding")
  }
  assert_eq(
    finding.cli_line(file="value.json"),
    "--shape: error[InvalidTarget]: example#Missing: I expected an existing data shape or data member as the validation target.",
  )
}

///|
test "text that is not JSON stops with InvalidJson and its offset" {
  guard check("{\"count\":") is DataChecked(valid=false, findings=[finding], ..) else {
    fail("I expected one finding")
  }
  guard finding is Stopped(code="InvalidJson", source=None, offset=Some(_), ..) else {
    fail(
      "I expected InvalidJson with an offset, but found \{@json.to_json(finding).stringify()}",
    )
  }
  assert_true(
    finding
    .cli_line(file="value.json")
    .has_prefix("value.json: error[InvalidJson]: "),
  )
}

///|
test "a duplicate key stops with DuplicateJsonKey" {
  guard check("{\"count\":2,\"count\":3}")
    is DataChecked(valid=false, findings=[finding], ..) else {
    fail("I expected one finding")
  }
  guard finding
    is Stopped(code="DuplicateJsonKey", message~, source=None, offset=Some(_)) else {
    fail(
      "I expected DuplicateJsonKey, but found \{@json.to_json(finding).stringify()}",
    )
  }
  assert_eq(
    message, "I expected unique JSON object member names, but found a duplicate.",
  )
}

///|
test "the unknown-members option is applied" {
  let value = "{\"count\":2,\"extra\":1}"
  guard findings_of(check(value)) is [finding] else {
    fail("I expected one finding")
  }
  guard finding is Found(code="UnknownMember", path="/extra", ..) else {
    fail(
      "I expected UnknownMember at /extra, but found \{@json.to_json(finding).stringify()}",
    )
  }
  let ignore : ValueOptions = {
    unknown_members: Ignore,
    member_names: Smithy,
    profile: None,
  }
  assert_true(check(value, options=ignore) is DataChecked(valid=true, ..))
}

///|
test "the member-names option is applied" {
  let model =
    #|$version: "2"
    #|namespace example
    #|structure Input { @required @jsonName("n") count: Integer }
  let value = "{\"n\":2}"
  assert_false(valid_of(check(value, model~)))
  let json_names : ValueOptions = {
    unknown_members: Reject,
    member_names: JsonName,
    profile: None,
  }
  assert_true(valid_of(check(value, model~, options=json_names)))
}

///|
test "a model with errors is blocked as a transform is" {
  let model =
    #|$version: "2"
    #|namespace example
    #|structure Input { x: Missing }
  assert_eq(blocked_kind(check("{}", model~)), ModelErrors)
}

///|
test "a shape that is not a shape ID is blocked" {
  let response = check("{}", shape="Input")
  assert_eq(blocked_kind(response), Other)
  assert_eq(
    blocked_reason(response),
    "I expected an absolute shape ID for the shape, but found 'Input'.",
  )
}

///|
test "a value check survives the Worker JSON" {
  let request = CheckValue(
    seq=3,
    files=[("example.smithy", consumer)],
    shape="example#Input",
    value="{\"count\":0,\"extra\":1}",
    options=ValueOptions::default(),
  )
  let session = Session::new()
  let text = handle_json(session, @json.to_json(request).stringify())
  let response : Response = @json.from_json(@json.parse(text))
  assert_eq(response, handle(session, request))
  assert_eq(findings_of(response).length(), 2)
}

///|
test "cli_line gives the offset of a Found after the file" {
  assert_eq(
    Found(
      code="InvalidJson",
      severity="error",
      path="",
      shape="example#Calculator",
      message="m",
      offset=Some(1),
    ).cli_line(file="bad.json"),
    "bad.json:1: error[InvalidJson] example#Calculator: m",
  )
}

///|
test "cli_line names the input file of a Stopped with no source" {
  assert_eq(
    Stopped(code="InvalidJson", message="m", source=None, offset=Some(9)).cli_line(
      file="value.json",
    ),
    "value.json: error[InvalidJson]: m",
  )
}

///|
/// The text of `examples/json-rpc/calculator.smithy`.
let calculator : String =
  #|$version: "2"
  #|namespace example
  #|
  #|use smithy.rpc#jsonRpc
  #|use smithy.rpc#method
  #|
  #|@jsonRpc(versions: ["1.0", "2.0"])
  #|service Calculator {
  #|    version: "1"
  #|    operations: [Subtract, Ping]
  #|}
  #|
  #|@method(name: "subtract", params: "either",
  #|    positional: ["minuend", "subtrahend"], resultMember: "value")
  #|operation Subtract { input: SubtractInput, output: SubtractOutput }
  #|
  #|structure SubtractInput {
  #|    @required
  #|    minuend: Integer
  #|    @required
  #|    subtrahend: Integer
  #|}
  #|
  #|structure SubtractOutput { value: Integer }
  #|
  #|@method(name: "ping", params: "either", positional: [], nullResult: true)
  #|operation Ping {}

///|
/// The text of `examples/json-rpc/responses.smithy`.
let responses : String =
  #|$version: "2"
  #|namespace example
  #|
  #|use smithy.rpc#jsonRpc
  #|use smithy.rpc#method
  #|use smithy.rpc#rpcError
  #|
  #|@jsonRpc(versions: ["1.0", "2.0"])
  #|service Replies {
  #|    version: "1"
  #|    operations: [Subtract, GetData, GetObject, Ping, Echo, PostMessage]
  #|}
  #|
  #|@method(name: "subtract", params: "either",
  #|    positional: ["minuend", "subtrahend"], resultMember: "value")
  #|operation Subtract { input: SubtractInput, output: SubtractOutput, errors: [Problem] }
  #|structure SubtractInput { @required minuend: Integer, @required subtrahend: Integer }
  #|structure SubtractOutput { @range(min: -20, max: 20) value: Integer }
  #|
  #|@error("client")
  #|@rpcError(code: 1001, dataMember: "detail")
  #|structure Problem { @required @length(min: 2) detail: String }
  #|
  #|@method(name: "get_data", params: "either", positional: [], resultMember: "items")
  #|operation GetData { output: DataOutput }
  #|list Items { member: Document }
  #|structure DataOutput { @length(min: 2) items: Items }
  #|
  #|@method(name: "get_object", params: "either", positional: [])
  #|operation GetObject { output: ObjectOutput }
  #|structure ObjectOutput { @required count: Integer }
  #|
  #|@method(name: "ping", params: "either", positional: [], nullResult: true)
  #|operation Ping {}
  #|
  #|@method(name: "echo", params: "either", positional: ["message"], resultMember: "message")
  #|operation Echo { input: EchoInput, output: EchoOutput }
  #|structure EchoInput { @required message: String }
  #|structure EchoOutput { message: String }
  #|
  #|@method(name: "postMessage", params: "either", positional: ["message"], resultMember: "value")
  #|operation PostMessage { input: EchoInput, output: PostOutput }
  #|structure PostOutput { value: Integer }

///|
/// The text of `examples/json-rpc/call.json`: its id is above 2^53.
let call : String =
  #|{"jsonrpc":"2.0","method":"subtract","params":[42,23],"id":9007199254740993}

///|
/// A response check against `example#Replies`, as
/// `smithy validate rpc --response`.
fn reply(message : String, context : ResponseContext?) -> CheckMessage {
  {
    model: responses,
    service: "example#Replies",
    version: V2_0,
    message,
    kind: ResponseMessage(context~, legacy_errors=None),
  }
}

///|
/// The inputs of a message check, for the tests.
struct CheckMessage {
  model : String
  service : String
  version : RpcVersion
  message : String
  kind : MessageKind
}

///|
fn CheckMessage::request(self : CheckMessage) -> Request {
  CheckMessage(
    seq=4,
    files=[("example.smithy", self.model)],
    service=self.service,
    version=self.version,
    message=self.message,
    kind=self.kind,
    options=ValueOptions::default(),
  )
}

///|
fn CheckMessage::run(self : CheckMessage) -> Response {
  handle(Session::new(), self.request())
}

///|
/// A request check against `example#Calculator`, as
/// `smithy validate rpc --message`.
fn call_of(message : String) -> CheckMessage {
  {
    model: calculator,
    service: "example#Calculator",
    version: V2_0,
    message,
    kind: RequestMessage,
  }
}

///|
fn only_finding(response : Response) -> DataFinding raise {
  guard findings_of(response) is [finding] else {
    fail(
      "I expected one finding, but found \{@json.to_json(response).stringify()}",
    )
  }
  finding
}

///|
test "the call of examples/json-rpc is valid" {
  assert_true(
    call_of(call).run() is DataChecked(seq=4, valid=true, findings=[]),
  )
}

///|
test "invalid params give TypeMismatch at /params/1" {
  let response = call_of(
    "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[42,\"23\"],\"id\":1}",
  ).run()
  assert_false(valid_of(response))
  assert_eq(
    only_finding(response).cli_line(file="invalid.json"),
    "invalid.json/params/1: error[TypeMismatch] example#SubtractInput$subtrahend: I expected a integer value, but found string.",
  )
}

///|
test "a response keeps the exact id of a large integer" {
  let context : ResponseContext? = Some(OriginalRequest(call))
  assert_true(
    reply(
      "{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":9007199254740993}", context,
    ).run()
    is DataChecked(valid=true, findings=[], ..),
  )
  let response = reply(
    "{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":9007199254740992}", context,
  ).run()
  assert_false(valid_of(response))
  guard only_finding(response) is Found(code="IdMismatch", ..) else {
    fail("I expected IdMismatch")
  }
}

///|
test "a result out of range gives Range at /result" {
  let response = reply(
    "{\"jsonrpc\":\"2.0\",\"result\":21,\"id\":1}",
    Some(Method("subtract")),
  ).run()
  assert_false(valid_of(response))
  guard only_finding(response)
    is Found(
      code="Range",
      severity="error",
      path="/result",
      shape="example#SubtractOutput$value",
      offset=None,
      ..
    ) else {
    fail("I expected Range at /result")
  }
}

///|
test "an operation context checks the result of the operation" {
  let response = reply(
    "{\"jsonrpc\":\"2.0\",\"result\":21,\"id\":1}",
    Some(Operation("example#Subtract")),
  ).run()
  guard only_finding(response) is Found(code="Range", path="/result", ..) else {
    fail("I expected Range at /result")
  }
}

///|
test "an envelope-only context checks the envelope only" {
  assert_true(
    reply("{\"jsonrpc\":\"2.0\",\"result\":21,\"id\":1}", Some(EnvelopeOnly)).run()
    is DataChecked(valid=true, ..),
  )
}

///|
test "a message that is not JSON gives InvalidJson with its offset" {
  let finding = only_finding(call_of("{").run())
  guard finding
    is Found(code="InvalidJson", shape="example#Calculator", offset=Some(_), ..) else {
    fail(
      "I expected InvalidJson with an offset, but found \{@json.to_json(finding).stringify()}",
    )
  }
  assert_true(finding.cli_line(file="bad.json").has_prefix("bad.json:"))
}

///|
test "a missing service stops with InvalidContract at --service" {
  let response = { ..call_of(call), service: "example#Nope", }.run()
  assert_false(valid_of(response))
  assert_eq(
    only_finding(response),
    Stopped(
      code="InvalidContract",
      message="example#Nope: I expected an existing service shape.",
      source=Some("--service"),
      offset=None,
    ),
  )
  assert_eq(
    only_finding(response).cli_line(file="call.json"),
    "--service: error[InvalidContract]: example#Nope: I expected an existing service shape.",
  )
}

///|
test "a response without context gives the findings of the library" {
  let message = "{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":1}"
  let loaded = load([("example.smithy", responses)])
  let service = @rpc.PreparedService::prepare(
    loaded.model.unwrap(),
    @smithy.ShapeId::parse("example#Replies").unwrap(),
    @rpc.V2_0,
  )
  let expected = service.validate_response(message)
  assert_false(expected.findings.is_empty())
  let response = reply(message, None).run()
  assert_eq(findings_of(response), expected.findings.map(rpc_found_of))
  assert_eq(valid_of(response), expected.is_valid())
}

///|
test "code-message-data with version 2.0 is blocked" {
  let response = {
    ..reply(call, None),
    kind: ResponseMessage(context=None, legacy_errors=Some(CodeMessageData)),
  }.run()
  assert_eq(blocked_kind(response), Other)
  assert_eq(blocked_reason(response), "--legacy-errors requires version 1.0")
}

///|
test "an explicit opaque with version 2.0 is blocked" {
  let response = {
    ..reply(call, None),
    kind: ResponseMessage(context=None, legacy_errors=Some(Opaque)),
  }.run()
  assert_eq(blocked_kind(response), Other)
  assert_eq(blocked_reason(response), "--legacy-errors requires version 1.0")
}

///|
test "no legacy error mapping with version 2.0 runs" {
  assert_true(
    reply(
      "{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":1}",
      Some(Method("subtract")),
    ).run()
    is DataChecked(valid=true, findings=[], ..),
  )
}

///|
test "code-message-data with version 1.0 maps the error" {
  let error = "{\"result\":null,\"error\":{\"code\":1001,\"message\":\"failure\",\"data\":1},\"id\":1}"
  let check = {
    ..reply(error, Some(Method("subtract"))),
    version: V1_0,
    kind: ResponseMessage(
      context=Some(Method("subtract")),
      legacy_errors=Some(CodeMessageData),
    ),
  }
  guard only_finding(check.run())
    is Found(code="TypeMismatch", path="/error/data", ..) else {
    fail("I expected TypeMismatch at /error/data")
  }
  assert_true(
    {
      ..check,
      kind: ResponseMessage(
        context=Some(Method("subtract")),
        legacy_errors=Some(Opaque),
      ),
    }.run()
    is DataChecked(valid=true, ..),
  )
}

///|
test "a method name that the CLI rejects is blocked" {
  let response = reply(call, Some(Method("rpc.x"))).run()
  assert_eq(blocked_kind(response), Other)
  assert_eq(
    blocked_reason(response),
    "I expected an application method name, but found 'rpc.x'.",
  )
}

///|
test "an operation ID with a member is blocked" {
  let response = reply(call, Some(Operation("example#Subtract$x"))).run()
  assert_eq(blocked_kind(response), Other)
  assert_eq(
    blocked_reason(response),
    "I expected an absolute operation ID, but found 'example#Subtract$x'.",
  )
}

///|
test "a service that is not a shape ID is blocked" {
  let response = { ..call_of(call), service: "Calculator", }.run()
  assert_eq(blocked_kind(response), Other)
  assert_eq(
    blocked_reason(response),
    "I expected an absolute shape ID for the service, but found 'Calculator'.",
  )
}

///|
test "a message check with a model error is blocked" {
  let model =
    #|$version: "2"
    #|namespace example
    #|structure Input { x: Missing }
  assert_eq(blocked_kind({ ..call_of(call), model, }.run()), ModelErrors)
}

///|
test "a message check survives the Worker JSON" {
  let request = reply(
    "{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":9007199254740992}",
    Some(OriginalRequest(call)),
  ).request()
  let session = Session::new()
  let text = handle_json(session, @json.to_json(request).stringify())
  let response : Response = @json.from_json(@json.parse(text))
  assert_eq(response, handle(session, request))
  guard only_finding(response) is Found(code="IdMismatch", ..) else {
    fail("I expected IdMismatch")
  }
}

///|
test "a bad service ID is blocked before the model loads" {
  let model =
    #|$version: "2"
    #|namespace example
    #|structure Input { x: Missing }
  let response = { ..call_of(call), model, service: "Calculator", }.run()
  assert_eq(blocked_kind(response), Other)
  assert_eq(
    blocked_reason(response),
    "I expected an absolute shape ID for the service, but found 'Calculator'.",
  )
}

///|
test "a bad response option is blocked before the model loads" {
  let model =
    #|$version: "2"
    #|namespace example
    #|structure Input { x: Missing }
  let response = { ..reply(call, Some(Method("rpc.x"))), model, }.run()
  assert_eq(blocked_kind(response), Other)
  assert_eq(
    blocked_reason(response),
    "I expected an application method name, but found 'rpc.x'.",
  )
}

///|
test "a bad shape ID is blocked before the model loads" {
  let model =
    #|$version: "2"
    #|namespace example
    #|structure Input { x: Missing }
  let response = check("{}", shape="Input", model~)
  assert_eq(blocked_kind(response), Other)
  assert_eq(
    blocked_reason(response),
    "I expected an absolute shape ID for the shape, but found 'Input'.",
  )
}

///|
/// A model with a serialization profile and a Morphir name adapter.
let profile_model : String =
  #|$version: "2"
  #|namespace example
  #|use smithy.serialization#jsonEncoding
  #|use smithy.serialization#jsonProfiles
  #|@jsonProfiles([{id: "array", defaults: {union: {style: "tagArray"}}}])
  #|union Expr {
  #|  Name: Name
  #|  Count: Integer
  #|}
  #|@jsonEncoding(base: {adapter: "morphir.v4.name"})
  #|string Name

///|
fn with_profile(profile : String) -> ValueOptions {
  { ..ValueOptions::default(), profile: Some(profile), }
}

///|
test "a profile reads the value with the declared representation and the Morphir adapters" {
  let shape = "example#Expr"
  assert_true(
    valid_of(
      check(
        "[\"Name\", [\"value\", \"in\", \"u\", \"s\", \"d\"]]",
        shape~,
        model=profile_model,
        options=with_profile("array"),
      ),
    ),
  )
  let refused = findings_of(
    check(
      "[\"Name\", \"value-in-Usd\"]",
      shape~,
      model=profile_model,
      options=with_profile("array"),
    ),
  )
  assert_eq(refused.length(), 1)
  assert_true(
    refused[0]
    is Found(code="AdapterFailure", path="/1", shape="example#Name", ..),
  )
  // Without a profile, the plain value check reads the object layout.
  assert_false(valid_of(check("[\"Count\", 1]", shape~, model=profile_model)))
}

///|
test "an unknown profile stops the check at --profile" {
  let findings = findings_of(
    check(
      "[\"Count\", 1]",
      shape="example#Expr",
      model=profile_model,
      options=with_profile("tree"),
    ),
  )
  assert_true(
    findings is [Stopped(code="UnknownProfile", source=Some("--profile"), ..)],
  )
}

///|
test "options without a profile keep their JSON" {
  assert_eq(
    @json.to_json(ValueOptions::default()).stringify(),
    "{\"unknown_members\":\"Reject\",\"member_names\":\"Smithy\"}",
  )
  let options = with_profile("array")
  let back : ValueOptions = @json.from_json(@json.to_json(options))
  assert_eq(back, options)
}
