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

///|
test "run_transcript passes the legacy error mapping to the checker" {
  let (document, read) = @rpc.read_json_transcript(
    "{\"version\": \"1.0\", \"entries\": [{\"from\": \"client\", \"message\": {\"method\": \"echo\", \"params\": [\"hi\"], \"id\": 1}}, {\"from\": \"server\", \"message\": {\"result\": null, \"error\": {\"code\": 7, \"message\": \"failed\"}, \"id\": 1}}]}",
  )
  assert_eq(read, [])
  // Opaque by default: the error is not checked, and an advisory says so.
  let unmapped = @rpc.run_transcript(chat(), document, read)
  assert_eq(unmapped.findings.map(f => f.code.to_string()), ["LimitedScope"])
  assert_eq(unmapped.findings[0].severity, @validation.Advisory)
  // code-message-data checks the error; Echo models no code 7.
  let mapped = @rpc.run_transcript(
    chat(),
    document,
    read,
    legacy_errors=CodeMessageData,
  )
  assert_eq(mapped.findings.map(f => f.code.to_string()), ["UnknownError"])
  assert_eq(mapped.findings[0].severity, @validation.Error)
}
