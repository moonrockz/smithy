# Go payment sample

The Go sample uses the generated POS and terminal packages. All card values are
masked test data. The handlers compare amounts with exact rational arithmetic.
They keep the original JSON number text in replies.

Run these commands from the repository root:

```shell
mise run jsonrpc:go:runtime
mise run codegen:go
mise run sample:build:go
mise run test:jsonrpc:go
mise run test:jsonrpc:matrix -- --caller go --receiver go
```

The quality task formats the temporary generated output with `gofmt`, then runs
`go build`, `go vet` and `go test`. The committed golden files keep the portable
generator output. The source runtime and handlers must pass the format check.

The build task writes executable paths in
`.dev/out/payment-terminal/commands/go.json`. You can also run the peers:

```shell
.dev/out/payment-terminal/bin/go-terminal serve --port 8080
.dev/out/payment-terminal/bin/go-pos --scenario payment --connect http://127.0.0.1:8080/rpc --log .dev/out/go-payment.jsonl
.dev/out/payment-terminal/bin/go-pos --scenario payment --connect ws://127.0.0.1:8080/ws --log .dev/out/go-payment-ws.jsonl
.dev/out/payment-terminal/bin/go-pos --scenario payment --connect stdio --log .dev/out/go-payment-stdio.jsonl -- .dev/out/payment-terminal/bin/go-terminal stdio
```

The scenarios are `payment`, `cancellation`, `errors` and `refusals`. Each POS run
checks its results and exits with status 1 on failure. The matrix task checks the
recorded log with `smithy validate rpc transcript` and the shared scenario
expectations. It writes results and the summary under `.dev/out/jsonrpc-matrix/`.

The [manual matrix guide](../INTEROPERABILITY.md) gives the full cross-language
commands, result format and build provenance rules.
