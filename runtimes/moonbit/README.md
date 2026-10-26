# MoonBit JSON-RPC runtime

This module is the JSON-RPC 2.0 runtime of the MoonBit JSON-RPC generator. The generator copies the
files of `rpc/` (not the `*_test.mbt` files) into its output as the package `<module>/rpc`. The
generated code imports it as `@rpc`. The module is not in `moon.work`, and it is not published.

The files in `rpc/` do not name this module, because the generator copies them into other modules.
`rpc/moon.pkg` is copied as it is, so it has no test-only imports.

The runtime is for the native target only.

## Test

```shell
mise run test:runtime:moonbit
```

The task runs `moon check --deny-warn` and `moon test --target native` in `runtimes/moonbit`.

## Parts

| File | Contents |
| --- | --- |
| `json.mbt` | `parse_json` and `write_json`. Each number keeps its exact source text. The parser and the writer do not recurse. |
| `values.mbt` | `Decimal`, `BigInteger`, `Timestamp`, the `decode_*` and `encode_*` functions, and the params helpers. |
| `errors.mbt` | `RpcError`, `TransportError`, the standard error codes and `RequestId`. |
| `session.mbt` | `SessionRules` and the session engine. |
| `peer.mbt` | `Peer`, `CallContext` and the dispatcher. |
| `log.mbt` | `TranscriptLog`, the JSONL session log. |
| `connection.mbt` | The `Connection` trait and `memory_pair`. |
| `stdio.mbt` | Content-Length framing, `stdio_connection` and `spawn_stdio`. |
| `http.mbt` | `http_connect`, the HTTP client, and the HTTP session of the server. |
| `websocket.mbt` | `ws_connect` and the WebSocket connection. |
| `server.mbt` | `RpcServer` and `serve`: `POST /rpc` and `GET /ws` on one port. |

## Behavior

- A peer never sends a batch. A received JSON array gets one `-32600` error with the ID `null`.
- A request ID is a string or an integer. An integer keeps its text, also beyond the Int64 range.
- Unknown members of a message are ignored.
- An unknown method gets `-32601`. A `DecodeError` of a handler gets `-32602`. An invalid envelope gets
  `-32600`. Invalid JSON gets `-32700`. Any other error of a handler gets `-32603`. An `RpcError` of a
  handler gives its code, message and data.
- A request to a notification-only method gets `-32600`, and its handler does not run. A notification
  to a request-only method is dropped.
- The session rules follow the transcript checker in `pkgs/smithy-validation/rpc`: each peer applies
  every message that it sends or receives. A checked call that the session refuses raises `RpcError`
  with the modeled code, and nothing is sent. The receiver refuses with the same code. When the model
  gives no code, the code is `-32600`.
- The modeled cancel notification cancels the task of the named incoming call. The runtime then answers
  that call with the modeled code (`-32800` when the model gives none).
- A handler can call the remote peer while its call runs. `CallContext::peer` gives a peer whose
  messages are related to the call, and `CallContext::id_json` gives the ID for a progress notification.
- stdio: `Content-Length: N` and a blank line, then N bytes of UTF-8 JSON. A reader ignores the headers
  that it does not know. `spawn_stdio(argv)` starts a child process. A command without a `/` is searched
  in PATH. `close` closes the stdin of the child, and `receive` then gives the rest of its output.
- HTTP, in the style of MCP Streamable HTTP: the client POSTs each message to `/rpc`. The server gives
  `Smithy-Session-Id` on its first response, and the client sends it on each later POST. An unknown
  session gets 404. A request gets 200 `text/event-stream`: first the comment `: open`, then one
  `event: message` with `data: <JSON>` for each message that its handler sends, and its response last.
  A notification or a response gets 202. Invalid JSON and a batch get 200 `application/json` with the
  error. The client sends the next POST only after the response headers of the last POST, so the order
  of the messages stays the same.
- WebSocket: `GET /ws` on the same port, one message in each text frame.
- `serve(port~, on_peer)` serves `/rpc` and `/ws` on 127.0.0.1, and writes `listening N` to stderr.
  Port 0 picks a free port. `on_peer` runs once for each HTTP session and for each WebSocket.
- `TranscriptLog` writes `{"dir":"send"|"recv","message":<wire JSON>}` lines, which
  `smithy validate rpc transcript --log-preset dir-message` reads. Diagnostics go to stderr only.

## Credits

The layers of the dispatcher (an envelope reader, a table of handlers, a table of pending calls, and a read
loop that runs each incoming call in its own task) follow the `jsonrpc` package of
[moonbitlang/openseek](https://github.com/moonbitlang/openseek), under the Apache License 2.0. This
runtime does not copy its code and does not depend on it. The asynchronous parts use
[moonbitlang/async](https://github.com/moonbitlang/async) 0.22.5, under the Apache License 2.0.
