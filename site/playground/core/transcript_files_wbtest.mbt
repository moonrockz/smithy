///|
/// The model of lesson 28: a weather service that a client calls and that
/// sends alerts.
const WEATHER_MODEL : String =
  #|$version: "2"
  #|namespace example
  #|
  #|use smithy.rpc#jsonRpc
  #|use smithy.rpc#jsonRpcProtocol
  #|use smithy.rpc#method
  #|
  #|@jsonRpcProtocol(
  #|    versions: ["2.0"]
  #|    peers: [
  #|        { name: "client", accepts: WeatherClient }
  #|        { name: "server", accepts: WeatherServer }
  #|    ]
  #|)
  #|structure WeatherProtocol {}
  #|
  #|@jsonRpc(versions: ["2.0"])
  #|service WeatherServer {
  #|    version: "1"
  #|    operations: [GetWeather]
  #|}
  #|
  #|@jsonRpc(versions: ["2.0"])
  #|service WeatherClient {
  #|    version: "1"
  #|    operations: [Alert]
  #|}
  #|
  #|@method(name: "weather/get", params: "named", resultMember: "forecast")
  #|operation GetWeather { input: GetWeatherInput, output: GetWeatherOutput }
  #|
  #|structure GetWeatherInput { @required city: String }
  #|
  #|structure GetWeatherOutput { forecast: String }
  #|
  #|@method(name: "weather/alert", params: "named", nullResult: true)
  #|operation Alert { input: AlertInput }
  #|
  #|structure AlertInput { text: String }

///|
const WEATHER_EXCHANGE : String =
  #|{
  #|  "version": "2.0",
  #|  "complete": true,
  #|  "entries": [
  #|    {"from": "client", "message": {"jsonrpc": "2.0", "id": 1, "method": "weather/get", "params": {"city": "Oslo"}}},
  #|    {"from": "server", "message": {"jsonrpc": "2.0", "method": "weather/alert", "params": {"text": "Wind"}}},
  #|    {"from": "server", "message": {"jsonrpc": "2.0", "id": 1, "result": "Rain"}}
  #|  ]
  #|}

///|
const WEATHER_PROTOCOL : String = "example#WeatherProtocol"

///|
fn start_files(
  session : Session,
  text : String,
  files~ : Array[(String, String)] = [("model.smithy", WEATHER_MODEL)],
  protocol~ : String = WEATHER_PROTOCOL,
) -> Response {
  handle(
    session,
    TranscriptStartFiles(
      seq=1,
      files~,
      protocol~,
      format=Json,
      complete=false,
      text~,
    ),
  )
}

///|
/// The findings of the start and of a run to the end, and the summary.
fn run_files(
  text : String,
) -> (Array[FindingView], Array[FindingView], SummaryView?) raise {
  let session = Session::new()
  let first = match start_files(session, text) {
    TranscriptProgress(findings~, ..) => findings
    other => fail(@json.to_json(other).stringify())
  }
  match handle(session, TranscriptStep(seq=2, count=100)) {
    TranscriptProgress(findings~, summary~, ..) => (first, findings, summary)
    other => fail(@json.to_json(other).stringify())
  }
}

///|
fn lines_of(
  findings : Array[FindingView],
  file~ : String = "exchange.json",
) -> Array[String] {
  findings.map(finding => finding.cli_line(file~))
}

///|
test "a valid exchange gives no finding and a valid summary" {
  let (first, rest, summary) = run_files(WEATHER_EXCHANGE)
  assert_eq(first, [])
  assert_eq(rest, [])
  let summary = summary.unwrap()
  assert_true(summary.valid)
  assert_eq(summary.entries, 3)
  assert_eq(summary.outstanding, 0)
}

///|
test "a start checks no entry yet" {
  let session = Session::new()
  match start_files(session, WEATHER_EXCHANGE) {
    TranscriptProgress(entries~, findings~, checked~, ..) => {
      assert_eq(checked, 0)
      assert_eq(entries.length(), 3)
      assert_eq(findings, [])
    }
    other => fail(@json.to_json(other).stringify())
  }
}

///|
const NO_REPLY : String =
  #|{
  #|  "version": "2.0",
  #|  "complete": true,
  #|  "entries": [
  #|    {"from": "client", "message": {"jsonrpc": "2.0", "id": 1, "method": "weather/get", "params": {"city": "Oslo"}}},
  #|    {"from": "server", "message": {"jsonrpc": "2.0", "method": "weather/alert", "params": {"text": "Wind"}}}
  #|  ]
  #|}

