///|
/// Same text as examples/json-rpc/transcripts/editor.json.
fn editor_json() -> String {
  (
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
    #|
  )
}

///|
/// Same text as examples/json-rpc/transcripts/editor.md.
fn editor_markdown() -> String {
  (
    #|---
    #|version: "2.0"
    #|complete: true
    #|---
    #|# Editor
    #|
    #|The same transcript as `editor.json`. The client initializes the server, the server
    #|calls the client back for its configuration, and the client asks for hover text and
    #|then shuts the server down.
    #|
    #|```jsonrpc client -> server
    #|{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": 42}}
    #|```
    #|
    #|```jsonrpc server -> client
    #|{"jsonrpc": "2.0", "id": 1, "result": "full"}
    #|```
    #|
    #|The server calls the client back.
    #|
    #|```jsonrpc server -> client
    #|{"jsonrpc": "2.0", "id": 1, "method": "workspace/configuration", "params": {"section": "editor"}}
    #|```
    #|
    #|```jsonrpc client -> server
    #|{"jsonrpc": "2.0", "id": 1, "result": ["tabs"]}
    #|```
    #|
    #|```jsonrpc client -> server
    #|{"jsonrpc": "2.0", "id": 2, "method": "textDocument/hover", "params": {"uri": "file:///a.txt", "line": 1, "character": 2}}
    #|```
    #|
    #|```jsonrpc server -> client
    #|{"jsonrpc": "2.0", "id": 2, "result": "docs"}
    #|```
    #|
    #|```jsonrpc client -> server
    #|{"jsonrpc": "2.0", "id": 3, "method": "shutdown"}
    #|```
    #|
    #|```jsonrpc server -> client
    #|{"jsonrpc": "2.0", "id": 3, "result": null}
    #|```
    #|
    #|```jsonrpc client -> server
    #|{"jsonrpc": "2.0", "method": "exit"}
    #|```
    #|
  )
}

///|
/// Same text as examples/json-rpc/transcripts/editor-dir.ndjson.
fn editor_dir_ndjson() -> String {
  (
    #|{"dir": "request", "message": {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": 42}}}
    #|{"dir": "response", "message": {"jsonrpc": "2.0", "id": 1, "result": "full"}}
    #|{"dir": "response", "message": {"jsonrpc": "2.0", "id": 1, "method": "workspace/configuration", "params": {"section": "editor"}}}
    #|{"dir": "request", "message": {"jsonrpc": "2.0", "id": 1, "result": ["tabs"]}}
    #|{"dir": "request", "message": {"jsonrpc": "2.0", "id": 2, "method": "textDocument/hover", "params": {"uri": "file:///a.txt", "line": 1, "character": 2}}}
    #|{"dir": "response", "message": {"jsonrpc": "2.0", "id": 2, "result": "docs"}}
    #|{"dir": "request", "message": {"jsonrpc": "2.0", "id": 3, "method": "shutdown"}}
    #|{"dir": "response", "message": {"jsonrpc": "2.0", "id": 3, "result": null}}
    #|{"dir": "request", "message": {"jsonrpc": "2.0", "method": "exit"}}
    #|
  )
}

///|
/// Same text as examples/json-rpc/transcripts/editor.jsonl: the editor
/// transcript as dir-message records with "in" and "out", among log noise.
fn editor_jsonl() -> String {
  (
    #|editor bridge 1.4 starting on stdio ✓
    #|Content-Length: 80
    #|
    #|{"dir": "in", "message": {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": 42}}}
    #|{"level": "info", "msg": "initialize took 3 ms ⏱"}
    #|{"dir": "out", "message": {"jsonrpc": "2.0", "id": 1, "result": "full"}}
    #|[server] sending a configuration request 📨
    #|{"dir": "out", "message": {"jsonrpc": "2.0", "id": 1, "method": "workspace/configuration", "params": {"section": "editor"}}}
    #|{"dir": "in", "message": {"jsonrpc": "2.0", "id": 1, "result": ["tabs"]}}
    #|Content-Length: 122
    #|
    #|{"dir": "in", "message": {"jsonrpc": "2.0", "id": 2, "method": "textDocument/hover", "params": {"uri": "file:///a.txt", "line": 1, "character": 2}}}
    #|{"dir": "out", "message": {"jsonrpc": "2.0", "id": 2, "result": "docs"}}
    #|not json {
    #|{"dir": "in", "message": {"jsonrpc": "2.0", "id": 3, "method": "shutdown"}}
    #|{"dir": "out", "message": {"jsonrpc": "2.0", "id": 3, "result": null}}
    #|42
    #|{"dir": "in", "message": {"jsonrpc": "2.0", "method": "exit"}}
    #|bye 👋
    #|
  )
}

