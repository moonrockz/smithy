///|
enum DiffFormat {
  Text
  Jsonl
} derive(Eq, Debug)

///|
fn DiffFormat::parse(value : String) -> DiffFormat raise CliError {
  match value {
    "text" => Text
    "jsonl" => Jsonl
    _ =>
      raise CliError(
        "expected text or jsonl after --format, found '\{value}'",
        2,
      )
  }
}

///|
/// Host operations write all bytes or raise, including backpressure. Only stdout
/// needs a flush after every record. File sinks finish with one flush and close.
struct OutputSink {
  write : (Bytes) -> Unit raise
  flush : () -> Unit raise
  close : () -> Unit raise
  flush_records : Bool
}

///|
fn diff_event_json(event : @smithy.ValidationEvent) -> Json {
  let shape : Json = match event.shape {
    Some(id) => Json(id.to_string())
    None => null
  }
  let source : Json = match event.source {
    None => null
    Some(source) => {
      let span : Json = match source.span {
        None => null
        Some(span) => { "start": span.start.0, "length": span.length.0 }
      }
      { "file": source.file, "path": source.path, "span": span }
    }
  }
  {
    "id": event.id,
    "severity": event.severity,
    "shape": shape,
    "message": event.message,
    "source": source,
  }
}

///|
/// Serialize only the current event. The comparison result already owns the
/// events, but this writer never creates another aggregate of serialized output.
fn write_diff_jsonl(
  events : Array[@smithy.ValidationEvent],
  sink : OutputSink,
) -> Unit raise {
  // Preserve the original write/flush failure, but always release the file.
  {
    errdefer ((sink.close)() catch { _ => () })
    for event in events {
      if event.severity == "SUPPRESSED" {
        continue
      }
      (sink.write)(@utf8.encode(diff_event_json(event).stringify() + "\n"))
      if sink.flush_records {
        (sink.flush)()
      }
    }
    if !sink.flush_records || events.is_empty() {
      (sink.flush)()
    }
  }
  (sink.close)()
}

///|
/// Diagnostics must remain separate from JSONL even on Wasm GC, whose default
/// print host routes eprintln through stdout. Reporting must not mask a failure.
fn cli_stderr(message : String) -> Unit {
  try {
    let sink = stderr_sink()
    (sink.write)(@utf8.encode(message + "\n"))
    (sink.flush)()
  } catch {
    _ => ()
  }
}