///|
test "a missing reply is MissingResponse when the last entry is read" {
  let session = Session::new()
  ignore(start_files(session, NO_REPLY))
  match handle(session, TranscriptStep(seq=2, count=1)) {
    TranscriptProgress(findings~, ..) => assert_eq(findings, [])
    other => fail(@json.to_json(other).stringify())
  }
  match handle(session, TranscriptStep(seq=3, count=100)) {
    TranscriptProgress(findings~, ..) =>
      assert_eq(lines_of(findings), [
        "exchange.json:5:35: entry 0 client: error MissingResponse: I expected a reply from server to entry 0 from client with id 1; the complete transcript has none.",
      ])
    other => fail(@json.to_json(other).stringify())
  }
}

///|
test "each case gives the CLI lines" {
  let partial = NO_REPLY.replace(
    old="\"complete\": true",
    new="\"complete\": false",
  )
  let (_, rest, summary) = run_files(partial)
  assert_eq(lines_of(rest), [
    "exchange.json:5:35: entry 0 client: advisory OutstandingCall: I found no reply yet from server to entry 0 from client with id 1; the transcript is partial.",
  ])
  assert_true(summary.unwrap().valid)
  let wrong_id = WEATHER_EXCHANGE.replace(
    old="\"id\": 1, \"result\"",
    new="\"id\": 2, \"result\"",
  )
  let (_, rest, _) = run_files(wrong_id)
  assert_eq(lines_of(rest), [
    "exchange.json:7:35: entry 2 server: error UnsolicitedResponse: I expected a reply to an active call from client; entry 2 from server sent id 2, which matches no call.",
    "exchange.json:5:35: entry 0 client: error MissingResponse: I expected a reply from server to entry 0 from client with id 1; the complete transcript has none.",
  ])
  let wrong_sender = WEATHER_EXCHANGE.replace(
    old="{\"from\": \"server\", \"message\": {\"jsonrpc\": \"2.0\", \"method\"",
    new="{\"from\": \"client\", \"message\": {\"jsonrpc\": \"2.0\", \"method\"",
  )
  let (_, rest, _) = run_files(wrong_sender)
  assert_eq(lines_of(rest), [
    "exchange.json:6:35: entry 1 client: error UnknownMethod: I expected a method declared by the selected service, but found weather/alert.",
  ])
}

///|
test "text that is not JSON gives InvalidTranscript at 1:1" {
  let session = Session::new()
  let text = WEATHER_EXCHANGE[:119].to_owned()
  match start_files(session, text) {
    TranscriptProgress(findings~, ..) =>
      assert_eq(lines_of(findings), [
        "exchange.json:1:1: error InvalidTranscript: I expected the end of the value that starts here, and I found the end of the text.",
      ])
    other => fail(@json.to_json(other).stringify())
  }
}

///|
test "the model files keep their names in model findings" {
  let (head, tail) = split_model()
  let session = Session::new()
  match
    start_files(session, WEATHER_EXCHANGE, files=[
      ("a.smithy", head),
      ("b.smithy", tail),
    ]) {
    TranscriptProgress(entries~, ..) => assert_eq(entries.length(), 3)
    other => fail(@json.to_json(other).stringify())
  }
  // An error in the second file blocks the check, as a transform is blocked.
  let bad = tail.replace(old="city: String", new="city: Strng")
  match
    start_files(session, WEATHER_EXCHANGE, files=[
      ("a.smithy", head),
      ("b.smithy", bad),
    ]) {
    Blocked(kind=ModelErrors, reason~, ..) =>
      assert_eq(
        reason, "The model has 1 error. Fix it in the Validate tab, then run again.",
      )
    other => fail(@json.to_json(other).stringify())
  }
}

