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
async fn stdio_fixture(mode : String) -> Array[String] {
  let path = "./_build/native/debug/build/fixtures/stdio/stdio.exe"
  guard @fs.exists(path) else {
    fail(
      "I expected the native stdio fixture at \{path}; run moon build --target native in runtimes/moonbit first.",
    )
  }
  [path, mode]
}

///|
async test "spawn_stdio talks to a child process" {
  @async.with_task_group(owner => {
    let conn = @rpc.spawn_stdio(owner, stdio_fixture("echo"))
    conn.send("{\"jsonrpc\":\"2.0\",\"method\":\"terminal.ping\"}", related=None)
    inspect(
      conn.receive().unwrap(),
      content="{\"jsonrpc\":\"2.0\",\"method\":\"terminal.ping\"}",
    )
    conn.shutdown()
    inspect(conn.wait(), content="0")
    // Process::wait caches the exit status on the retained handle.
    inspect(conn.wait(), content="0")
  })
}

///|
async test "spawn_stdio needs a command" {
  let text = @async.with_task_group(owner => {
    try @rpc.spawn_stdio(owner, []) |> ignore catch {
      @rpc.TransportError(message) => message
      err => "other: \{err}"
    } noraise {
      _ => "no error"
    }
  })
  inspect(
    text,
    content="I expected a command to start, found an empty argument list.",
  )
}

///|
async test "default shutdown preserves memory and stdio closure" {
  let (a, b) = @rpc.memory_pair()
  a.shutdown()
  a.shutdown()
  assert_true(a.receive() is None)
  assert_true(b.receive() is None)
  let stdio = @rpc.stdio_connection()
  stdio.shutdown()
  assert_true(stdio.receive() is None)
  let rejected = try stdio.send("{}", related=None) catch {
    @rpc.TransportError(_) => true
    err => raise err
  } noraise {
    _ => false
  }
  assert_true(rejected)
}

///|
async test "Peer::run returns when the child process exits" {
  // The child reads one frame header line and exits.
  @async.with_task_group(owner => {
    let conn = @rpc.spawn_stdio(owner, stdio_fixture("exit-after-header"))
    let pos = new_pos(@rpc.TranscriptLog::memory())
    @async.with_timeout(5000, () => {
      @async.with_task_group(group => {
        group.spawn_bg(() => pos.run(conn))
        pos.notify("terminal.ping", None, checked=false)
      })
    })
    inspect(conn.wait(), content="0")
  })
}

///|
async test "Peer::run returns after close while it reads from a child" {
  @async.with_task_group(owner => {
    let conn = @rpc.spawn_stdio(owner, stdio_fixture("echo"))
    let pos = new_pos(@rpc.TranscriptLog::memory())
    @async.with_timeout(5000, () => {
      @async.with_task_group(group => {
        group.spawn_bg(() => pos.run(conn))
        @async.sleep(20)
        conn.close()
      })
    })
    inspect(conn.wait(), content="0")
  })
}

///|
async test "spawn_stdio wait returns after the child already exited" {
  @async.with_task_group(owner => {
    let conn = @rpc.spawn_stdio(owner, stdio_fixture("echo"))
    assert_true(conn.pid() > 0)
    conn.close()
    // Drain stdout so the child can finish before wait.
    while conn.receive() is Some(_) {
      ignore(())
    }
    @async.sleep(50)
    inspect(conn.wait(), content="0")
  })
}
