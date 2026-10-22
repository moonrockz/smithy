///|
test "message text keeps exact numbers" {
  let (document, problems) = @rpc.read_json_transcript(
    "[{\"from\": \"client\", \"message\": {\"id\": 1.0e400, \"s\": \"}\\\"]\"}}]",
  )
  assert_eq(problems, [])
  assert_eq(document.entries.length(), 1)
  assert_eq(document.entries[0].message, "{\"id\": 1.0e400, \"s\": \"}\\\"]\"}")
  assert_eq(document.entries[0].sender, peer("client"))
}

///|
test "documents carry version completeness and expectations" {
  let text =
    #|{
    #|  "version": "2.0",
    #|  "complete": true,
    #|  "expect": [{"code": "MissingResponse", "entry": 0}, {"code": "InvalidId", "related": 1}],
    #|  "entries": [
    #|    { "from": "client", "message": {"jsonrpc": "2.0", "id": 1, "method": "x"} },
    #|    { "from": "server", "message": 7 }
    #|  ]
    #|}
  let (document, problems) = @rpc.read_json_transcript(text)
  assert_eq(problems, [])
  assert_eq(document.version, Some(@rpc.V2_0))
  assert_eq(document.completeness, Some(@rpc.Complete))
  assert_eq(
    document.expect,
    Some([
      expected("MissingResponse", entry=Some(0)),
      expected("InvalidId", related=Some(1)),
    ]),
  )
  assert_eq(document.entries.map(e => e.sender.to_string()), [
    "client", "server",
  ])
  assert_eq(document.entries[1].message, "7")
  assert_eq(document.entries[0].location, Some({ line: 6, column: 36, }))
  assert_eq(document.entries[1].location, Some({ line: 7, column: 36, }))
  let (partial, _) = @rpc.read_json_transcript(
    "{\"version\": \"1.0\", \"complete\": false, \"entries\": []}",
  )
  assert_eq(partial.version, Some(@rpc.V1_0))
  assert_eq(partial.completeness, Some(@rpc.Partial))
  assert_eq(partial.expect, None)
  let (bare, _) = @rpc.read_json_transcript("{\"entries\": []}")
  assert_eq(bare.version, None)
  assert_eq(bare.completeness, None)
}

///|
test "bare arrays are entries" {
  let (document, problems) = @rpc.read_json_transcript(
    "\u{FEFF}\r\n[\r\n {\"from\":\"a\",\"message\":null},{\"from\":\"b\",\"message\":[1, [2]]}]\r\n",
  )
  assert_eq(problems, [])
  assert_eq(document.version, None)
  assert_eq(document.completeness, None)
  assert_eq(document.expect, None)
  assert_eq(document.entries.map(e => e.message), ["null", "[1, [2]]"])
  assert_eq(document.entries[0].location, Some({ line: 3, column: 24, }))
}

///|
fn problem_at(text : String) -> Array[(Int32, Int32, Bool)] {
  let (_, problems) = @rpc.read_json_transcript(text)
  problems.map(p => {
    let at = p.location.unwrap()
    (at.line, at.column, p.code == InvalidTranscript)
  })
}

///|
test "malformed documents give located findings" {
  // Empty and truncated documents.
  assert_eq(problem_at(""), [(1, 1, true)])
  assert_eq(problem_at("{\"entries\": ["), [(1, 1, true)])
  assert_eq(problem_at("[] x"), [(1, 4, true)])
  assert_eq(problem_at("{\"entries\": [}"), [(1, 14, true)])
  assert_eq(problem_at("\"text"), [(1, 1, true)])
  // A bad entry is dropped; the next one is still read.
  let text =
    #|[
    #|  {"from": "bad name", "message": 1},
    #|  {"message": 2},
    #|  {"from": "client"},
    #|  5,
    #|  {"from": "client", "message": 3}
    #|]
  let (document, problems) = @rpc.read_json_transcript(text)
  assert_eq(document.entries.map(e => e.message), ["3"])
  assert_eq(problems.map(p => p.location.unwrap().line), [2, 3, 4, 5])
  assert_eq(problems.map(p => p.severity == @validation.Error), [
    true, true, true, true,
  ])
  // Bad header values and expectations.
  assert_eq(problem_at("{\"version\": \"3.0\", \"entries\": []}"), [
    (1, 13, true),
  ])
  assert_eq(problem_at("{\"complete\": 1, \"entries\": []}"), [(1, 14, true)])
  assert_eq(
    problem_at("{\"expect\": [{\"code\": \"Nope\"}], \"entries\": []}"),
    [(1, 13, true)],
  )
  assert_eq(
    problem_at("{\"expect\": [{\"code\": \"InvalidId\", \"entry\": -1}]}"),
    [(1, 13, true)],
  )
}

