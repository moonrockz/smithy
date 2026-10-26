# Python JSON-RPC runtime

`smithy_jsonrpc_runtime` is the asyncio JSON-RPC 2.0 runtime of the peers that the Smithy Python
generator makes. The generator copies this package without changes into the generated package as
`<package>/_runtime/`. Generated code imports it relatively (`from ._runtime import Peer`).

All imports in the package are relative, and the package does not import its own name. Thus the
copy works under any package name. `tests/test_vendored_copy.py` checks this. The tests in `tests/`
are not copied.

## Rules

- Values are exact. A `bigDecimal` is a `decimal.Decimal`. A `bigInteger` or a `long` is an `int`.
  A number never goes through `float`. `json_codec.loads` reads each number with a fraction as a
  `Decimal` and each integer as an `int`. `json_codec.dumps` writes a `Decimal` with its exact text,
  so `20.00` stays `20.00`.
- A request ID is a string or an integer (`RequestId`). The peer returns it unchanged. The string
  `"1"` and the integer `1` are different IDs.
- A peer never sends a batch. A received JSON array gets one `-32600` error with the ID null.
- `SessionRules` drive the session state. Each peer applies every message that it sends or
  receives, with the same semantics as `smithy validate rpc transcript`. When `checked` is true, the
  caller refuses a call locally with the modeled code and sends nothing. The receiver refuses with
  the modeled code.
- The modeled cancel notification cancels the asyncio task of the active incoming call. The runtime
  answers that call with the modeled code (`-32800` in the sample).
- A handler can send requests and notifications to the remote peer while its call runs
  (`CallContext.request`, `CallContext.notify`). `CallContext.id` is the ID of the running call.
- Error codes: `-32700` for text that is not JSON, `-32600` for an invalid request, `-32601` for an
  unknown method, `-32602` for a `DecodeError` or a Pydantic `ValidationError`, `-32603` for other
  handler errors. A handler can raise `RpcError` with any code.
- `TranscriptLog` writes one JSON line for each message that the peer sends or receives:
  `{"dir":"send","message":<message>}`. The validator reads it with `--log-preset dir-message`.
- Diagnostics go to stderr through `logging`. The runtime never writes to stdout, because stdout is
  the stdio transport.

## Transports

- `stdio_connection()`: Content-Length framing on stdin and stdout. A reader ignores the headers
  that it does not know.
- `spawn_stdio(argv)`: starts a child process and connects to its stdin and stdout.
- `memory_pair()`: two connected in-memory ends, for tests.

## Checks

Run the checks from the repository root:

```shell
mise run test:runtime:python
```

The task runs `uv sync --locked`, `ruff format --check`, `ruff check`, `pyright` in strict mode and
`pytest`. All dependency versions are pinned in `pyproject.toml` and locked in `uv.lock`.

## Limits

The HTTP client reads at most `MAX_EVENT_BYTES` (16 MiB) of one event-stream line, of the joined
data of one event, and of one JSON response body. A larger response fails its call
(`StreamLimitError`, a `ConnectionError`), so a server that holds an event open cannot grow the
memory of the client. Pass `limit=` to `HttpClientConnection` for a different limit.
