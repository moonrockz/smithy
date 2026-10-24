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
  let ignore : ValueOptions = { unknown_members: Ignore, member_names: Smithy, }
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