///|
/// Same text as examples/json-rpc/transcripts/mcp-like.jsonl.
fn mcp_like_jsonl() -> String {
  (
    #|2026-10-22T09:00:00.000Z INFO editor server 1.4 listening on stdio
    #|2026-10-22T09:00:00.120Z DEBUG {"event": "message", "from": "client", "text": "{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"initialize\", \"params\": {\"processId\": 42}}"}
    #|2026-10-22T09:00:00.130Z DEBUG {"event": "message", "from": "server", "text": "{\"jsonrpc\": \"2.0\", \"id\": 1, \"result\": \"full\"}"}
    #|2026-10-22T09:00:00.131Z DEBUG {"event": "timing", "ms": 11}
    #|2026-10-22T09:00:01.000Z DEBUG {"event": "message", "from": "client", "text": "{\"jsonrpc\": \"2.0\", \"id\": 2, \"method\": \"textDocument/hover\", \"params\": {\"uri\": \"file:///café.txt\", \"line\": 1, \"character\": 2}}"}
    #|2026-10-22T09:00:01.050Z DEBUG {"event": "message", "from": "server", "text": "{\"jsonrpc\": \"2.0\", \"id\": 2, \"result\": \"docs 📄\"}"}
    #|2026-10-22T09:00:02.000Z WARN slow client 🐢
    #|2026-10-22T09:00:02.100Z DEBUG {"event": "message", "from": "client", "text": "{\"jsonrpc\": \"2.0\", \"id\": 3, \"method\": \"shutdown\"}"}
    #|2026-10-22T09:00:02.110Z DEBUG {"event": "message", "from": "server", "text": "{\"jsonrpc\": \"2.0\", \"id\": 3, \"result\": null}"}
    #|2026-10-22T09:00:02.200Z DEBUG {"event": "message", "from": "client", "text": "{\"jsonrpc\": \"2.0\", \"method\": \"exit\"}"}
    #|
  )
}

///|
/// Same text as examples/json-rpc/transcripts/mcp-like.mapping.json.
fn mcp_like_mapping_json() -> String {
  (
    #|{
    #|  "prefix": {"fields": 2, "delimiter": " "},
    #|  "selector": {"field": "/event", "equals": "message"},
    #|  "message": {"escapedField": "/text"},
    #|  "sender": {"field": "/from", "values": {"client": "client", "server": "server"}}
    #|}
    #|
  )
}

///|
fn editor_peers() -> Map[String, @rpc.PeerName] {
  { "client": peer("client"), "server": peer("server") }
}

///|
fn in_out() -> @rpc.LogMapping {
  @rpc.LogMapping::dir_message({ "in": peer("client"), "out": peer("server") })
}

///|
fn request_response() -> @rpc.LogMapping {
  @rpc.LogMapping::dir_message({
    "request": peer("client"),
    "response": peer("server"),
  })
}

///|
fn mcp_like_mapping() -> @rpc.LogMapping raise {
  @rpc.LogMapping::new(
    prefix=Fields(2, ' '),
    selector=FieldEquals("/event", "message"),
    message=EscapedField("/text"),
    sender=@rpc.SenderSource::Field("/from", editor_peers()),
  )
}

///|
/// Reads `text` in one chunk and ends the stream.
fn read_log(
  mapping : @rpc.LogMapping,
  text : String,
  line_bytes? : Int32,
) -> (
  Array[@rpc.TranscriptEntry],
  Array[@rpc.TranscriptFinding],
  @rpc.LogCounts,
) {
  let reader = match line_bytes {
    Some(line_bytes) => @rpc.LogReader::new(mapping, line_bytes~)
    None => @rpc.LogReader::new(mapping)
  }
  let (entries, findings) = reader.push_text(text)
  let (rest, tail) = reader.end()
  (entries + rest, findings + tail, reader.counts())
}

