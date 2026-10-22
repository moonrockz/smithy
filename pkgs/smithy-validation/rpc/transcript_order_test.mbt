///|
/// Same text as examples/json-rpc/lifecycle.smithy.
fn lifecycle_source() -> String {
  (
    #|$version: "2"
    #|namespace example.lifecycle
    #|
    #|use smithy.rpc#jsonRpc
    #|use smithy.rpc#jsonRpcCancels
    #|use smithy.rpc#jsonRpcLifecycle
    #|use smithy.rpc#jsonRpcProtocol
    #|use smithy.rpc#jsonRpcSession
    #|use smithy.rpc#method
    #|
    #|/// A MEP-like protocol: the host starts an extension, uses it and stops it.
    #|/// The initialize result advertises the optional capabilities.
    #|@jsonRpcProtocol(
    #|    versions: ["2.0"]
    #|    peers: [
    #|        { name: "host", accepts: Host }
    #|        { name: "extension", accepts: Extension }
    #|    ]
    #|)
    #|@jsonRpcSession(
    #|    states: ["starting", "initializing", "ready", "stopping", "stopped"]
    #|    capabilities: [
    #|        { name: "progress", method: "initialize", pointer: "/capabilities/progress" }
    #|        { name: "cancellation", method: "initialize", pointer: "/capabilities/cancellation" }
    #|    ]
    #|)
    #|structure Lifecycle {}
    #|
    #|@jsonRpc(versions: ["2.0"])
    #|service Extension {
    #|    version: "1"
    #|    operations: [Initialize, Initialized, Describe, Ping, Compile, Shutdown, Exit, CancelRequest]
    #|}
    #|
    #|@jsonRpc(versions: ["2.0"])
    #|service Host {
    #|    version: "1"
    #|    operations: [Progress]
    #|}
    #|
    #|@method(name: "initialize", params: "named")
    #|@jsonRpcLifecycle(allowedIn: ["starting"], onSuccess: "initializing")
    #|operation Initialize { input: InitializeInput, output: InitializeResult }
    #|
    #|structure InitializeInput { @required host: String }
    #|
    #|structure InitializeResult { @required capabilities: Capabilities }
    #|
    #|structure Capabilities {
    #|    progress: Boolean
    #|    cancellation: Boolean
    #|}
    #|
    #|@method(name: "initialized", params: "named", nullResult: true)
    #|@jsonRpcLifecycle(allowedIn: ["initializing"], onCall: "ready")
    #|operation Initialized {}
    #|
    #|@method(name: "describe", params: "named", resultMember: "name")
    #|@jsonRpcLifecycle(allowedIn: ["starting", "initializing", "ready"])
    #|operation Describe { output: DescribeOutput }
    #|
    #|structure DescribeOutput { name: String }
    #|
    #|@method(name: "ping", params: "named", nullResult: true)
    #|@jsonRpcLifecycle(allowedIn: ["starting", "initializing", "ready"])
    #|operation Ping {}
    #|
    #|@method(name: "compile", params: "named", resultMember: "output")
    #|@jsonRpcLifecycle(allowedIn: ["ready"])
    #|operation Compile { input: CompileInput, output: CompileOutput }
    #|
    #|structure CompileInput { @required source: String }
    #|
    #|structure CompileOutput { output: String }
    #|
    #|@method(name: "shutdown", params: "named", nullResult: true)
    #|@jsonRpcLifecycle(allowedIn: ["ready"], onSuccess: "stopping")
    #|operation Shutdown {}
    #|
    #|@method(name: "exit", params: "named", nullResult: true)
    #|@jsonRpcLifecycle(onCall: "stopped")
    #|operation Exit {}
    #|
    #|/// The host cancels one of its own calls. The call may then fail with -32800.
    #|@method(name: "$/cancelRequest", params: "named", nullResult: true)
    #|@jsonRpcLifecycle(requires: ["cancellation"])
    #|@jsonRpcCancels(idMember: "id", code: -32800)
    #|operation CancelRequest { input: CancelRequestInput }
    #|
    #|structure CancelRequestInput { @required id: Document }
    #|
    #|/// The extension reports progress to the host.
    #|@method(name: "progress", params: "named", nullResult: true)
    #|@jsonRpcLifecycle(requires: ["progress"])
    #|operation Progress { input: ProgressInput }
    #|
    #|structure ProgressInput { @required message: String }
  )
}

///|
fn lifecycle() -> @rpc.ProtocolDescription raise {
  describe(load(lifecycle_source()), "example.lifecycle#Lifecycle", @rpc.V2_0)
}

