///|
/// A session log in the JSONL form of the `dir-message` log preset of
/// `smithy validate rpc transcript`. Each line is
/// `{"dir":"send","message":<wire JSON>}` or `{"dir":"recv",...}`, from the
/// view of the peer that writes it.
struct TranscriptLog {
  path : String?
  mut file : @fs.File?
  lines : Array[String]
}

///|
/// A log that writes to the file at `path`. The file is created, or
/// truncated, when the first line is written.
pub fn TranscriptLog::open(path : String) -> TranscriptLog raise TransportError {
  if path == "" {
    raise TransportError(
      "I expected a path for the transcript log, found an empty text.",
    )
  }
  { path: Some(path), file: None, lines: [], }
}

///|
/// A log that keeps its lines in memory, for tests.
pub fn TranscriptLog::memory() -> TranscriptLog {
  { path: None, file: None, lines: [], }
}

///|
/// The lines of a memory log, without the line ends. A file log keeps no
/// lines in memory.
pub fn TranscriptLog::lines(self : TranscriptLog) -> Array[String] {
  self.lines
}

///|
/// Closes the file of the log.
pub fn TranscriptLog::close(self : TranscriptLog) -> Unit {
  if self.file is Some(file) {
    file.close()
    self.file = None
  }
}

///|
/// The text of one log line. `valid` is false when the wire text is not
/// JSON; the line then holds the text as a JSON string.
fn log_line(dir : String, text : String, valid : Bool) -> String {
  let message = if valid {
    // A raw line end can occur only between JSON tokens, so a space keeps
    // the same JSON value on one line.
    text.replace_all(old="\r", new=" ").replace_all(old="\n", new=" ")
  } else {
    write_json(Json::string(text))
  }
  "{\"dir\":\"\{dir}\",\"message\":\{message}}"
}

///|
async fn TranscriptLog::record(
  self : TranscriptLog,
  dir : String,
  text : String,
  valid~ : Bool = true,
) -> Unit {
  let line = log_line(dir, text, valid)
  guard self.path is Some(path) else {
    self.lines.push(line)
    return
  }
  let file = match self.file {
    Some(file) => file
    None => {
      let file = @fs.open(path, mode=WriteOnly, create_mode=CreateOrTruncate)
      self.file = Some(file)
      file
    }
  }
  file.write(line + "\n")
}