///|
fn feed_document(
  text : String,
  protocol : @rpc.ProtocolDescription,
) -> (@rpc.TranscriptDocument, Array[@rpc.TranscriptFinding]) raise {
  let (document, problems) = @rpc.read_json_transcript(text)
  assert_eq(problems, [])
  let checker = @rpc.TranscriptChecker::new(
    protocol,
    completeness=document.completeness.unwrap_or(Partial),
  )
  let found = checker.feed_all(document.entries)
  found.append(checker.finish().findings)
  (document, found)
}

///|
test "echo and chat fixtures are valid" {
  let echo =
    #|{
    #|  "version": "1.0",
    #|  "complete": true,
    #|  "entries": [
    #|    { "from": "client", "message": {"method": "echo", "params": ["Hello JSON-RPC"], "id": 1} },
    #|    { "from": "server", "message": {"result": "Hello JSON-RPC", "error": null, "id": 1} }
    #|  ]
    #|}
  assert_eq(feed_document(echo, chat()).1, [])
  let conversation =
    #|{
    #|  "version": "1.0",
    #|  "complete": true,
    #|  "entries": [
    #|    { "from": "client", "message": {"method": "postMessage", "params": ["Hello all!"], "id": 99} },
    #|    { "from": "server", "message": {"method": "handleMessage", "params": ["user1", "I'm in!"], "id": null} },
    #|    { "from": "server", "message": {"result": 1, "error": null, "id": 99} },
    #|    { "from": "server", "message": {"method": "userLeft", "params": ["user3"], "id": null} }
    #|  ]
    #|}
  assert_eq(feed_document(conversation, chat()).1, [])
}

///|
test "editor fixtures match their expectations" {
  let positive =
    #|{
    #|  "version": "2.0",
    #|  "complete": true,
    #|  "entries": [
    #|    { "from": "client", "message": {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": 42}} },
    #|    { "from": "server", "message": {"jsonrpc": "2.0", "id": 1, "result": "full"} },
    #|    { "from": "server", "message": {"jsonrpc": "2.0", "id": 1, "method": "workspace/configuration", "params": {"section": "editor"}} },
    #|    { "from": "client", "message": {"jsonrpc": "2.0", "id": 1, "result": ["tabs"]} },
    #|    { "from": "client", "message": {"jsonrpc": "2.0", "id": 2, "method": "textDocument/hover", "params": {"uri": "file:///a.txt", "line": 1, "character": 2}} },
    #|    { "from": "server", "message": {"jsonrpc": "2.0", "id": 2, "result": "docs"} },
    #|    { "from": "client", "message": {"jsonrpc": "2.0", "id": 3, "method": "shutdown"} },
    #|    { "from": "server", "message": {"jsonrpc": "2.0", "id": 3, "result": null} },
    #|    { "from": "client", "message": {"jsonrpc": "2.0", "method": "exit"} }
    #|  ]
    #|}
  assert_eq(feed_document(positive, editor()).1, [])
  let negative =
    #|{
    #|  "version": "2.0",
    #|  "complete": true,
    #|  "expect": [
    #|    { "code": "UnsolicitedResponse", "entry": 1 },
    #|    { "code": "MissingResponse", "entry": 0 },
    #|    { "code": "MissingResponse", "entry": 2 }
    #|  ],
    #|  "entries": [
    #|    { "from": "client", "message": {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": 42}} },
    #|    { "from": "server", "message": {"jsonrpc": "2.0", "id": 9, "result": "full"} },
    #|    { "from": "client", "message": {"jsonrpc": "2.0", "id": 2, "method": "textDocument/hover", "params": {"uri": "file:///a.txt"}} }
    #|  ]
    #|}
  let (document, found) = feed_document(negative, editor())
  let result = @rpc.match_expected(document.expect.unwrap(), found)
  assert_eq(result.missing, [])
  assert_eq(result.unexpected, [])
}

///|
test "batch fixture is valid" {
  let batches =
    #|{
    #|  "version": "2.0",
    #|  "complete": true,
    #|  "entries": [
    #|    { "from": "client", "message": [
    #|      {"jsonrpc": "2.0", "method": "sum", "params": [1, 2, 4], "id": "1"},
    #|      {"jsonrpc": "2.0", "method": "notify_hello", "params": [7]},
    #|      {"jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": "2"}
    #|    ] },
    #|    { "from": "server", "message": [
    #|      {"jsonrpc": "2.0", "result": 7, "id": "1"},
    #|      {"jsonrpc": "2.0", "result": 19, "id": "2"}
    #|    ] }
    #|  ]
    #|}
  assert_eq(feed_document(batches, batch_link()).1, [])
}
