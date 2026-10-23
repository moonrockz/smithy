///|
/// The tests run with `site/` as the working directory, so `..` is the
/// repository.
test "playground_data reads every sample of the picker" {
  guard playground_data("..", "/smithy/next/") is Ok(data) else {
    fail("the samples did not load")
  }
  assert_eq(data.worker, "/smithy/next/playground/worker.js")
  assert_eq(data.version, @smithy.version())
  assert_eq(data.selected, @samples.default_index)
  assert_eq(data.samples.map(s => s.title), @samples.manifest.map(s => s.title))
  let mistake = data.samples[data.selected]
  assert_true(mistake.model.contains("count: Intger"))
  assert_eq(data.transcript, @samples.default_transcript)
  assert_eq(
    data.transcripts.map(s => (s.title, s.path, s.format)),
    @samples.transcript_manifest.map(s => (s.title, s.path, s.format)),
  )
  let chat = data.transcripts[data.transcript]
  assert_true(chat.text.contains("{\"result\": \"one\""))
}

///|
test "playground_data names a sample that is missing" {
  match playground_data("/nonexistent-smithy-content", "/") {
    Err(message) => {
      assert_true(message.contains("examples/json-rpc/peers.smithy"))
      assert_true(message.contains("/nonexistent-smithy-content"))
    }
    Ok(_) => fail("a missing sample must fail the build")
  }
}

///|
test "the playground has a search entry that names its samples" {
  guard playground_data("..", "/smithy/") is Ok(data) else {
    fail("the samples did not load")
  }
  let entry = playground_entry(data)
  assert_eq(entry.route, Playground)
  assert_eq(entry.anchor, "")
  assert_eq(entry.page, "Playground")
  assert_true(entry.text.contains("JSON-RPC chat protocol"))
  assert_true(entry.text.contains("Chat with three findings"))
  assert_true(entry.text.contains("in the browser"))
}

///|
test "an example with a model in the picker gets a fragment that opens that model" {
  guard playground_data("..", "/smithy/") is Ok(data) else {
    fail("the samples did not load")
  }
  guard example_fragment("json-rpc", data) is Ok(Some(fragment)) else {
    fail("json-rpc has a model in the picker")
  }
  guard @core.decode_share(fragment) is Ok(state) else {
    fail("the fragment does not decode")
  }
  assert_eq(
    state.model,
    @fs.read_file_to_string("../examples/json-rpc/peers.smithy"),
  )
  assert_eq(state.tab, ValidateTab)
  // The transcript is one under the example, with its own protocol.
  assert_eq(
    state.transcript,
    @fs.read_file_to_string("../examples/json-rpc/transcripts/chat.md"),
  )
  assert_eq(state.protocol, "example.peers#EchoChat")
  assert_true(fragment.length() <= @core.MAX_SHARE_LENGTH)
}

///|
test "an example with no model in the picker has no fragment" {
  guard playground_data("..", "/smithy/") is Ok(data) else {
    fail("the samples did not load")
  }
  assert_eq(example_fragment("openrpc", data), Ok(None))
  assert_eq(example_fragment("nope", data), Ok(None))
}

///|
test "every example gets its playground fragment, so that each page has all of them" {
  guard playground_data("..", "/smithy/") is Ok(data) else {
    fail("the samples did not load")
  }
  let example = (dir : String) => @content.Example::{
    dir,
    title: dir,
    summary: "",
    files: [],
    playground: None,
  }
  guard with_playground_links([example("json-rpc"), example("openrpc")], data)
    is Ok(examples) else {
    fail("the fragments fit")
  }
  assert_eq(examples.map(e => e.dir), ["json-rpc", "openrpc"])
  assert_eq(examples[0].playground, example_fragment("json-rpc", data).unwrap())
  assert_true(examples[0].playground is Some(_))
  assert_eq(examples[1].playground, None)
}