///|
fn ordered_editor() -> @rpc.ProtocolDescription raise {
  describe(load(peers_source()), "example.peers#OrderedEditor", @rpc.V2_0)
}

///|
/// A 2.0 call. `params` is a JSON object text, or "" for none.
fn call(id : Int32, method_ : String, params~ : String = "") -> String {
  let params = if params == "" { "" } else { ", \"params\": " + params }
  "{\"jsonrpc\": \"2.0\", \"id\": \{id}, \"method\": \"" +
  method_ +
  "\"" +
  params +
  "}"
}

///|
/// A 2.0 notification. `params` is a JSON object text, or "" for none.
fn notify(method_ : String, params~ : String = "") -> String {
  let params = if params == "" { "" } else { ", \"params\": " + params }
  "{\"jsonrpc\": \"2.0\", \"method\": \"" + method_ + "\"" + params + "}"
}

///|
fn success(id : Int32, result : String) -> String {
  "{\"jsonrpc\": \"2.0\", \"id\": \{id}, \"result\": " + result + "}"
}

///|
fn failure(id : Int32, code : Int32) -> String {
  "{\"jsonrpc\": \"2.0\", \"id\": \{id}, \"error\": {\"code\": \{code}, \"message\": \"failed\"}}"
}

///|
fn cancel(id : String) -> String {
  notify("$/cancelRequest", params="{\"id\": " + id + "}")
}

///|
/// The calls that bring the lifecycle protocol to ready, with the given
/// capabilities object in the initialize result.
fn ready(capabilities : String) -> Array[@rpc.TranscriptEntry] {
  [
    entry("host", call(1, "initialize", params="{\"host\": \"h\"}")),
    entry("extension", success(1, "{\"capabilities\": " + capabilities + "}")),
    entry("host", notify("initialized")),
  ]
}

///|
fn summary_of(findings : Array[@rpc.TranscriptFinding]) -> Array[String] {
  findings.map(f => {
    let related = f.related.map(r => r.to_string()).join(",")
    "\{f.code.to_string()}@\{f.entry.unwrap_or(-1)}[\{related}]"
  })
}

///|
/// The model text without the lifecycle and session traits.
fn without_order(source : String) -> String {
  source
  .split("\n")
  .filter(line => {
    !line.contains("jsonRpcLifecycle") && !line.contains("jsonRpcSession")
  })
  .map(line => line.to_owned())
  .collect()
  .join("\n")
}

///|
/// The transcripts of the correlation tests.
fn correlation_transcripts() -> Array[Array[@rpc.TranscriptEntry]] {
  let parse_error = "{\"jsonrpc\": \"2.0\", \"error\": {\"code\": -32700, \"message\": \"Parse error\"}, \"id\": null}"
  [
    [
      entry("client", hover("1")),
      entry("server", hover_reply("1.0")),
      entry("client", hover("2")),
      entry("server", hover_reply("20e-1")),
      entry("client", hover("3")),
      entry("server", hover_reply("\"3\"")),
    ],
    [
      entry("client", hover("1")),
      entry(
        "server", "{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"workspace/configuration\", \"params\": {}}",
      ),
      entry("client", "{\"jsonrpc\": \"2.0\", \"id\": 1, \"result\": [\"a\"]}"),
      entry("server", hover_reply("1")),
    ],
    [entry("server", hover_reply("1")), entry("client", hover("1"))],
    [
      entry("client", hover("1")),
      entry("server", hover_reply("1")),
      entry("server", hover_reply("1")),
    ],
    [
      entry("client", hover("1")),
      entry("client", hover("1")),
      entry("client", hover_reply("1")),
    ],
    [
      entry("client", hover("1")),
      entry("server", "{\"jsonrpc\": \"2.0\", \"id\": 1, \"result\": 5}"),
    ],
    [
      entry("client", "{"),
      entry(
        "client", "{\"jsonrpc\": \"2.0\", \"id\": null, \"method\": \"shutdown\"}",
      ),
      entry("server", parse_error),
      entry("server", parse_error),
    ],
    [
      entry("client", "{\"jsonrpc\": \"2.0\", \"method\": \"exit\"}"),
      entry("client", hover("7")),
      entry(
        "client", "{\"jsonrpc\": \"2.0\", \"id\": 8, \"method\": \"initialize\", \"params\": {}}",
      ),
      entry("server", "{\"jsonrpc\": \"2.0\", \"id\": 8, \"result\": \"full\"}"),
      entry(
        "client", "{\"jsonrpc\": \"2.0\", \"id\": 9, \"method\": \"shutdown\"}",
      ),
      entry("server", "{\"jsonrpc\": \"2.0\", \"id\": 9, \"result\": null}"),
      entry("client", hover("10")),
    ],
    [
      entry(
        "client", "{\"method\": \"postMessage\", \"params\": [\"Hello all!\"], \"id\": 99}",
      ),
      entry("server", "{\"result\": 1, \"error\": null, \"id\": 99}"),
      entry(
        "server", "{\"method\": \"userLeft\", \"params\": [\"user3\"], \"id\": null}",
      ),
      entry("client", "{\"result\": null, \"error\": null, \"id\": null}"),
    ],
  ]
}

