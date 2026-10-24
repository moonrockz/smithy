///|
/// The model of a load that the CLI compares: it assembles and has no ERROR or
/// DANGER event.
fn comparable(loaded : @smithy.LoadResult) -> @smithy.Model? {
  if error_count(loaded) > 0 {
    return None
  }
  loaded.model
}

///|
/// The findings of one side. A load with no model and no ERROR or DANGER event
/// gives one more finding, so the page has a reason to show: the CLI stops
/// there with no line.
fn diff_findings(
  loaded : @smithy.LoadResult,
  files : Array[(String, String)],
) -> Array[Diagnostic] {
  let findings = diagnostics_of(loaded, files)
  if loaded.model is None && error_count(loaded) == 0 {
    findings.push({
      severity: "ERROR",
      code: "ModelNotBuilt",
      message: "I could not build a model from the text, and I have no error to show.",
      file: "",
      start_line: 0,
      start_column: 0,
      end_line: 0,
      end_column: 0,
      shape: None,
    })
  }
  findings
}

///|
/// Compare two models, as `smithy diff` does: load both, and compare only when
/// both are clean. The answer has the findings of each model.
fn diff_models(
  seq : Int32,
  old : Array[(String, String)],
  new : Array[(String, String)],
) -> Response {
  let old_loaded = load(old)
  let new_loaded = load(new)
  let old_findings = diff_findings(old_loaded, old)
  let new_findings = diff_findings(new_loaded, new)
  guard comparable(old_loaded) is Some(old_model) &&
    comparable(new_loaded) is Some(new_model) else {
    return Diffed(
      seq~,
      old=old_findings,
      new=new_findings,
      events=None,
      breaking=false,
    )
  }
  let result = @diff.compare(old_model, new_model)
  let events = result.events
    .filter(event => event.severity != "SUPPRESSED")
    .map(event => {
      id: event.id,
      severity: event.severity,
      shape: event.shape.map(id => id.to_string()),
      message: event.message,
    })
  Diffed(
    seq~,
    old=old_findings,
    new=new_findings,
    events=Some(events),
    breaking=result.is_breaking(),
  )
}
