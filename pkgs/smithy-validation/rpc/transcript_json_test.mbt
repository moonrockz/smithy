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
    [(1, 13, true), (1, 1, true)],
  )
}

///|
test "an expect file is a located array of expected findings" {
  let (items, problems) = @rpc.read_expected_findings(
    "\u{FEFF}\n[{\"code\": \"MissingResponse\", \"entry\": 0}, {\"code\": \"InvalidId\", \"related\": 1, \"entry\": null}]\n",
  )
  assert_eq(problems, [])
  assert_eq(items, [
    expected("MissingResponse", entry=Some(0)),
    expected("InvalidId", related=Some(1)),
  ])
  let (empty, problems) = @rpc.read_expected_findings("[]")
  assert_eq(empty, [])
  assert_eq(problems, [])
  // The item rules are those of the document reader's expect member.
  for
    (text, line, column) in [
      ("", 1, 1),
      ("  \n", 2, 1),
      ("{\"code\": \"MissingResponse\"}", 1, 1),
      ("[{\"code\": \"Nope\"}]", 1, 2),
      ("[\n {\"code\": \"InvalidId\", \"entry\": -1}]", 2, 2),
      ("[{\"entry\": 1}]", 1, 2),
      ("[7]", 1, 2),
      ("[] []", 1, 4),
      ("[{\"code\": \"InvalidId\"}", 1, 1),
    ] {
    let (items, problems) = @rpc.read_expected_findings(text)
    assert_eq(items, [], msg=text)
    guard problems is [problem] else { fail("expected one problem: \{text}") }
    assert_eq(problem.code, InvalidTranscript, msg=text)
    assert_eq(problem.severity, @validation.Error, msg=text)
    assert_eq(problem.location, Some({ line, column, }), msg=text)
  }
  let (_, problems) = @rpc.read_expected_findings("{}")
  assert_eq(problems.map(p => p.message), [
    "I expected an array of expected findings, and I found '{'.",
  ])
  let (_, problems) = @rpc.read_expected_findings("")
  assert_eq(problems.map(p => p.message), [
    "I expected an array of expected findings, and I found an empty document.",
  ])
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

///|
test "a transcript object needs exactly one entries member" {
  // A misspelled key leaves the document with no entries.
  let misspelled =
    #|{"version": "2.0", "complete": true, "entires": []}
  let (document, problems) = @rpc.read_json_transcript(misspelled)
  assert_eq(document.entries, [])
  assert_eq(
    problems.map(p => {
      (p.code.to_string(), p.severity == @validation.Error, p.location)
    }),
    [
      ("InvalidTranscript", false, Some({ line: 1, column: 38, })),
      ("InvalidTranscript", true, Some({ line: 1, column: 1, })),
    ],
  )
  assert_eq(
    problems[0].message,
    "I do not know the transcript member \"entires\"; I ignored it.",
  )
  assert_eq(
    problems[1].message,
    "I expected an \"entries\" member in the transcript object, and I found none.",
  )
  // A second entries member is an error, and its entries are not read.
  let twice =
    #|{
    #|  "entries": [{"from": "client", "message": 1}],
    #|  "entries": [{"from": "client", "message": 2}]
    #|}
  let (document, problems) = @rpc.read_json_transcript(twice)
  assert_eq(document.entries.map(e => e.message), ["1"])
  assert_eq(problems.length(), 1)
  assert_eq(problems[0].code, InvalidTranscript)
  assert_eq(problems[0].severity, @validation.Error)
  assert_eq(problems[0].location, Some({ line: 3, column: 3, }))
  assert_eq(
    problems[0].message,
    "I expected one \"entries\" member in the transcript object, and I found a second one.",
  )
}

///|
test "unknown top-level members are advisories" {
  let text =
    #|{"version": "2.0", "comment": "x", "entries": []}
  let (document, problems) = @rpc.read_json_transcript(text)
  assert_eq(document.version, Some(@rpc.V2_0))
  assert_eq(problems.length(), 1)
  assert_eq(problems[0].code, InvalidTranscript)
  assert_eq(problems[0].severity, @validation.Advisory)
  assert_eq(problems[0].location, Some({ line: 1, column: 20, }))
  // An advisory never fails a valid document.
  let run = @rpc.run_transcript(editor(), document, problems)
  assert_false(run.findings.iter().any(f => f.severity == @validation.Error))
}

///|
test "many entries are located in one scan" {
  let lines = ["["]
  let count = 20000
  for i in 0..<count {
    let comma = if i + 1 < count { "," } else { "" }
    lines.push("  {\"from\": \"client\", \"message\": \{i}}\{comma}")
  }
  lines.push("]")
  let (document, problems) = @rpc.read_json_transcript(lines.join("\n"))
  assert_eq(problems, [])
  assert_eq(document.entries.length(), count)
  assert_eq(document.entries[0].location, Some({ line: 2, column: 33, }))
  assert_eq(
    document.entries[count - 1].location,
    Some({ line: count + 1, column: 33, }),
  )
}

///|
test "document values nest at most 128 levels" {
  let deep = "[".repeat(129) + "]".repeat(129)
  let (_, problems) = @rpc.read_json_transcript(
    "{\"entries\": [], \"expect\": [" + deep + "]}",
  )
  assert_eq(problems.length(), 1)
  assert_true(problems[0].message.has_prefix("I expected a valid JSON value"))
  let (_, problems) = @rpc.read_json_transcript(
    "{\"entries\": [], \"expect\": [" + "[".repeat(127) + "]".repeat(127) + "]}",
  )
  assert_eq(problems.length(), 1)
  assert_true(problems[0].message.has_prefix("I expected an object"))
}

///|
test "a duplicate version, complete or expect member is an error" {
  for
    case in [
      ("version", "\"1.0\"", "\"2.0\""),
      ("complete", "true", "false"),
      ("expect", "[]", "[]"),
    ] {
    let (name, first, second) = case
    let text = "{\n  \"\{name}\": \{first},\n  \"\{name}\": \{second},\n  \"entries\": []\n}"
    let (_, problems) = @rpc.read_json_transcript(text)
    assert_eq(problems.length(), 1, msg=name)
    assert_eq(problems[0].code, InvalidTranscript, msg=name)
    assert_eq(problems[0].severity, @validation.Error, msg=name)
    assert_eq(problems[0].location, Some({ line: 3, column: 3, }), msg=name)
    assert_eq(
      problems[0].message,
      "I expected one \"\{name}\" member in the transcript object, and I found a second one.",
    )
  }
}