///|
fn run_all(
  protocol : @rpc.ProtocolDescription,
  entries : Array[@rpc.TranscriptEntry],
  completeness : @rpc.Completeness,
) -> (Array[@rpc.TranscriptFinding], @rpc.TranscriptSummary) {
  let checker = @rpc.TranscriptChecker::new(protocol, completeness~)
  let found = checker.feed_all(entries)
  (found, checker.finish())
}

///|
test "protocols without session traits are unchanged" {
  let ordered = load(peers_source())
  let plain = load(without_order(peers_source()))
  assert_false(without_order(peers_source()).contains("jsonRpcLifecycle"))
  let mut total = 0
  for
    protocol in [
      ("example.peers#Editor", @rpc.V2_0),
      ("example.peers#EchoChat", @rpc.V1_0),
      ("example.peers#OneWay", @rpc.V2_0),
    ] {
    let (name, version) = protocol
    let with_traits = describe(ordered, name, version)
    let without_traits = describe(plain, name, version)
    for transcript in correlation_transcripts() {
      for completeness in [@rpc.Complete, @rpc.Partial] {
        let expected = run_all(without_traits, transcript, completeness)
        assert_eq(run_all(with_traits, transcript, completeness), expected)
        total += expected.0.length() + expected.1.findings.length()
      }
    }
  }
  // The comparison covers real findings, not only empty lists.
  assert_true(total > 100)
  // Hover before initialize and after shutdown is allowed without a session.
  let (found, _) = run_all(
    describe(ordered, "example.peers#Editor", @rpc.V2_0),
    correlation_transcripts()[7],
    Complete,
  )
  assert_eq(found, [])
}

///|
test "only initialize describe ping and exit before initialization" {
  let checker = @rpc.TranscriptChecker::new(lifecycle())
  let found = checker.feed_all([
    entry("host", call(1, "compile", params="{\"source\": \"x\"}")),
    entry("host", call(2, "shutdown")),
    entry("host", notify("initialized")),
    entry("host", call(3, "describe")),
    entry("host", call(4, "ping")),
    entry("host", call(5, "initialize", params="{\"host\": \"h\"}")),
    // The rejected shutdown succeeds, but it moves the session nowhere.
    entry("extension", success(2, "null")),
    entry("extension", success(3, "\"compiler\"")),
    entry("extension", success(4, "null")),
    entry("extension", success(5, "{\"capabilities\": {}}")),
    entry("host", call(6, "compile", params="{\"source\": \"x\"}")),
    entry("host", call(7, "ping")),
    entry("host", notify("initialized")),
    entry("host", call(8, "compile", params="{\"source\": \"x\"}")),
    entry("host", call(9, "initialize", params="{\"host\": \"h\"}")),
  ])
  assert_eq(summary_of(found), [
    "StateViolation@0[]", "StateViolation@1[]", "StateViolation@2[]", "StateViolation@10[9]",
    "StateViolation@14[12]",
  ])
  assert_eq(found[0].severity, @validation.Error)
  assert_eq(found[0].sender, Some(peer("host")))
  assert_eq(
    found[0].message,
    "I expected method compile only in state ready; entry 0 from host sent it in state starting.",
  )
  assert_eq(
    found[3].message,
    "I expected method compile only in state ready; entry 10 from host sent it in state initializing.",
  )
  assert_eq(
    found[4].message,
    "I expected method initialize only in state starting; entry 14 from host sent it in state ready.",
  )
  // Rejected calls are still correlated.
  assert_eq(checker.finish().outstanding, 5)
  let early_exit = @rpc.TranscriptChecker::new(lifecycle())
  let found = early_exit.feed_all([
    entry("host", notify("exit")),
    entry("host", call(1, "ping")),
  ])
  assert_eq(summary_of(found), ["StateViolation@1[0]"])
  assert_eq(
    found[0].message,
    "I expected method ping only in states starting, initializing or ready; entry 1 from host sent it in state stopped.",
  )
}

