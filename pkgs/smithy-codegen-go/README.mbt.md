# Go JSON-RPC code generation

`moonrockz/smithy-codegen-go` writes a Go module for one JSON-RPC peer. Register
`plugin` as `go-jsonrpc-codegen` in a Smithy build runner. The Smithy CLI registers
this name. The generator works on native, wasm, wasm-gc, and JS. It returns text
files and does not access files, processes, or the network.

```json
{
  "version": "1.0",
  "plugins": {
    "go-jsonrpc-codegen": {
      "service": "example.payments#PaymentTerminal",
      "protocol": "example.payments#TerminalProtocol",
      "peer": "terminal",
      "module": "example/payments/terminal",
      "package": "payments",
      "transports": ["stdio", "http", "websocket"]
    }
  }
}
```

`service` is required. `protocol` selects a two-peer protocol. Without it, the
service has implicit `client` and `server` peers. `peer` defaults to `client`.
`module` defaults to `example/generated`. `package` defaults to `generated`.
`version` defaults to `2.0`, the supported version. `transports` checks the selected
transport names. The generated module includes all three transport adapters.
Unknown settings fail in lexical name order.

Use `run(PluginContext)` for an existing plugin context. Use
`generate(model, description, peer, module_name~, package_name~)` when a caller
already has a prepared `smithy-codegen-jsonrpc.Description`. `generate` does not
read RPC traits. The model supplies value shapes and service renames. The
description supplies methods, wire names, required members, unknown-member
policies, result and error selectors, and session rules.

## Generated API

The root package has `types.go`, `peer.go`, `contract.go`, and `errors.go`.
`NewPeer(Handlers, rpc.Options)` returns a peer. `Handlers` has one typed function
field for each accepted operation. A nil field leaves that handler unregistered.
The peer has a typed method for each operation that the other peer accepts.
Call `Serve(ctx, transport)` on the peer to start it. The embedded `rpc.Peer`
also supplies `Ready`, `Close`, `State`, and `HasCapability`.

An operation with input has an input argument. A unit input has no argument.
A notification or a null result returns `error`. Another request returns its
typed result and `error`. A selected result member returns that member's target
type. An operation that permits both kinds also has a `Notify` method with the
operation name as its suffix.

Structures have JSON tags. Optional members are pointers. Required members keep
their value type. Sparse lists and maps use pointer values to keep null entries.
Decoders check required members and apply the prepared policy
for unknown members. Union types are sealed interfaces. Each variant has a
`Value` field, for example `EntryMethodSwipe{Value: card}`. Generated decoders
read union members in structures, lists, maps, results, and error data.

Modeled error structures implement `error` and `RPCError() *rpc.Error`. Return
them from a handler to send the prepared code and data. Typed calls convert a
mapped error back to its modeled type. Use `errors.As` to inspect the result.
An unmapped error stays an `*rpc.Error`.
An absent optional selected error member omits the error data. A required
document member keeps JSON null as present data.

Custom simple types are aliases. `bigDecimal` uses `rpc.Number`; `bigInteger`
uses `rpc.Integer`. These types preserve exact JSON number text. No float carries
a big number. Documents use `json.RawMessage`. The default timestamp type is
`rpc.Number`, for epoch seconds. A prepared `DateTime` default uses `string`.
Core `timestampFormat` on a member has priority over its target's format. The
target format has priority over the prepared default. This rule also applies
to list and map members, union members, selected results, and error data.
Blobs use `[]byte` and JSON base64 encoding. Decoders reject null for an optional
primitive or enum member. A document member can hold null. Enums reject unknown
values on input and output.
Maps with enum keys check each key against its enum target on input and result
validation. Maps with string keys keep ordinary string keys.
All maps check entries in lexical key order to keep their first diagnostic stable.

The runtime applies the prepared lifecycle, capability, cancellation, and active
call rules. `rpc.RequestID(ctx)` reads a handler's exact request ID.
`rpc.PeerFromContext(ctx)` returns the runtime peer for a callback. `Contract()`
returns a fresh copy of the prepared runtime contract.

## Names and dependencies

The shared `ServiceNames` helper applies the rename maps of both protocol
services before Go casing. Exported names start with an uppercase letter.
An underscore starts the next word. An all-uppercase word becomes title case.
For example, `paymentId` becomes `PaymentId`, and `INSERT_CARD` becomes
`InsertCard`. The generator reports declaration and member name conflicts.
It does not change a rendered symbol name. `$T` and the shared package import
policy select the import aliases. Text order uses `lexical_compare`.

The generated `rpc/` package contains the real runtime source from `runtimes/go`.
Every runtime reference uses `<module>/rpc`. The runtime's `go.mod` and `go.sum`
supply the exact dependency pins. The generator changes only the module line.
The embedding check maintained with the runtime detects source drift.

Run `gofmt -w` on the generated Go files before a Go build. Then run `go build
./...`, `go vet ./...`, and `go test ./...`. Generation does not require Go.
The package golden fixture records generator output before Go formatting.

The fixture config at `fixtures/smithy-build.json` generates a separate value
codec module. Its Go tests check sparse entries, nested policies, null values,
and enum output. The payment codec fixture checks exact decimals, sealed unions,
modeled errors, and the prepared session contract.
