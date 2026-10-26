///|
async fn frames_of(input : String) -> String {
  let (r, w) = @io.pipe()
  let out = []
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      defer w.close()
      w.write(input)
    })
    defer r.close()
    while @rpc.read_frame(r) is Some(text) {
      out.push(text)
    }
  }) catch {
    @rpc.TransportError(message) => out.push("error: " + message)
    err => out.push("other: \{err}")
  }
  out.join("\n")
}

///|
async test "read frames and ignore unknown headers" {
  inspect(
    frames_of(
      "Content-Length: 2\r\n\r\n{}Content-Type: application/vscode-jsonrpc; charset=utf-8\r\ncontent-length:  4\r\n\r\n[1,2]",
    ),
    content=(
      #|{}
      #|[1,2
      #|error: I expected a frame header of the form 'Name: value', found ']'.
    ),
  )
}

///|
async test "the length counts UTF-8 bytes" {
  let (r, w) = @io.pipe()
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      defer w.close()
      @rpc.write_frame(w, "\"é😀\"")
    })
    defer r.close()
    let raw = r.read_all().text()
    inspect(raw, content="Content-Length: 8\r\n\r\n\"é😀\"")
  })
}

///|
async test "frame errors name the header and what was found" {
  inspect(
    frames_of("Foo: 1\r\n\r\n{}"),
    content="error: I expected a Content-Length header in the frame, found 'Foo: 1'.",
  )
  inspect(
    frames_of("Content-Length: x\r\n\r\n{}"),
    content="error: I expected a byte count of at most 67108864 in the Content-Length header, found 'x'.",
  )
  inspect(
    frames_of("Content-Length: 10\r\n\r\n{}"),
    content="error: I expected 10 bytes of the frame body, found the end of the input.",
  )
  inspect(
    frames_of("Content-Length: 2\r\n"),
    content="error: I expected the empty line at the end of the frame headers, found the end of the input after 'Content-Length: 2'.",
  )
  inspect(frames_of(""), content="")
}

///|
async test "spawn_stdio talks to a child process" {
  let conn = @rpc.spawn_stdio(["/bin/cat"])
  conn.send("{\"jsonrpc\":\"2.0\",\"method\":\"terminal.ping\"}", related=None)
  inspect(
    conn.receive().unwrap(),
    content="{\"jsonrpc\":\"2.0\",\"method\":\"terminal.ping\"}",
  )
  conn.close()
  inspect(conn.wait(), content="0")
}

///|
async test "spawn_stdio needs a command" {
  let text = try @rpc.spawn_stdio([]) |> ignore catch {
    @rpc.TransportError(message) => message
    err => "other: \{err}"
  } noraise {
    _ => "no error"
  }
  inspect(
    text,
    content="I expected a command to start, found an empty argument list.",
  )
}