///|
test "only exit after shutdown" {
  let checker = @rpc.TranscriptChecker::new(lifecycle(), completeness=Complete)
  let found = checker.feed_all(
    ready("{}") +
    [
      entry("host", call(2, "shutdown")),
      entry("extension", success(2, "null")),
      entry("host", call(3, "compile", params="{\"source\": \"x\"}")),
      entry("host", call(4, "ping")),
      entry("host", call(5, "describe")),
      entry("host", call(6, "shutdown")),
      entry("host", notify("exit")),
      entry("host", call(7, "ping")),
      entry("host", notify("exit")),
    ],
  )
  assert_eq(summary_of(found), [
    "StateViolation@5[4]", "StateViolation@6[4]", "StateViolation@7[4]", "StateViolation@8[4]",
    "StateViolation@10[9]",
  ])
  assert_true(found[0].message.contains("in state stopping"))
  assert_true(found[4].message.contains("in state stopped"))
  // A failed shutdown leaves the session ready.
  let failed = @rpc.TranscriptChecker::new(lifecycle())
  let found = failed.feed_all(
    ready("{}") +
    [
      entry("host", call(2, "shutdown")),
      entry("extension", failure(2, -32603)),
      entry("host", call(3, "compile", params="{\"source\": \"x\"}")),
    ],
  )
  assert_eq(found, [])
}

///|
test "progress needs the advertised capability" {
  let progress = entry(
    "extension",
    notify("progress", params="{\"message\": \"half\"}"),
  )
  for
    advertised in [
      "{\"progress\": true}", "{\"progress\": true, \"cancellation\": false}",
    ] {
    let checker = @rpc.TranscriptChecker::new(lifecycle())
    assert_eq(checker.feed_all(ready(advertised) + [progress]), [])
  }
  for missing in ["{}", "{\"progress\": false}", "{\"progress\": null}"] {
    let checker = @rpc.TranscriptChecker::new(lifecycle())
    // A null Boolean is also a TypeMismatch in the initialize reply.
    let found = checker
      .feed_all(ready(missing) + [progress])
      .filter(f => !(f.code is Message(_)))
    // The related entry is the initialize call that did not advertise it.
    assert_eq(summary_of(found), ["CapabilityNotAdvertised@3[0]"])
    assert_eq(found[0].severity, @validation.Error)
    assert_eq(
      found[0].message,
      "I expected capability progress to be advertised before method progress; entry 3 from extension sent it, and no initialize result advertised it.",
    )
  }
  // An error reply advertises nothing, and neither does an unanswered call.
  let checker = @rpc.TranscriptChecker::new(lifecycle())
  let found = checker.feed_all([
    entry("host", call(1, "initialize", params="{\"host\": \"h\"}")),
    { ..progress, message: notify("progress", params="{\"message\": \"a\"}"), },
    entry("extension", failure(1, -32603)),
    progress,
  ])
  assert_eq(summary_of(found), [
    "CapabilityNotAdvertised@1[0]", "CapabilityNotAdvertised@3[0]",
  ])
  // Before any initialize call, no entry is related.
  let checker = @rpc.TranscriptChecker::new(lifecycle())
  assert_eq(summary_of(checker.feed_all([progress])), [
    "CapabilityNotAdvertised@0[]",
  ])
}

