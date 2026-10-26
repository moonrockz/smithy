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
- `TranscriptLog` writes `{"dir":"send"|"recv","message":<wire JSON>}` lines, which
  `smithy validate rpc transcript --log-preset dir-message` reads. Diagnostics go to stderr only.

## Credits

The layers of the dispatcher (an envelope reader, a table of handlers, a table of pending calls, and a read
loop that runs each incoming call in its own task) follow the `jsonrpc` package of
[moonbitlang/openseek](https://github.com/moonbitlang/openseek), under the Apache License 2.0. This
runtime does not copy its code and does not depend on it. The asynchronous parts use
[moonbitlang/async](https://github.com/moonbitlang/async) 0.22.5, under the Apache License 2.0.
