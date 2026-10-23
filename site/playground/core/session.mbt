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
      start_transcript(
        session, seq, model, protocol, format, complete, log_preset, text,
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