///|
test "cancelled calls may answer with the declared code" {
  let checker = @rpc.TranscriptChecker::new(lifecycle(), completeness=Complete)
  let compile = id => call(id, "compile", params="{\"source\": \"x\"}")
  let found = checker.feed_all(
    ready("{\"cancellation\": true}") +
    [
      entry("host", compile(2)),
      entry("host", cancel("2")),
      entry("extension", failure(2, -32800)),
      // Without a cancellation the code is still a finding.
      entry("host", compile(3)),
      entry("extension", failure(3, -32800)),
      // Another code is still a finding after a cancellation.
      entry("host", compile(4)),
      entry("host", cancel("4.0")),
      entry("extension", failure(4, -32801)),
      // The cancellation covers one reply to one call.
      entry("host", compile(5)),
      entry("host", cancel("5")),
      entry("extension", success(5, "\"done\"")),
      entry("host", compile(5)),
      entry("extension", failure(5, -32800)),
    ],
  )
  assert_eq(summary_of(found), [
    "UnknownError@7[6]", "UnknownError@10[8]", "UnknownError@15[14]",
  ])
  assert_eq(checker.finish().findings, [])
  // A cancellation that is not accepted cancels nothing.
  let unadvertised = @rpc.TranscriptChecker::new(lifecycle())
  let found = unadvertised.feed_all(
    ready("{}") +
    [
      entry("host", compile(2)),
      entry("host", cancel("2")),
      entry("extension", failure(2, -32800)),
    ],
  )
  assert_eq(summary_of(found), [
    "CapabilityNotAdvertised@4[0]", "UnknownError@5[3]",
  ])
  // An application code that the operation does not model is excused too.
  let model = load(
    (
      #|$version: "2"
      #|namespace t
      #|use smithy.rpc#jsonRpc
      #|use smithy.rpc#jsonRpcCancels
      #|use smithy.rpc#jsonRpcProtocol
      #|use smithy.rpc#jsonRpcSession
      #|use smithy.rpc#method
      #|@jsonRpcProtocol(versions: ["2.0"], peers: [{name: "a"}, {name: "b", accepts: S}])
      #|@jsonRpcSession(states: ["open"])
      #|structure P {}
      #|@jsonRpc(versions: ["2.0"])
      #|service S { version: "1", operations: [Work, Stop] }
      #|@method(name: "work", params: "positional", positional: [], nullResult: true)
      #|operation Work {}
      #|@method(name: "stop", params: "positional", positional: ["target"], nullResult: true)
      #|@jsonRpcCancels(idMember: "target", code: 7)
      #|operation Stop { input: StopInput }
      #|structure StopInput { target: Integer }
    ),
  )
  let checker = @rpc.TranscriptChecker::new(describe(model, "t#P", @rpc.V2_0))
  let found = checker.feed_all([
    entry("a", call(1, "work")),
    entry("a", call(2, "work")),
    entry("a", "{\"jsonrpc\": \"2.0\", \"method\": \"stop\", \"params\": [1]}"),
    entry("b", failure(1, 7)),
    entry("b", failure(2, 7)),
  ])
  assert_eq(summary_of(found), ["UnknownError@4[1]"])
}

///|
test "cancelling an inactive call is advisory" {
  let checker = @rpc.TranscriptChecker::new(lifecycle(), completeness=Complete)
  let found = checker.feed_all(
    ready("{\"cancellation\": true}") +
    [
      entry("host", cancel("9")),
      entry("host", call(2, "ping")),
      entry("extension", success(2, "null")),
      entry("host", cancel("2")),
      entry("host", call(3, "ping")),
      entry("host", cancel("\"3\"")),
      entry("extension", success(3, "null")),
    ],
  )
  assert_eq(summary_of(found), [
    "CancelInactiveCall@3[]", "CancelInactiveCall@6[5]", "CancelInactiveCall@8[]",
  ])
  assert_true(found.iter().all(f => f.severity == @validation.Advisory))
  assert_eq(
    found[0].message,
    "I expected $/cancelRequest at entry 3 from host to name an active call from host; it names id 9, which is not active.",
  )
  assert_eq(
    found[1].message,
    "I expected $/cancelRequest at entry 6 from host to name an active call from host; it names id 2, which is not active. Entry 5 answered it.",
  )
  assert_eq(checker.finish().findings, [])
}

///|
fn session_model(session : String, operation_traits : String) -> String {
  "$version: \"2\"\nnamespace t\nuse smithy.rpc#jsonRpc\nuse smithy.rpc#jsonRpcProtocol\n" +
  "use smithy.rpc#jsonRpcSession\nuse smithy.rpc#jsonRpcLifecycle\nuse smithy.rpc#jsonRpcCancels\n" +
  "use smithy.rpc#method\n" +
  "@jsonRpcProtocol(versions: [\"2.0\"], peers: [{name: \"a\"}, {name: \"b\", accepts: S}])\n" +
  "@jsonRpcSession(\{session})\nstructure P {}\n" +
  "@jsonRpc(versions: [\"2.0\"])\nservice S { version: \"1\", operations: [Go] }\n" +
  "@method(name: \"go\", params: \"named\", nullResult: true)\n" +
  operation_traits +
  "\noperation Go { input: GoInput }\nstructure GoInput { @jsonName(\"ref\") id: String }\n"
}

