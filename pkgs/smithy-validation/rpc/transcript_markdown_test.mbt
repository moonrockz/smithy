///|
fn echo_markdown() -> String {
  (
    #|---
    #|version: "1.0"
    #|complete: true
    #|---
    #|## Echo
    #|
    #|```jsonrpc client -> server
    #|{"method": "echo", "params": ["Hello JSON-RPC"], "id": 1}
    #|```
    #|```jsonrpc server -> client
    #|{"result": "Hello JSON-RPC", "error": null, "id": 1}
    #|```
  )
}

///|
fn echo_json() -> String {
  (
    #|{
    #|  "version": "1.0",
    #|  "complete": true,
    #|  "entries": [
    #|    { "from": "client", "message": {"method": "echo", "params": ["Hello JSON-RPC"], "id": 1} },
    #|    { "from": "server", "message": {"result": "Hello JSON-RPC", "error": null, "id": 1} }
    #|  ]
    #|}
  )
}

///|
test "markdown echo equals the json echo" {
  let (markdown, problems) = @rpc.read_markdown_transcript(echo_markdown())
  assert_eq(problems, [])
  let (json, _) = @rpc.read_json_transcript(echo_json())
  assert_eq(markdown.version, json.version)
  assert_eq(markdown.completeness, json.completeness)
  assert_eq(
    markdown.entries.map(e => (e.sender, e.message)),
    json.entries.map(e => (e.sender, e.message)),
  )
  // The location is the first line of the block body, column 1.
  assert_eq(markdown.entries.map(e => e.location), [
    Some({ line: 8, column: 1, }),
    Some({ line: 11, column: 1, }),
  ])
  let from_markdown = @rpc.run_transcript(chat(), markdown, problems)
  let from_json = @rpc.run_transcript(chat(), json, [])
  assert_eq(from_markdown.findings, [])
  assert_eq(from_markdown.findings, from_json.findings)
  assert_eq(from_markdown.summary, from_json.summary)
}

///|
test "tilde and long fences close only on a matching fence" {
  let text =
    #|````jsonrpc client -> server
    #|{"method": "echo", "params": ["a"], "id": 1}
    #|```
    #|still inside
    #|````
    #|~~~jsonrpc server
    #|{"result": "a", "error": null, "id": 1}
    #|```
    #|~~~
    #|~~~~ text
    #|```jsonrpc client
    #|not an entry
    #|~~~~
    #|```jsonrpc client
    #|{"method": "echo", "params": ["b"], "id": 2}
    #|```
  let (document, problems) = @rpc.read_markdown_transcript(text)
  assert_eq(problems, [])
  assert_eq(document.entries.map(e => e.message), [
    "{\"method\": \"echo\", \"params\": [\"a\"], \"id\": 1}\n```\nstill inside",
    "{\"result\": \"a\", \"error\": null, \"id\": 1}\n```", "{\"method\": \"echo\", \"params\": [\"b\"], \"id\": 2}",
  ])
  assert_eq(document.entries.map(e => e.sender.to_string()), [
    "client", "server", "client",
  ])
}

///|
test "front matter sets version and completeness" {
  let (document, problems) = @rpc.read_markdown_transcript(
    "\u{FEFF}---\r\nversion: 2.0\r\ncomplete: false\r\ntitle: ignored\r\n---\r\n```jsonrpc client\r\n{}\r\n```\r\n",
  )
  assert_eq(problems, [])
  assert_eq(document.version, Some(@rpc.V2_0))
  assert_eq(document.completeness, Some(@rpc.Partial))
  assert_eq(document.entries.map(e => e.message), ["{}"])
  assert_eq(document.entries[0].location, Some({ line: 7, column: 1, }))
  // Front matter is only the first lines; later dashes are prose.
  let (late, problems) = @rpc.read_markdown_transcript(
    "intro\n---\nversion: 1.0\ncomplete: true\n---\n",
  )
  assert_eq(problems, [])
  assert_eq(late.version, None)
  assert_eq(late.completeness, None)
  let (bad, problems) = @rpc.read_markdown_transcript("---\nversion: 3\n---\n")
  assert_eq(bad.version, None)
  assert_eq(problems.map(p => (p.code, p.location)), [
    (@rpc.InvalidTranscript, Some({ line: 2, column: 1, })),
  ])
}

