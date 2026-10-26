# Go JSON-RPC runtime

This package runs generated Smithy JSON-RPC 2.0 peers. The generator copies the
source files into `rpc/` in its output. Generated code imports `<module>/rpc`.
This directory is also a standalone Go module for runtime tests.

The runtime uses `go.lsp.dev/jsonrpc2 v1.0.1` for dispatch, response correlation,
and stdio framing. It uses `github.com/coder/websocket v1.8.14` for WebSocket.
These versions were checked against their published modules. Go 1.26 or later is
required. The repository pins Go 1.27.3.

Run the quality checks from this directory:

```sh
gofmt -w *.go
go build ./...
go vet ./...
go test -race ./...
```

## Peer API

`NewPeer(contract, localPeer, options)` creates one peer for one connection or
HTTP session. `Contract` contains two `PeerContract` values and an optional
`SessionContract`. The generated contract comes from the prepared Smithy RPC
description. Do not change a contract after you pass it to `NewPeer`.

`Register(method, handler)` sets a handler for a method that the local peer
accepts. A `Handler` receives `context.Context` and `json.RawMessage`. It returns
the wire result or an error. `Bind[I, O]` adapts a typed Go function to a handler:

```go
err := peer.Register("echo", rpc.Bind(func(ctx context.Context, input EchoInput) (EchoOutput, error) {
    return EchoOutput{Text: input.Text}, nil
}))
```

`Bind` ignores unknown object members. Generated validators supply the modeled
member policy and the value constraints through `ValidateParams`,
`ValidateResult`, and `ValidateData`. The dispatcher converts positional
parameters to a named object before it calls the validator and handler. Pass
an array to `Call` or `Notify` for a positional method. Generated wrappers apply
`resultMember` selection. The runtime enforces `NullResult`.

Start `Serve(ctx, transport)` in a goroutine, then wait for `Ready()` before you
call the other peer. `Serve` can run once. It stops when the context is canceled
or the transport ends. `Close` closes the transport and cancels active handlers.
Handlers must stop when their context is canceled.

`Call(ctx, method, params, &result)` waits for a response. `Notify` sends a
notification. Both check the method kind, parameter form, lifecycle state,
capabilities, and active call references before they send. The receiver checks
the same rules. `CallUnchecked` skips local state and capability checks for wire
refusal tests. It still checks the method and parameters and tracks the reply.

`CallWithID(ctx, id, method, params, &result)` uses a caller-selected ID.
`StringID(text)` creates a string ID. `IntegerID(text)` validates an exact
integer ID. The runtime preserves incoming string and integer values, including
integers larger than `int64`. Integral decimal and exponent notation is valid.
It correlates equal integer values without expanding the exponent.

`RequestID(ctx)` returns the exact ID of the current request.
`PeerFromContext(ctx)` returns its local peer. A handler can use this peer to
send progress or call the other peer. Admission and lifecycle transitions run
in receive order. Handlers then run concurrently, so callbacks and cancellation
do not block the reader.

## Session rules and errors

The first session state is the initial state. `MethodRule` names the receiving
peer, allowed states, transitions, required capabilities, and cancellation rule.
A successful source result advertises a capability when its JSON Pointer names
a value other than absent, null, or false. State and capability refusals use the
codes in the contract. A refused call applies no transition.

A cancellation notification cancels the context of its sender's active call.
If the handler returns `context.Canceled`, the runtime sends the modeled
cancellation code. A canceled local call context sends the modeled cancellation
notification. Cancellation of an inactive call has no effect. Progress must
name an active call from its receiver.

Return `*rpc.Error` or a modeled error that implements both `error` and
`RPCError() *rpc.Error`. `NewError(code, message, data)` encodes optional error
data. `Error.Data` keeps exact JSON bytes. Error and contract codes use `int64`.
A generator must reject a modeled code outside that range. The runtime checks
modeled data requirements and validators. Other application errors become
`-32603`. Error data never passes through a float.

## Transports

`Stdio(reader io.ReadCloser, writer io.Writer)` uses the upstream
`Content-Length` frame reader and writer. It ignores unknown headers. Closing
the transport closes the reader. Use stdin and stdout for messages. Write
application diagnostics to stderr.

Mount `NewHTTPHandler(factory)` at `/rpc`. The `PeerFactory` creates a peer and
registers its handlers for each new session. Call the returned `HTTPServer`'s
`Close` method when the server stops. It retains up to 1024 sessions by default.
Set `MaxSessions` before serving to change this limit.

The first POST creates a session. Each response includes `Smithy-Session-Id`.
The client sends this header on later POSTs. An unknown session gets HTTP 404.
Requests get HTTP 200 with an SSE stream. The stream starts with a `: open`
comment and a blank line to flush the headers. Each event has `event: message` and
one JSON-RPC message in `data`. Progress and callbacks precede the final reply.
The final reply ends that stream. Notification and callback-response POSTs get
HTTP 202 with an empty body. The client answers each callback with a new POST.
Session state is shared across all these POSTs.

A server message uses its parent request stream when that stream is open.
An unbound server request or notification uses the latest open stream. If no
stream is open, the session queues up to 32 messages for the next request
stream. Queued messages arrive before that request's reply. A full queue
returns an error. Final replies always use their original request stream.
The dispatcher still checks lifecycle rules and active call references before
it queues a message.

`NewHTTPTransport(url, client)` creates the client transport. A nil client uses
`http.DefaultClient`. It accepts JSON responses and SSE, including multiline
SSE data. Each request response must contain the final reply with that request's
exact ID. An SSE stream that ends before this reply, a JSON callback in place
of the reply, or HTTP 202 for a request fails the transport and its pending
calls. `SessionID()` returns the current session ID. Pass both
`application/json` and `text/event-stream` in the Accept header when you use a
different HTTP client.

Mount `NewWebSocketHandler(factory)` at `/ws`. Use
`DialWebSocket(ctx, url)` on the calling side. Each text frame contains one
JSON-RPC message. Binary frames are rejected. Each connection has a separate
peer and session state. WebSocket does not use the HTTP session header.

Every transport uses the same dispatcher. The runtime never sends batches.
A received batch gets one `-32600` response with a null ID. Messages are limited
to 1 MiB. This limit also applies to the full SSE data payload, including
newline bytes between data lines. The client rejects an oversized event before
its delimiter or EOF. Active calls are limited to 1024 per direction by default. Set
`Options.MaxActiveCalls` to change the call limit.

## Exact values and logs

`Number` stores Smithy `bigDecimal` as exact JSON number text. `Integer` stores
Smithy `bigInteger` as exact integral JSON number text. Use their validated
constructors at input boundaries. Both types reject strings, null, and invalid
number syntax. Neither type converts through `float64`. `Decode` uses
`json.Number` for document values and rejects trailing JSON values.

Logging is off by default. Set `Options.Log` to stderr or an explicit transcript
file. The runtime rejects stdout as a log destination. Each JSONL row has
`dir: "send"` or `dir: "recv"` and a `message` JSON value. Direction is relative
to the peer that writes the log. For a POS caller log, check it with
`--log-preset dir-message --direction send=pos --direction recv=terminal`.
The runtime writes no other logs.
