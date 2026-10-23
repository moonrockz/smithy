///|
/// Run one request. A validate or transform request has no state. A transcript
/// request starts, steps or resets the transcript that the session holds.
pub fn handle(session : Session, request : Request) -> Response {
  match request {
    Validate(seq~, model~) => validate(seq, model)
    Transform(seq~, model~, output~, selector~) =>
      transform(seq, model, output, selector)
    TranscriptStart(
      seq~,
      model~,
      protocol~,
      format~,
      complete~,
      log_preset~,
      text~
    ) =>
      session.start_transcript(
        seq~,
        model~,
        protocol~,
        format~,
        complete~,
        log_preset~,
        text~,
      )
    TranscriptStep(seq~, count~) => step_transcript(session, seq, count)
    TranscriptReset(seq~) => {
      session.active = None
      TranscriptProgress(
        seq~,
        entries=[],
        findings=[],
        done=false,
        summary=None,
      )
    }
  }
}

///|
/// Run one request given as JSON and give the response as JSON. This is the
/// message format of the Worker. A request that does not decode gives
/// `Blocked` with `seq` -1.
pub fn handle_json(session : Session, text : String) -> String {
  let request : Request = @json.from_json(@json.parse(text)) catch {
    error =>
      return @json.to_json(
        blocked(seq=-1, reason="I could not read the request: \{error}"),
      ).stringify()
  }
  @json.to_json(handle(session, request)).stringify()
}
