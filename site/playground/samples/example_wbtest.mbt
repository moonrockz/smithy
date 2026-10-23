///|
let model_a : Sample = {
  title: "A",
  path: "examples/a/peers.smithy",
  model: "namespace a\n",
}

///|
let model_site : Sample = {
  title: "Site",
  path: "site/landing/sample/order.smithy",
  model: "namespace site\n",
}

///|
let chat : TranscriptSample = {
  title: "Chat",
  path: "examples/a/transcripts/chat.md",
  protocol: "a#Chat",
  format: Markdown,
  version: None,
  preset: None,
  text: "chat",
}

///|
let log : TranscriptSample = {
  title: "Log",
  path: "examples/b/transcripts/log.jsonl",
  protocol: "b#Log",
  format: Jsonl,
  version: Some("2.0"),
  preset: Some(Raw(sender="client")),
  text: "log",
}

///|
test "example_state: a directory with a model gives the model and its transcript" {
  let state = example_state("a", [model_site, model_a], [log, chat], 0)
  assert_eq(
    state,
    Some({
      model: "namespace a\n",
      transcript: "chat",
      tab: ValidateTab,
      output: JsonAst,
      protocol: "a#Chat",
      format: Markdown,
      complete: false,
      selector: None,
      log_preset: None,
      version: None,
    }),
  )
}

///|
test "example_state: a directory with a model and no transcript uses the default" {
  let state = example_state("a", [model_a], [log], 0)
  assert_eq(state.map(s => s.transcript), Some("log"))
  assert_eq(state.map(s => s.log_preset), Some(Some(Raw(sender="client"))))
  assert_eq(state.map(s => s.version), Some(Some("2.0")))
}

///|
test "example_state: a directory with no model in the picker has no state" {
  assert_eq(example_state("b", [model_a, model_site], [log], 0), None)
  assert_eq(example_state("site", [model_site], [log], 0), None)
}