///|
test "invalid session traits are contract errors" {
  let session = "states: [\"open\", \"closed\"], capabilities: [{name: \"fast\", method: \"go\", pointer: \"/fast\"}]"
  let valid = load(
    session_model(
      session, "@jsonRpcLifecycle(allowedIn: [\"open\"], onCall: \"open\", onSuccess: \"closed\", onError: \"open\", requires: [\"fast\"])\n@jsonRpcCancels(idMember: \"id\")",
    ),
  )
  describe(valid, "t#P", @rpc.V2_0) |> ignore
  for
    case in [
      ("@jsonRpcLifecycle(allowedIn: [\"shut\"])", "allowedIn"),
      ("@jsonRpcLifecycle(onCall: \"shut\")", "onCall"),
      ("@jsonRpcLifecycle(onSuccess: \"shut\")", "onSuccess"),
      ("@jsonRpcLifecycle(onError: \"shut\")", "onError"),
      ("@jsonRpcLifecycle(requires: [\"slow\"])", "requires"),
      // The member is id; ref is its JSON name.
      ("@jsonRpcCancels(idMember: \"ref\")", "idMember"),
      ("@jsonRpcCancels(idMember: \"other\")", "other"),
    ] {
    let (traits, word) = case
    expect_invalid(session_model(session, traits), @rpc.V2_0, mentions=word)
  }
  for
    case in [
      ("states: [\"open\", \"open\"]", "distinct state names"),
      (
        "states: [\"open\"], capabilities: [{name: \"fast\", method: \"stop\", pointer: \"/fast\"}]",
        "method stop",
      ),
      (
        "states: [\"open\"], capabilities: [{name: \"fast\", method: \"go\", pointer: \"fast\"}]",
        "JSON Pointer",
      ),
      (
        "states: [\"open\"], capabilities: [{name: \"fast\", method: \"go\", pointer: \"/a~2\"}]",
        "/a~2",
      ),
      (
        "states: [\"open\"], capabilities: [{name: \"fast\", method: \"go\", pointer: \"/a\"}, {name: \"fast\", method: \"go\", pointer: \"/b\"}]",
        "distinct capability names",
      ),
      (
        "states: [\"open\"], capabilities: [{name: \"\", method: \"go\", pointer: \"/a\"}]",
        "nonempty capability name",
      ),
    ] {
    let (invalid, word) = case
    expect_invalid(session_model(invalid, ""), @rpc.V2_0, mentions=word)
  }
  // Model validation rejects a code that is not an integer, so the trait
  // value is set after loading.
  let model = load(session_model(session, "@jsonRpcCancels(idMember: \"id\")"))
  let go = model.shapes[@smithy.ShapeId::parse("t#Go").unwrap()]
  for
    code in [
      @smithy.Number(@smithy.NodeNumber::parse("1.5").unwrap()),
      @smithy.String("-32800"),
    ] {
    go.traits[@smithy.ShapeId::parse("smithy.rpc#jsonRpcCancels").unwrap()] = @smithy.Object({
        "idMember": @smithy.String("id"),
        "code": code,
      },
    )
    try describe(model, "t#P", @rpc.V2_0) catch {
      @rpc.InvalidContract(_, message) =>
        assert_eq(message, "I expected an integer jsonRpcCancels code.")
      e => fail("unexpected error: \{e}")
    } noraise {
      _ =>
        fail(
          "I expected the code \{@json.to_json(code).stringify()} to be rejected.",
        )
    }
  }
}

///|
test "editor initialize first and shutdown then exit" {
  let initialize = "{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"initialize\", \"params\": {\"processId\": 42}}"
  let configuration = "{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"workspace/configuration\", \"params\": {}}"
  let transcript = [
    entry("client", hover("0")),
    entry("server", configuration),
    entry("client", initialize),
    entry("server", success(1, "\"full\"")),
    entry("server", configuration),
    entry("client", "{\"jsonrpc\": \"2.0\", \"id\": 1, \"result\": [\"tabs\"]}"),
    entry("client", hover("2")),
    entry("server", hover_reply("2")),
    entry("client", call(3, "shutdown")),
    entry("server", success(3, "null")),
    entry("client", hover("4")),
    entry("client", notify("exit")),
    entry("client", initialize),
  ]
  let (found, _) = run_all(ordered_editor(), transcript, Partial)
  assert_eq(summary_of(found), [
    "StateViolation@0[]", "StateViolation@1[]", "ActiveIdReused@4[1]", "StateViolation@10[9]",
    "StateViolation@12[11]",
  ])
  assert_eq(found[1].sender, Some(peer("server")))
  // Editor has no session, so the same transcript has no order findings.
  let (found, _) = run_all(editor(), transcript, Partial)
  assert_eq(summary_of(found), ["ActiveIdReused@4[1]"])
}

///|
test "batches follow the session order" {
  let checker = @rpc.TranscriptChecker::new(lifecycle(), completeness=Complete)
  let found = checker.feed_all([
    entry(
      "host",
      "[" +
      call(1, "initialize", params="{\"host\": \"h\"}") +
      ", " +
      call(2, "compile", params="{\"source\": \"x\"}") +
      "]",
    ),
    entry(
      "extension",
      "[" +
      success(1, "{\"capabilities\": {\"progress\": true}}") +
      ", " +
      failure(2, -32603) +
      "]",
    ),
    entry("extension", notify("progress", params="{\"message\": \"m\"}")),
    entry("host", "[" + notify("initialized") + ", " + call(3, "ping") + "]"),
    entry("extension", "[" + success(3, "null") + "]"),
    entry("host", call(4, "compile", params="{\"source\": \"x\"}")),
    entry("extension", success(4, "\"ok\"")),
  ])
  assert_eq(summary_of(found), ["StateViolation@0[]"])
  assert_true(found[0].message.contains("method compile"))
  assert_eq(checker.finish().findings, [])
}

