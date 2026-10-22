///|
test "run_transcript reads completeness from the document, the override wins" {
  let (document, read) = @rpc.read_json_transcript(
    "{\"version\": \"2.0\", \"entries\": [{\"from\": \"client\", \"message\": {\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"shutdown\"}}]}",
  )
  let partial = @rpc.run_transcript(editor(), document, read)
  assert_eq(partial.findings.map(f => f.code.to_string()), ["OutstandingCall"])
  assert_eq(partial.summary.outstanding, 1)
  assert_eq(partial.expectations, None)
  let complete = @rpc.run_transcript(
    editor(),
    document,
    read,
    completeness=Complete,
  )
  assert_eq(complete.findings.map(f => f.code.to_string()), ["MissingResponse"])
  let (declared, _) = @rpc.read_json_transcript(
    "{\"complete\": true, \"entries\": []}",
  )
  assert_eq(@rpc.run_transcript(editor(), declared, []).findings, [])
  let overridden = @rpc.run_transcript(
    editor(),
    { ..declared, entries: document.entries, },
    [],
  )
  assert_eq(overridden.findings.map(f => f.code.to_string()), [
    "MissingResponse",
  ])
}

///|
test "run_transcript puts reader findings first and matches the expect list" {
  let (document, read) = @rpc.read_json_transcript(
    "{\"version\": \"2.0\", \"expect\": [{\"code\": \"UnsolicitedResponse\", \"entry\": 0}], \"entries\": [{\"from\": \"server\", \"message\": {\"jsonrpc\": \"2.0\", \"id\": 9, \"result\": 1}}, {\"from\": \"client\"}]}",
  )
  assert_eq(read.length(), 1)
  let run = @rpc.run_transcript(editor(), document, read)
  assert_eq(run.findings.map(f => f.code.to_string()), [
    "InvalidTranscript", "UnsolicitedResponse",
  ])
  let result = run.expectations.unwrap()
  assert_eq(result.missing, [])
  assert_eq(result.unexpected.map(f => f.code.to_string()), [
    "InvalidTranscript",
  ])
  assert_false(result.is_match())
}
