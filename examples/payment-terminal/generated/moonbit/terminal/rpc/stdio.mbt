// The stdio transport: `Content-Length: N\r\n\r\n` and then N bytes of UTF-8
// JSON, as in LSP. A reader ignores the headers that it does not know, such
// as Content-Type. Diagnostics go to stderr, never to stdout.

///|
/// The largest frame body that a reader accepts: 64 MiB.
pub let max_frame_bytes : Int32 = 64 * 1024 * 1024

///|
fn header_lines(lines : Array[String]) -> String {
  if lines.is_empty() {
    "no header"
  } else {
    lines.map(line => "'" + line + "'").join(", ")
  }
}

///|
/// Reads one frame. It gives None at the end of the input before a frame.
pub async fn[R : @io.Reader] read_frame(reader : R) -> String? {
  let headers : Array[String] = []
  let mut length : Int32? = None
  while true {
    let line = match reader.read_until("\n") {
      Some(line) =>
        if line.has_suffix("\r") {
          line[:line.length() - 1].to_owned()
        } else {
          line
        }
      None =>
        if headers.is_empty() {
          return None
        } else {
          raise TransportError(
            "I expected the empty line at the end of the frame headers, found the end of the input after \{header_lines(headers)}.",
          )
        }
    }
    if line == "" {
      break
    }
    headers.push(line)
    guard line.find(":") is Some(colon) else {
      raise TransportError(
        "I expected a frame header of the form 'Name: value', found '\{line}'.",
      )
    }
    let name = line[:colon].to_owned().trim(chars=" \t").to_lower()
    if name == "content-length" {
      let value = line[colon + 1:].to_owned().trim(chars=" \t").to_owned()
      let n = if value != "" && value.iter().all(c => c >= '0' && c <= '9') {
        @string.parse_int(value) catch {
          _ => -1
        }
      } else {
        -1
      }
      if n < 0 || n > max_frame_bytes {
        raise TransportError(
          "I expected a byte count of at most \{max_frame_bytes} in the Content-Length header, found '\{value}'.",
        )
      }
      length = Some(n)
    }
  }
  guard length is Some(n) else {
    raise TransportError(
      "I expected a Content-Length header in the frame, found \{header_lines(headers)}.",
    )
  }
  let body = reader.read_exactly(n) catch {
    @io.ReaderClosed =>
      raise TransportError(
        "I expected \{n} bytes of the frame body, found the end of the input.",
      )
    err => raise err
  }
  let text = @utf8.decode(body) catch {
    _ =>
      raise TransportError(
        "I expected UTF-8 text in the frame body, found other bytes.",
      )
  }
  Some(text)
}

///|
/// Writes one frame with a Content-Length header.
pub async fn[W : @io.Writer] write_frame(writer : W, text : String) -> Unit {
  let body = @utf8.encode(text)
  // The header is ASCII, so one encoded text holds the header and the body.
  writer.write(@utf8.encode("Content-Length: \{body.length()}\r\n\r\n" + text))
}

///|
/// The stdio of this process as a connection: frames are read from stdin and
/// written to stdout.
struct StdioConnection {
  mut closed : Bool
}

///|
pub fn stdio_connection() -> StdioConnection {
  { closed: false, }
}

///|
pub impl Connection for StdioConnection with fn receive(self) {
  if self.closed {
    return None
  }
  read_frame(@stdio.stdin)
}

///|
pub impl Connection for StdioConnection with fn send(self, text, related~) {
  ignore(related)
  if self.closed {
    raise TransportError("I could not send the message: stdio is closed.")
  }
  write_frame(@stdio.stdout, text)
}

///|
pub impl Connection for StdioConnection with fn close(self) {
  self.closed = true
}

///|
/// A child process as a connection: frames are written to its stdin and
/// read from its stdout. Its stderr is the stderr of this process.
struct ProcessConnection {
  pid : Int32
  reader : @process.ReadFromProcess
  writer : @process.WriteToProcess
  mut closed : Bool
}

///|
/// Starts `argv` as a child process and connects to its stdio.
pub async fn spawn_stdio(argv : Array[String]) -> ProcessConnection {
  guard argv.length() > 0 else {
    raise TransportError(
      "I expected a command to start, found an empty argument list.",
    )
  }
  let (child_in, writer) = @process.write_to_process()
  let (reader, child_out) = @process.read_from_process()
  let pid = @process.spawn_orphan(
    argv[0],
    argv[1:],
    stdin=child_in,
    stdout=child_out,
  )
  { pid, reader, writer, closed: false, }
}

///|
/// The process ID of the child.
pub fn ProcessConnection::pid(self : ProcessConnection) -> Int32 {
  self.pid
}

///|
/// Waits until the child ends, and gives its exit code.
pub async fn ProcessConnection::wait(self : ProcessConnection) -> Int32 {
  @process.wait_pid(self.pid)
}

///|
pub impl Connection for ProcessConnection with fn receive(self) {
  if self.closed {
    return None
  }
  read_frame(self.reader)
}

///|
pub impl Connection for ProcessConnection with fn send(self, text, related~) {
  ignore(related)
  if self.closed {
    raise TransportError(
      "I could not send the message: the connection to the child process is closed.",
    )
  }
  write_frame(self.writer, text)
}

///|
/// Closes the stdin of the child, so that it reads the end of its input,
/// and stops the reading of its stdout.
pub impl Connection for ProcessConnection with fn close(self) {
  if !self.closed {
    self.closed = true
    self.writer.close()
    self.reader.close()
  }
}