///|
test "initialize sent the wrong way advertises nothing" {
  // The host does not model initialize, so the call applies no rule.
  let checker = @rpc.TranscriptChecker::new(lifecycle())
  let found = checker
    .feed_all([
      entry("extension", call(1, "initialize", params="{\"host\": \"h\"}")),
      entry("host", success(1, "{\"capabilities\": {\"progress\": true}}")),
      entry("extension", notify("progress", params="{\"message\": \"m\"}")),
      entry("host", notify("initialized")),
    ])
    .filter(f => !(f.code is Message(_)))
  assert_eq(summary_of(found), [
    "CapabilityNotAdvertised@2[]", "StateViolation@3[]",
  ])
  // The same call in a batch also applies no rule.
  let checker = @rpc.TranscriptChecker::new(lifecycle())
  let found = checker
    .feed_all([
      entry(
        "extension",
        "[" + call(1, "initialize", params="{\"host\": \"h\"}") + "]",
      ),
      entry(
        "host",
        "[" + success(1, "{\"capabilities\": {\"progress\": true}}") + "]",
      ),
      entry("extension", notify("progress", params="{\"message\": \"m\"}")),
    ])
    .filter(f => !(f.code is Message(_)))
  assert_eq(summary_of(found), ["CapabilityNotAdvertised@2[]"])
}

///|
test "a refused call does not transition or cancel" {
  let compile = id => call(id, "compile", params="{\"source\": \"x\"}")
  let checker = @rpc.TranscriptChecker::new(lifecycle())
  let found = checker.feed_all(
    ready("{\"cancellation\": true}") +
    [
      entry("host", compile(2)),
      // Both calls reuse the active id 2, so the checker does not track them.
      entry("host", call(2, "exit")),
      entry("host", call(2, "$/cancelRequest", params="{\"id\": 2}")),
      entry("extension", failure(2, -32800)),
      entry("host", call(3, "ping")),
    ],
  )
  assert_eq(summary_of(found), [
    "ActiveIdReused@4[3]", "ActiveIdReused@5[3]", "UnknownError@6[3]",
  ])
  let limits = @rpc.TranscriptLimits::new(active_calls=1)
  let checker = @rpc.TranscriptChecker::new(lifecycle(), limits~)
  let found = checker.feed_all(
    ready("{}") +
    [
      entry("host", compile(2)),
      entry("host", call(3, "exit")),
      entry("host", "[" + compile(4) + "]"),
      entry("host", "[" + call(5, "exit") + "]"),
      entry("extension", success(2, "\"ok\"")),
      entry("host", call(6, "ping")),
    ],
  )
  assert_eq(summary_of(found), ["ActiveCallLimit@4[]", "ActiveCallLimit@6[]"])
}

///|
test "an unreadable entry refused at the limit does not transition" {
  // An id of true is not usable, so each call is an unreadable entry.
  let unreadable = method_ => {
    "{\"jsonrpc\": \"2.0\", \"id\": true, \"method\": \"" + method_ + "\"}"
  }
  let entries = [
    entry("host", unreadable("ping")),
    entry("host", unreadable("exit")),
    entry("host", call(3, "ping")),
  ]
  // A tracked unreadable exit moves the session to stopped, so the ping
  // after it is out of order.
  let checker = @rpc.TranscriptChecker::new(lifecycle())
  let found = checker.feed_all(entries).filter(f => !(f.code is Message(_)))
  assert_eq(summary_of(found), ["StateViolation@2[1]"])
  // At the limit, the checker does not track the exit, so it applies no
  // transition, like a refused call.
  let limits = @rpc.TranscriptLimits::new(active_calls=1)
  let checker = @rpc.TranscriptChecker::new(lifecycle(), limits~)
  let found = checker.feed_all(entries).filter(f => !(f.code is Message(_)))
  assert_eq(summary_of(found), ["ActiveCallLimit@1[]"])
}