///|
/// The weather model in two files: the protocol, and the operations in the
/// second, which the first reaches with a `use`.
fn split_model() -> (String, String) {
  let head =
    #|$version: "2"
    #|namespace example
    #|
    #|use smithy.rpc#jsonRpc
    #|use smithy.rpc#jsonRpcProtocol
    #|use example.ops#GetWeather
    #|use example.ops#Alert
    #|
    #|@jsonRpcProtocol(
    #|    versions: ["2.0"]
    #|    peers: [
    #|        { name: "client", accepts: WeatherClient }
    #|        { name: "server", accepts: WeatherServer }
    #|    ]
    #|)
    #|structure WeatherProtocol {}
    #|
    #|@jsonRpc(versions: ["2.0"])
    #|service WeatherServer {
    #|    version: "1"
    #|    operations: [GetWeather]
    #|}
    #|
    #|@jsonRpc(versions: ["2.0"])
    #|service WeatherClient {
    #|    version: "1"
    #|    operations: [Alert]
    #|}
  let tail =
    #|$version: "2"
    #|namespace example.ops
    #|
    #|use smithy.rpc#method
    #|
    #|@method(name: "weather/get", params: "named", resultMember: "forecast")
    #|operation GetWeather { input: GetWeatherInput, output: GetWeatherOutput }
    #|
    #|structure GetWeatherInput { @required city: String }
    #|
    #|structure GetWeatherOutput { forecast: String }
    #|
    #|@method(name: "weather/alert", params: "named", nullResult: true)
    #|operation Alert { input: AlertInput }
    #|
    #|structure AlertInput { text: String }
  (head, tail)
}

///|
test "a model with errors is blocked as a transform is" {
  let session = Session::new()
  let bad = WEATHER_MODEL.replace(old="forecast: String", new="forecast: Strng")
  match start_files(session, WEATHER_EXCHANGE, files=[("model.smithy", bad)]) {
    Blocked(kind=ModelErrors, ..) => ()
    other => fail(@json.to_json(other).stringify())
  }
}

///|
test "the expect lines are the lines of the CLI" {
  let missing : ExpectationView = {
    matched: false,
    missing: [{ code: "MissingResponse", entry: Some(0), related: None, }],
    unexpected: [],
  }
  assert_eq(missing.cli_lines(file="x.json"), [
    "x.json: expect: I expected MissingResponse at entry 0; no finding matches it.",
  ])
  let related : ExpectationView = {
    matched: false,
    missing: [{ code: "C", entry: Some(2), related: Some(0), }],
    unexpected: [],
  }
  assert_eq(related.cli_lines(file="x.json"), [
    "x.json: expect: I expected C at entry 2 related to entry 0; no finding matches it.",
  ])
  let unexpected : ExpectationView = {
    matched: false,
    missing: [],
    unexpected: [
      {
        code: "MissingResponse",
        severity: "error",
        message: "m",
        entry: Some(0),
        line: Some(6),
        column: Some(35),
        sender: Some("client"),
        related: [],
        path: None,
        shape: None,
        operation: None,
      },
    ],
  }
  assert_eq(unexpected.cli_lines(file="x.json"), [
    "x.json:6:35: entry 0 client: expect: I did not expect error MissingResponse.",
  ])
}

///|
test "cli_line leaves out the parts that a finding does not have" {
  let finding : FindingView = {
    code: "C",
    severity: "error",
    message: "m",
    entry: Some(1),
    line: None,
    column: None,
    sender: None,
    related: [],
    path: None,
    shape: None,
    operation: None,
  }
  assert_eq(finding.cli_line(file="x.json"), "x.json: entry 1: error C: m")
  let other = {
    ..finding,
    severity: "advisory",
    entry: None,
    line: Some(2),
    column: Some(3),
  }
  assert_eq(other.cli_line(file="x.json"), "x.json:2:3: advisory C: m")
}

///|
test "TranscriptStart answers as before" {
  let old = handle(
    Session::new(),
    TranscriptStart(
      seq=1,
      model=WEATHER_MODEL,
      protocol=WEATHER_PROTOCOL,
      format=Json,
      complete=false,
      log_preset=None,
      version=None,
      text=WEATHER_EXCHANGE,
    ),
  )
  assert_eq(old, start_files(Session::new(), WEATHER_EXCHANGE))
}

///|
test "a transcript request with files survives the Worker JSON" {
  let request = TranscriptStartFiles(
    seq=1,
    files=[("a.smithy", WEATHER_MODEL)],
    protocol=WEATHER_PROTOCOL,
    format=Json,
    complete=false,
    text=WEATHER_EXCHANGE,
  )
  let session = Session::new()
  let text = handle_json(session, @json.to_json(request).stringify())
  let expected = @json.to_json(handle(Session::new(), request)).stringify()
  assert_eq(text, expected)
  let decoded : Request = @json.from_json(
    @json.parse(@json.to_json(request).stringify()),
  )
  assert_eq(decoded, request)
}