///|
fn sent(entries : Array[@rpc.TranscriptEntry]) -> Array[(String, String)] {
  entries.map(e => (e.sender.to_string(), e.message))
}

///|
test "log noise content-length lines and plain text are counted not reported" {
  let (entries, findings, counts) = read_log(in_out(), editor_jsonl())
  assert_eq(findings, [])
  assert_eq(counts, { lines: 19, not_json: 8, skipped: 2, entries: 9, })
  let (document, _) = @rpc.read_json_transcript(editor_json())
  assert_eq(sent(entries), sent(document.entries))
  // The location is the line, and the column where the message value starts.
  assert_eq(entries[0].location, Some({ line: 4, column: 26, }))
  assert_eq(entries[1].location, Some({ line: 6, column: 27, }))
  assert_true(entries.iter().all(e => e.receiver is None))
  let checker = @rpc.TranscriptChecker::new(editor(), completeness=Complete)
  assert_eq(checker.feed_all(entries), [])
  assert_eq(checker.finish().findings, [])
}

///|
test "dir-message records map directions to peers" {
  let (entries, findings, counts) = read_log(
    request_response(),
    editor_dir_ndjson(),
  )
  assert_eq(findings, [])
  assert_eq(counts, { lines: 9, not_json: 0, skipped: 0, entries: 9, })
  assert_eq(entries.map(e => e.sender.to_string()), [
    "client", "server", "server", "client", "client", "server", "client", "server",
    "client",
  ])
  let (document, _) = @rpc.read_json_transcript(editor_json())
  assert_eq(sent(entries), sent(document.entries))
  // A direction the map does not name, a non-string direction and a record
  // with no message are reported, and each such line is dropped.
  let text =
    #|{"dir": "sideways", "message": {"jsonrpc": "2.0", "method": "exit"}}
    #|{"dir": 7, "message": {"jsonrpc": "2.0", "method": "exit"}}
    #|{"dir": "request"}
    #|{"message": {"jsonrpc": "2.0", "method": "exit"}}
    #|{"dir": "request", "message": {"jsonrpc": "2.0", "method": "exit"}}
  let (entries, findings, counts) = read_log(request_response(), text)
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].location, Some({ line: 5, column: 31, }))
  assert_eq(
    findings.map(f => (f.code.to_string(), f.severity, f.entry, f.location)),
    [
      (
        "InvalidTranscript",
        @validation.Error,
        None,
        Some({ line: 1, column: 9, }),
      ),
      (
        "InvalidTranscript",
        @validation.Error,
        None,
        Some({ line: 2, column: 9, }),
      ),
      (
        "InvalidTranscript",
        @validation.Error,
        None,
        Some({ line: 3, column: 1, }),
      ),
    ],
  )
  assert_eq(
    findings[0].message,
    "I expected a sender value at /dir that the mapping names (request, response), and I found \"sideways\" on line 1.",
  )
  assert_eq(
    findings[1].message,
    "I expected a string sender value at /dir, and I found 7 on line 2.",
  )
  assert_eq(
    findings[2].message,
    "I expected a message at /message, and I found no such field on line 3.",
  )
  assert_eq(counts, { lines: 5, not_json: 0, skipped: 1, entries: 1, })
}

