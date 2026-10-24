///|
fn reply(response : @core.Response) -> String {
  @json.to_json(response).stringify()
}

///|
test "findings answer their request" {
  let item : @core.Diagnostic = {
    severity: "ERROR",
    code: "TraitTarget",
    message: "m",
    file: "model.smithy",
    start_line: 3,
    start_column: 1,
    end_line: 3,
    end_column: 9,
    shape: Some("example#City"),
  }
  assert_eq(
    reply_msg(
      reply(Diagnostics(seq=4, items=[item], shapes=1, protocols=[])),
      9,
    ),
    Answered(seq=4, answer=Checked([item])),
  )
}

///|
test "a transform answers with the text of its files" {
  assert_eq(
    reply_msg(
      reply(
        Transformed(
          seq=2,
          files=[("model.json", "{}\n")],
          warnings=[],
          service=None,
        ),
      ),
      2,
    ),
    Answered(seq=2, answer=Converted("{}\n")),
  )
}

///|
test "a blocked request answers with its reason" {
  assert_eq(
    reply_msg(reply(Blocked(seq=3, reason="no", kind=ModelErrors)), 3),
    Answered(seq=3, answer=NotConverted("no")),
  )
}

///|
test "a reply of another build answers the newest request with the mismatch text" {
  let mismatch = @lesson.Answered(seq=7, answer=NotConverted(mismatch_text))
  assert_eq(
    reply_msg(reply(Blocked(seq=-1, reason="?", kind=Other)), 7),
    mismatch,
  )
  assert_eq(reply_msg("{\"Unknown\":1}", 7), mismatch)
  assert_eq(reply_msg("not json", 7), mismatch)
}

///|
test "the output editor language follows the lesson output" {
  assert_eq(output_language(Some(JsonAst)), "json")
  assert_eq(output_language(Some(OpenApi31)), "json")
  assert_eq(output_language(Some(Idl)), "smithy")
  assert_eq(output_language(Some(Selector)), "plain")
  assert_eq(output_language(None), "plain")
}

///|
test "the highlight and the marks are JSON for the editor" {
  assert_eq(lines_json([]), "[]")
  assert_eq(lines_json([2, 5]), "[2,5]")
  assert_eq(mark_json([]), "[]")
}

///|
test "the worker error text names the message when there is one" {
  assert_eq(
    stopped_text(""),
    "The checker stopped. Edit the model to try again.",
  )
  assert_eq(
    stopped_text("trap"),
    "The checker stopped: trap. Edit the model to try again.",
  )
}

///|
fn test_runtime(sent : Array[@lesson.Msg]) -> Runtime {
  let page : @model.LessonPage = {
    slug: "l",
    title: "L",
    section: "S",
    number: 1,
    total: 1,
    output: None,
    selector: None,
    spec: "",
    files: [],
    digest: "d",
    previous: None,
    next: None,
    worker: "worker.js",
    storage_key: "k",
    playground: None,
  }
  { page, worker: None, number: 2, dispatch: msg => sent.push(msg), seq: 5, }
}

///|
test "an error of an older Worker changes nothing" {
  let sent : Array[@lesson.Msg] = []
  let runtime = test_runtime(sent)
  runtime.worker_failed(1, "trap")
  assert_eq(sent, [])
  runtime.worker_failed(2, "trap")
  assert_eq(sent, [Answered(seq=5, answer=NotConverted(stopped_text("trap")))])
}

///|
test "a reply of an older Worker changes nothing" {
  let sent : Array[@lesson.Msg] = []
  let runtime = test_runtime(sent)
  runtime.worker_replied(1, "not json")
  assert_eq(sent, [])
  runtime.worker_replied(2, "not json")
  assert_eq(sent, [Answered(seq=5, answer=NotConverted(mismatch_text))])
}

///|
test "the script mounts the lesson component for a lesson with an editor only" {
  let sent : Array[@lesson.Msg] = []
  let page = test_runtime(sent).page
  assert_true(!should_mount(page))
  assert_true(
    should_mount({ ..page, files: [{ name: "model.smithy", text: "", }], }),
  )
}