///|
test "a cancellation of an earlier batch call is excused in the batch reply" {
  let compile = id => call(id, "compile", params="{\"source\": \"x\"}")
  let checker = @rpc.TranscriptChecker::new(lifecycle(), completeness=Complete)
  let found = checker.feed_all(
    ready("{\"cancellation\": true}") +
    [
      entry("host", "[" + compile(2) + ", " + compile(3) + "]"),
      entry("host", cancel("2")),
      entry("host", "[" + cancel("3") + "]"),
      entry(
        "extension",
        "[" + failure(2, -32800) + ", " + failure(3, -32800) + "]",
      ),
      // Only the cancelled element is excused.
      entry("host", "[" + compile(4) + ", " + compile(5) + "]"),
      entry("host", cancel("4")),
      entry(
        "extension",
        "[" + failure(5, -32800) + ", " + failure(4, -32800) + "]",
      ),
      // A cancellation of a single call does not excuse a batch call with
      // the same id.
      entry("host", compile(6)),
      entry("host", "[" + compile(6) + "]"),
      entry("host", cancel("6")),
      entry("extension", "[" + failure(6, -32800) + "]"),
      entry("extension", failure(6, -32800)),
    ],
  )
  assert_eq(summary_of(found), ["UnknownError@9[7]", "UnknownError@13[11]"])
  assert_eq(found[0].finding.map(f => f.path.pointer()), Some("/0/error/code"))
  assert_eq(checker.finish().findings, [])
}

///|
test "a cancellation of a call in the same batch gives no advisory" {
  let compile = id => call(id, "compile", params="{\"source\": \"x\"}")
  let checker = @rpc.TranscriptChecker::new(lifecycle(), completeness=Complete)
  let found = checker.feed_all(
    ready("{\"cancellation\": true}") +
    [
      entry("host", "[" + compile(2) + ", " + cancel("2") + "]"),
      entry("extension", "[" + failure(2, -32800) + "]"),
      entry("host", "[" + cancel("3") + ", " + compile(3) + "]"),
      entry("extension", "[" + failure(3, -32800) + "]"),
    ],
  )
  // The elements may be processed in any order, so the cancellation proves
  // nothing and excuses nothing.
  assert_eq(summary_of(found), ["UnknownError@4[3]", "UnknownError@6[5]"])
  assert_eq(checker.finish().findings, [])
}

///|
test "a null-id cancellation excuses no batch element" {
  let compile = id => call(id, "compile", params="{\"source\": \"x\"}")
  // A structured id is invalid in 2.0, so this element is answered with a
  // null id.
  let invalid = "{\"jsonrpc\": \"2.0\", \"method\": \"compile\", \"params\": {\"source\": \"x\"}, \"id\": {\"a\": 1}}"
  let null_error = "{\"jsonrpc\": \"2.0\", \"id\": null, \"error\": {\"code\": -32800, \"message\": \"failed\"}}"
  let checker = @rpc.TranscriptChecker::new(lifecycle(), completeness=Complete)
  let found = checker.feed_all(
    ready("{\"cancellation\": true}") +
    [
      entry("host", "[" + compile(2) + ", " + invalid + "]"),
      entry("host", cancel("null")),
      entry("extension", "[" + success(2, "\"ok\"") + ", " + null_error + "]"),
    ],
  )
  // The null key of a batch answers an invalid element, not one call, so the
  // cancellation names no active call and the reply keeps its finding.
  assert_eq(summary_of(found), [
    "InvalidId@3[]", "CancelInactiveCall@4[]", "UnknownError@5[3]", "InvalidContext@5[3]",
  ])
  assert_eq(found[2].finding.map(f => f.path.pointer()), Some("/1/error/code"))
  assert_eq(checker.finish().findings, [])
}

///|
test "a notification is not the source call of a capability" {
  let progress = entry(
    "extension",
    notify("progress", params="{\"message\": \"m\"}"),
  )
  let init_params = "{\"host\": \"h\"}"
  // A single notification, and a notification element of a batch.
  for
    sent in [
      notify("initialize", params=init_params),
      "[" +
      notify("initialize", params=init_params) +
      ", " +
      call(9, "ping") +
      "]",
    ] {
    let checker = @rpc.TranscriptChecker::new(lifecycle())
    let found = checker
      .feed_all([entry("host", sent), progress])
      .filter(f => !(f.code is Message(_)))
    assert_eq(summary_of(found), ["CapabilityNotAdvertised@1[]"])
  }
  // A real source call that came earlier stays the related entry.
  let checker = @rpc.TranscriptChecker::new(lifecycle())
  let found = checker
    .feed_all([
      entry("host", call(1, "initialize", params=init_params)),
      entry("host", notify("initialize", params=init_params)),
      progress,
    ])
    .filter(f => !(f.code is Message(_)))
  assert_eq(summary_of(found), ["CapabilityNotAdvertised@2[0]"])
}