///|
test "prefixes and escaped messages are extracted" {
  let (entries, findings, counts) = read_log(
    mcp_like_mapping(),
    mcp_like_jsonl(),
  )
  assert_eq(findings, [])
  assert_eq(counts, { lines: 10, not_json: 2, skipped: 1, entries: 7, })
  assert_eq(sent(entries), [
    (
      "client", "{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"initialize\", \"params\": {\"processId\": 42}}",
    ),
    ("server", "{\"jsonrpc\": \"2.0\", \"id\": 1, \"result\": \"full\"}"),
    (
      "client", "{\"jsonrpc\": \"2.0\", \"id\": 2, \"method\": \"textDocument/hover\", \"params\": {\"uri\": \"file:///café.txt\", \"line\": 1, \"character\": 2}}",
    ),
    ("server", "{\"jsonrpc\": \"2.0\", \"id\": 2, \"result\": \"docs 📄\"}"),
    ("client", "{\"jsonrpc\": \"2.0\", \"id\": 3, \"method\": \"shutdown\"}"),
    ("server", "{\"jsonrpc\": \"2.0\", \"id\": 3, \"result\": null}"),
    ("client", "{\"jsonrpc\": \"2.0\", \"method\": \"exit\"}"),
  ])
  // An escaped message starts after the opening quote of its string.
  assert_eq(entries[0].location, Some({ line: 2, column: 80, }))
  let checker = @rpc.TranscriptChecker::new(editor(), completeness=Complete)
  assert_eq(checker.feed_all(entries), [])
  assert_eq(checker.finish().findings, [])
  // Skip to the first brace; a line without one is not JSON.
  let braced =
    #|[12:00:01] client> {"jsonrpc": "2.0", "method": "exit"}
    #|[12:00:02] nothing here
    #|[12:00:03] note {"level": "debug"}
  let mapping = @rpc.LogMapping::new(
    prefix=ToFirstBrace,
    sender=Fixed(peer("client")),
  )
  let (entries, findings, counts) = read_log(mapping, braced)
  assert_eq(findings, [])
  assert_eq(sent(entries), [
    ("client", "{\"jsonrpc\": \"2.0\", \"method\": \"exit\"}"),
  ])
  assert_eq(entries[0].location, Some({ line: 1, column: 20, }))
  assert_eq(counts, { lines: 3, not_json: 1, skipped: 1, entries: 1, })
  // Too few fields is not JSON; an escaped field that is not a string is
  // reported.
  let fielded =
    #|2026 INFO
    #|2026 INFO {"event": "message", "from": "client", "text": 5}
    #|2026 INFO {"event": "message", "from": "client"}
  let (entries, findings, counts) = read_log(mcp_like_mapping(), fielded)
  assert_eq(entries, [])
  assert_eq(findings.map(f => (f.location, f.message)), [
    (
      Some({ line: 2, column: 58, }),
      "I expected a string holding the message at /text, and I found 5 on line 2.",
    ),
    (
      Some({ line: 3, column: 11, }),
      "I expected a message at /text, and I found no such field on line 3.",
    ),
  ])
  assert_eq(counts, { lines: 3, not_json: 1, skipped: 0, entries: 0, })
}

///|
/// Gives `text` to a new reader in chunks of `size` UTF-16 code units, which
/// can split a surrogate pair.
fn read_in_units(
  mapping : @rpc.LogMapping,
  text : String,
  size : Int32,
) -> (
  Array[@rpc.TranscriptEntry],
  Array[@rpc.TranscriptFinding],
  @rpc.LogCounts,
) {
  let reader = @rpc.LogReader::new(mapping)
  let entries = []
  let findings = []
  let mut start = 0
  while start < text.length() {
    let end = if start + size < text.length() {
      start + size
    } else {
      text.length()
    }
    let (e, f) = reader.push_text(text.unsafe_substring(start~, end~))
    entries.append(e)
    findings.append(f)
    start = end
  }
  let (e, f) = reader.end()
  (entries + e, findings + f, reader.counts())
}

///|
test "line endings bom split characters and a missing final newline" {
  let lf = "{\"jsonrpc\": \"2.0\", \"id\": 1, \"result\": \"😀 é\"}\nplain 🐢\n{\"jsonrpc\": \"2.0\", \"method\": \"exit\"}"
  let crlf = "\u{FEFF}" + lf.replace_all(old="\n", new="\r\n")
  let raw = @rpc.LogMapping::raw(peer("server"))
  let expected = read_log(raw, lf)
  assert_eq(expected.0.length(), 2)
  assert_eq(
    expected.0[0].message,
    "{\"jsonrpc\": \"2.0\", \"id\": 1, \"result\": \"😀 é\"}",
  )
  // The final line has no newline and still gives an entry.
  assert_eq(
    expected.0[1].message,
    "{\"jsonrpc\": \"2.0\", \"method\": \"exit\"}",
  )
  assert_eq(expected.0[1].location, Some({ line: 3, column: 1, }))
  assert_eq(expected.2, { lines: 3, not_json: 1, skipped: 0, entries: 2, })
  for size in 1..<=5 {
    assert_eq(read_in_units(raw, crlf, size), expected)
  }
  // An empty first chunk does not lose the BOM, and only the first BOM is
  // removed: a later one makes its line not JSON.
  let reader = @rpc.LogReader::new(raw)
  ignore(reader.push_text(""))
  let (entries, _) = reader.push_text(
    "\u{FEFF}{\"jsonrpc\": \"2.0\", \"method\": \"exit\"}\n\u{FEFF}{\"jsonrpc\": \"2.0\", \"method\": \"exit\"}\n",
  )
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].location, Some({ line: 1, column: 1, }))
  assert_eq(reader.end(), ([], []))
  assert_eq(reader.counts(), { lines: 2, not_json: 1, skipped: 0, entries: 1, })
  // A final carriage return with no newline is a line ending too.
  assert_eq(
    read_log(raw, "{\"jsonrpc\": \"2.0\", \"method\": \"exit\"}\r").0,
    read_log(raw, "{\"jsonrpc\": \"2.0\", \"method\": \"exit\"}").0,
  )
}

