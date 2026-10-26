module example/payment-sample

go 1.26

require (
	example/payments/pos v0.0.0
	example/payments/terminal v0.0.0
)

require (
	github.com/coder/websocket v1.8.14 // indirect
	github.com/go-json-experiment/json v0.0.0-20260601182631-00ed12fed2a6 // indirect
	go.lsp.dev/jsonrpc2 v1.0.1 // indirect
)

replace example/payments/pos => ../generated/go/pos

replace example/payments/terminal => ../generated/go/terminal
