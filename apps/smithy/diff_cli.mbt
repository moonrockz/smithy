///|
fn diff_load(path : String) -> @smithy.Model? raise {
  let loader = @smithy.Loader::new()
  // Reuse local resource discovery, including directory traversal and JAR
  // manifests. This runner only collects inputs; no projection or plugin runs.
  let runner = @build.BuildRunner::new(
    @build.BuildConfig::parse("{\"version\":\"1.0\"}"),
  )
  build_add_files(loader, runner, path, None) catch {
    @build.InvalidBuildConfig(message) => raise CliError(message, 1)
    error => raise error
  }
  let result = loader.assemble()
  let mut failed = result.model == None
  for event in result.validation_events() {
    if event.severity == "ERROR" || event.severity == "DANGER" {
      failed = true
    }
    if event.severity == "ERROR" ||
      event.severity == "DANGER" ||
      event.severity == "WARNING" {
      cli_stderr(path + ": " + validation_event_text(event))
    }
  }
  if failed {
    None
  } else {
    result.model
  }
}

///|
fn run_diff(
  old_path : String,
  new_path : String,
  output : String?,
  format : DiffFormat,
) -> Int32 raise {
  let old_model = diff_load(old_path)
  let new_model = diff_load(new_path)
  guard old_model is Some(old_model) && new_model is Some(new_model) else {
    return 1
  }
  let result = @diff.compare(old_model, new_model)
  if format == Jsonl {
    write_diff_jsonl(result.events, output_sink(output))
    return if result.is_breaking() { 1 } else { 0 }
  }
  let lines = result.events
    .iter()
    .filter(e => e.severity != "SUPPRESSED")
    .map(e => {
      validation_event_text(e)
      .replace_all(old="\r\n", new="\n")
      .replace_all(old="\n", new="\\n")
    })
    .collect()
  emit(if lines.is_empty() { "" } else { lines.join("\n") + "\n" }, output)
  if result.is_breaking() {
    1
  } else {
    0
  }
}