///|
test "overlong lines are reported and skipped" {
  let raw = @rpc.LogMapping::raw(peer("client"))
  let exit = "{\"jsonrpc\": \"2.0\", \"method\": \"exit\"}"
  let limit = exit.length()
  // A line of exactly the limit passes, also before CRLF.
  let (entries, findings, _) = read_log(
    raw,
    exit + "\r\n" + exit,
    line_bytes=limit,
  )
  assert_eq(findings, [])
  assert_eq(entries.length(), 2)
  // One byte more is reported once, at its line, and the next line is read.
  let long = "{\"jsonrpc\": \"2.0\", \"method\": \"exit!\"}"
  let text = exit + "\n" + long + "\n" + exit + "\n" + long
  let reader = @rpc.LogReader::new(raw, line_bytes=limit)
  let entries = []
  let findings = []
  for i in 0..<text.length() {
    let (e, f) = reader.push_text(text.unsafe_substring(start=i, end=i + 1))
    entries.append(e)
    findings.append(f)
  }
  let (e, f) = reader.end()
  entries.append(e)
  findings.append(f)
  assert_eq(entries.map(e => e.location), [
    Some({ line: 1, column: 1, }),
    Some({ line: 3, column: 1, }),
  ])
  assert_eq(findings.map(f => (f.code.to_string(), f.severity, f.location)), [
    ("InvalidTranscript", @validation.Error, Some({ line: 2, column: 1, })),
    ("InvalidTranscript", @validation.Error, Some({ line: 4, column: 1, })),
  ])
  assert_eq(
    findings[0].message,
    "I expected a log line of at most \{limit} bytes, and I found more on line 2; I skipped the line.",
  )
  assert_eq(reader.counts(), { lines: 4, not_json: 0, skipped: 0, entries: 2, })
  // Bytes are UTF-8 bytes: four 2-byte characters exceed 7 bytes.
  let (_, findings, _) = read_log(raw, "éééé", line_bytes=7)
  assert_eq(findings.length(), 1)
  let (_, findings, _) = read_log(raw, "ééé", line_bytes=7)
  assert_eq(findings, [])
}

///|
test "raw mapping is single sender" {
  let raw = @rpc.LogMapping::raw(peer("client"))
  assert_true(@rpc.LogReader::new(raw).single_sender())
  assert_false(@rpc.LogReader::new(in_out()).single_sender())
  // Records with jsonrpc, method, result or error are selected, and so is a
  // batch array that holds one; other JSON is skipped.
  let text =
    #|{"jsonrpc": "2.0", "method": "exit"}
    #|{"method": "echo", "params": [], "id": 1}
    #|{"result": 1, "error": null, "id": 1}
    #|{"error": {"code": 1}, "id": 2}
    #|[{"jsonrpc": "2.0", "method": "exit"}]
    #|{"level": "info"}
    #|[]
    #|"jsonrpc"
  let (entries, findings, counts) = read_log(raw, text)
  assert_eq(findings, [])
  assert_eq(entries.map(e => e.location.unwrap().line), [1, 2, 3, 4, 5])
  assert_true(entries.iter().all(e => e.sender == peer("client")))
  assert_eq(counts, { lines: 8, not_json: 0, skipped: 3, entries: 5, })
}

