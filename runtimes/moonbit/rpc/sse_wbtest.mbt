///|
/// A reader that gives `text` in chunks of at most 7 bytes.
fn sse_reader(text : String) -> @io.MemoryReader {
  @io.MemoryReader(async fn(writer) {
    let bytes = @utf8.encode(text)
    let mut start = 0
    while start < bytes.length() {
      let end = if start + 7 < bytes.length() {
        start + 7
      } else {
        bytes.length()
      }
      writer.write(bytes[start:end])
      start = end
    }
  })
}

///|
async fn sse_events(text : String, limit : Int32) -> Array[String] {
  let events = []
  let reader = sse_reader(text)
  defer reader.close()
  read_events(reader, fn(data) { events.push(data) }, limit~)
  events
}

///|
async test "sse events are read in chunks, with comments and CRLF" {
  let events = sse_events(
    ": open\r\n\r\nevent: message\r\ndata: {\"a\":1}\r\n\r\ndata: one\ndata: two\n\n",
    64,
  )
  assert_eq(events, ["{\"a\":1}", "one\ntwo"])
}

///|
async test "an sse line longer than the limit is an error" {
  let message = try sse_events("data: " + "x".repeat(100) + "\n\n", 64) catch {
    TransportError(text) => text
    _ => "another error"
  } noraise {
    _ => "no error"
  }
  assert_eq(
    message, "I expected an event-stream line of at most 64 bytes, found more.",
  )
}

///|
async test "an sse event whose data lines pass the limit is an error" {
  let lines = "data: 0123456789\n".repeat(10)
  let message = try sse_events(lines + "\n", 64) catch {
    TransportError(text) => text
    _ => "another error"
  } noraise {
    _ => "no error"
  }
  assert_eq(
    message, "I expected the data of one event-stream event to be at most 64 bytes, found more.",
  )
}

///|
async test "a held-open stream with an endless event stops at the limit" {
  let reader = @io.MemoryReader(async fn(writer) {
    for ;; {
      writer.write(b"data: 0123456789abcdef\n")
    }
  })
  defer reader.close()
  let message = try read_events(reader, fn(_) { () }, limit=1024) catch {
    TransportError(text) => text
    _ => "another error"
  } noraise {
    _ => "no error"
  }
  assert_true(
    message.has_prefix("I expected the data of one event-stream event"),
  )
}

///|
async test "a json response body is read up to the limit" {
  let small = sse_reader("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":null}")
  defer small.close()
  assert_eq(
    read_body(small, limit=64),
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":null}",
  )
  let large = sse_reader("x".repeat(100))
  defer large.close()
  let message = try read_body(large, limit=64) catch {
    TransportError(text) => text
    _ => "another error"
  } noraise {
    _ => "no error"
  }
  assert_eq(
    message, "I expected a JSON response body of at most 64 bytes, found more.",
  )
}