///|
test "expect blocks are read" {
  let text =
    #|```jsonrpc-expect
    #|[{"code": "UnsolicitedResponse", "entry": 0}]
    #|```
    #|```jsonrpc-expect
    #|[{"code": "MissingResponse", "related": 1}]
    #|```
    #|```jsonrpc-expect
    #|[{"code": "Nonsense"}]
    #|```
  let (document, problems) = @rpc.read_markdown_transcript(text)
  assert_eq(
    document.expect,
    Some([
      @rpc.ExpectedFinding::new("UnsolicitedResponse", entry=Some(0)).unwrap(),
      @rpc.ExpectedFinding::new("MissingResponse", related=Some(1)).unwrap(),
    ]),
  )
  assert_eq(problems.map(p => (p.code, p.location)), [
    (@rpc.InvalidTranscript, Some({ line: 8, column: 2, })),
  ])
  let (none, _) = @rpc.read_markdown_transcript("```jsonrpc client\n{}\n```\n")
  assert_eq(none.expect, None)
}

///|
test "a jsonrpc fence without a direction is reported" {
  let text =
    #|```jsonrpc
    #|{}
    #|```
    #|```jsonrpc client -> client
    #|{}
    #|```
    #|```jsonrpc a -> b -> c
    #|{}
    #|```
  let (document, problems) = @rpc.read_markdown_transcript(text)
  assert_eq(document.entries, [])
  assert_eq(problems.map(p => (p.code, p.location)), [
    (@rpc.InvalidTranscript, Some({ line: 1, column: 1, })),
    (@rpc.InvalidTranscript, Some({ line: 4, column: 1, })),
    (@rpc.InvalidTranscript, Some({ line: 7, column: 1, })),
  ])
}

///|
test "an unterminated fence is reported at its opening line" {
  let text = "prose\n\n```jsonrpc client\n{\"method\": \"x\"}\n"
  let (document, problems) = @rpc.read_markdown_transcript(text)
  assert_eq(document.entries, [])
  assert_eq(problems.map(p => (p.code, p.severity, p.location)), [
    (@rpc.InvalidTranscript, @validation.Error, Some({ line: 3, column: 1, })),
  ])
  // An unterminated fence of another language is prose.
  let (_, quiet) = @rpc.read_markdown_transcript("```json\n{")
  assert_eq(quiet, [])
}

///|
test "a named receiver is kept and a wrong one is an unknown peer" {
  let text =
    #|```jsonrpc client -> server
    #|{"jsonrpc": "2.0", "id": 1, "method": "shutdown"}
    #|```
    #|```jsonrpc client -> sevrer
    #|{"jsonrpc": "2.0", "id": 2, "method": "shutdown"}
    #|```
    #|```jsonrpc client
    #|{"jsonrpc": "2.0", "id": 3, "method": "shutdown"}
    #|```
  let (document, problems) = @rpc.read_markdown_transcript(text)
  assert_eq(problems, [])
  assert_eq(document.entries.map(e => e.receiver.map(p => p.to_string())), [
    Some("server"),
    Some("sevrer"),
    None,
  ])
  let run = @rpc.run_transcript(editor(), document, problems)
  let unknown = run.findings.filter(f => f.code == @rpc.UnknownPeer)
  assert_eq(unknown.map(f => f.entry), [Some(1)])
  assert_true(unknown[0].message.contains("sevrer"))
  assert_true(unknown[0].message.contains("server"))
  // The skipped entry is not tracked as a call: entries 0 and 2 stay outstanding.
  assert_eq(run.summary.outstanding, 2)
}

///|
test "info strings split on any whitespace" {
  let text = "```jsonrpc\tclient\t->\tserver\n{\"method\": \"echo\", \"params\": [\"a\"], \"id\": 1}\n```\n" +
    "```jsonrpc \t server\n{\"result\": \"a\", \"error\": null, \"id\": 1}\n```\n" +
    "```jsonrpc-expect\t\n[]\n```\n"
  let (document, problems) = @rpc.read_markdown_transcript(text)
  assert_eq(problems, [])
  assert_eq(
    document.entries.map(e => {
      (e.sender.to_string(), e.receiver.map(r => r.to_string()))
    }),
    [("client", Some("server")), ("server", None)],
  )
  assert_eq(document.expect, Some([]))
}