///|
test "mapping json is validated" {
  let peers = [peer("client"), peer("server")]
  assert_eq(
    @rpc.LogMapping::from_json(mcp_like_mapping_json(), peers),
    mcp_like_mapping(),
  )
  // Defaults: no prefix, any JSON-RPC record, the whole record; a string
  // sender is a fixed peer.
  assert_eq(
    @rpc.LogMapping::from_json("{\"sender\": \"client\"}", peers),
    @rpc.LogMapping::raw(peer("client")),
  )
  assert_eq(
    @rpc.LogMapping::from_json(
      "{\"prefix\": \"first-brace\", \"selector\": {\"hasField\": \"/dir\"}, \"message\": {\"field\": \"/message\"}, \"sender\": {\"field\": \"/dir\", \"values\": {\"in\": \"client\"}}}",
      peers,
    ),
    @rpc.LogMapping::new(
      prefix=ToFirstBrace,
      selector=HasField("/dir"),
      message=@rpc.MessageSource::Field("/message"),
      sender=@rpc.SenderSource::Field("/dir", { "in": peer("client") }),
    ),
  )
  assert_eq(
    @rpc.LogMapping::from_json(
      "{\"prefix\": \"none\", \"selector\": \"jsonrpc\", \"message\": \"record\", \"sender\": \"server\"}",
      peers,
    ),
    @rpc.LogMapping::raw(peer("server")),
  )
  fn rejected(text : String) -> String {
    try @rpc.LogMapping::from_json(text, peers) catch {
      @validation.ConfigurationError(message) => message
    } noraise {
      _ => "accepted"
    }
  }

  assert_eq(
    rejected("{\"sender\": \"client\""),
    "I expected a JSON object for the log mapping, and I found text that is not JSON.",
  )
  assert_eq(
    rejected("{}"),
    "I expected a \"sender\" in the log mapping, and I found none.",
  )
  assert_eq(
    rejected("{\"sender\": \"nobody\"}"),
    "I expected a peer of the protocol (client, server) as the sender, and I found \"nobody\".",
  )
  assert_eq(
    rejected("{\"sender\": \"client\", \"colour\": 1}"),
    "I expected prefix, selector, message or sender in the log mapping, and I found \"colour\".",
  )
  assert_eq(
    rejected("{\"sender\": \"client\", \"selector\": {\"hasField\": \"dir\"}}"),
    "I expected a JSON Pointer such as \"/dir\", and I found \"dir\".",
  )
  assert_eq(
    rejected("{\"sender\": \"client\", \"message\": {\"field\": \"/a~2\"}}"),
    "I expected a JSON Pointer such as \"/dir\", and I found \"/a~2\".",
  )
  assert_eq(
    rejected(
      "{\"sender\": \"client\", \"prefix\": {\"fields\": -1, \"delimiter\": \" \"}}",
    ),
    "I expected a field count of 0 or more in the log prefix, and I found -1.",
  )
  assert_eq(
    rejected(
      "{\"sender\": \"client\", \"prefix\": {\"fields\": 1, \"delimiter\": \"ab\"}}",
    ),
    "I expected one character as the prefix delimiter, and I found \"ab\".",
  )
  assert_eq(
    rejected("{\"sender\": {\"field\": \"/dir\", \"values\": {}}}"),
    "I expected at least one value in the sender map for /dir, and I found none.",
  )
  assert_eq(
    rejected(
      "{\"sender\": {\"field\": \"/dir\", \"values\": {\"in\": \"nobody\"}}}",
    ),
    "I expected a peer of the protocol (client, server) for sender value \"in\", and I found \"nobody\".",
  )
  assert_eq(
    rejected("{\"sender\": \"client\", \"message\": \"everything\"}"),
    "I expected \"record\", {\"field\": pointer} or {\"escapedField\": pointer} for \"message\", and I found \"everything\".",
  )
  // The constructor validates pointers and field counts too.
  fn refused(make : () -> @rpc.LogMapping raise) -> Bool {
    try make() catch {
      @validation.ConfigurationError(_) => true
      _ => false
    } noraise {
      _ => false
    }
  }

  assert_true(
    refused(() => {
      @rpc.LogMapping::new(
        message=@rpc.MessageSource::Field("message"),
        sender=Fixed(peer("client")),
      )
    }),
  )
  assert_true(
    refused(() => {
      @rpc.LogMapping::new(prefix=Fields(-1, ' '), sender=Fixed(peer("client")))
    }),
  )
  assert_true(
    refused(() => {
      @rpc.LogMapping::new(sender=@rpc.SenderSource::Field("/dir", Map([])))
    }),
  )
}
