# Payment terminal protocol

This sample models a POS and a payment terminal with the `smithy.rpc` traits.
The `pos` peer accepts `PointOfSale`. The `terminal` peer accepts `PaymentTerminal`.
All card values are masked test data, such as `**** 4242`.

Run the commands from the repository root. The model uses the RPC traits that the CLI loads.

```shell
mise exec -- moon run apps/smithy --target native -- validate rpc transcript --protocol example.payments#TerminalProtocol examples/payment-terminal/model.smithy examples/payment-terminal/transcripts/payment.json
```

To check another scenario, replace `payment.json` with a file from this table.
The checker exits with status 0 for each file. A negative scenario has an `expect`
list with its exact findings. The checker must find those errors and no other errors.

| File in `transcripts/` | Behavior |
| --- | --- |
| `payment.json` | Initialize, pay, report progress, call the POS for a tip and signature, read a receipt, page through transactions, refund, void, and stop. Unknown input and result fields are ignored through the service policy. |
| `cancellation.json` | Cancel `payment.start` after progress. The terminal answers that call with the modeled cancellation code, then stops. The amount exceeds the exact integer range of a binary float. |
| `errors.json` | Check all six application errors, each card entry union member, and the declined and partially approved outcome union members. |
| `refusals.json` | Refuse a call before initialization, refuse a payment without its capability, and refuse a call after shutdown. Each error reply uses the code in the model. The sender violations remain expected findings. |
| `invalid-kinds-and-progress.json` | Reject a notification sent to a request method, progress for an unknown call, and a request sent to a notification method. The notification method needs no response. |

`tests/payment-terminal` checks the model and all transcripts on JS and native in
`mise run test`. The amounts use `bigDecimal`. The signature uses a base64 blob.
Transaction records use timestamps, lists, and maps. The receipt has nested
structures and optional fields.

The session starts in `starting`. A successful `terminal.initialize` moves it to
`initializing`. The `terminal.initialized` notification moves it to `ready`.
`payment.start` moves it to `paying` until a result or error moves it to `ready`.
`terminal.shutdown` moves it to `stopping`, and `terminal.exit` moves it to
`stopped`. `terminal.ping` is valid in every state.

The initialize result advertises payment, swipe, chip, contactless, PIN, tips,
signature, progress, and cancellation capabilities. The `payment` capability
gates `payment.start`. The POS callbacks and control notifications have their
own capability rules. The card entry choice stays part of the payment input.

The build file exports the two accepted services as OpenRPC documents with the
`openrpc` plugin, and generates the MoonBit and Python peers. It writes them
under `.dev/out/payment-terminal/`.

```shell
mise exec -- moon run apps/smithy --target native -- build --config examples/payment-terminal/smithy-build.json
```

## Generated peers

`generated/` holds the golden output of the generators. The golden files change
only on purpose: `mise run codegen:payment-terminal` writes them, and
`mise run codegen:payment-terminal -- --check` fails when they are not current.

| Directory | Plugin | Peer |
| --- | --- | --- |
| `generated/moonbit/pos` | `moonbit-jsonrpc-codegen::moonbit-pos` | `pos`, module `example/pos` |
| `generated/moonbit/terminal` | `moonbit-jsonrpc-codegen::moonbit-terminal` | `terminal`, module `example/terminal` |
| `generated/python/pos` | `python-jsonrpc-codegen::python-pos` | `pos`, package `payment_pos` |
| `generated/python/terminal` | `python-jsonrpc-codegen::python-terminal` | `terminal`, package `payment_terminal` |

`moonbit/` holds the hand-written MoonBit sample: the terminal rules, the POS
scenarios and the executables `pos_main` and `terminal_main`. `python/` holds
the Python sample. `mise run sample:build:moonbit` and
`mise run sample:build:python` build them and write the command manifests
`.dev/out/payment-terminal/commands/<language>.json`
(`{"pos": [argv], "terminal": [argv]}`, absolute paths).

## Sample programs

Each language has the same command line, so a POS of one language can use a
terminal of another.

- Terminal: `<terminal> stdio [--log PATH]` uses Content-Length frames on
  stdin and stdout. `<terminal> serve --port N [--log PATH]` serves `POST /rpc`
  and `GET /ws` on 127.0.0.1:N, and writes `listening N` to stderr when it is
  ready.
- POS: `<pos> --scenario NAME --connect TARGET [--log PATH] [-- TERMINAL...]`.
  TARGET is `stdio` (the POS starts the terminal command after `--`),
  `http://127.0.0.1:N/rpc` or `ws://127.0.0.1:N/ws`. The POS exits with 0 when
  every check of the scenario passes.
- `--log PATH` writes one JSON line for each message:
  `{"dir": "send" | "recv", "message": ...}`, from the view of the writer.
  Diagnostics go to stderr only.

HTTP follows the Streamable HTTP style. The client posts each message to
`/rpc`. The server answers a request with a `text/event-stream` response: the
notifications and requests of its handler come first, then the response. The
client answers a request from the server with a new POST. The server sets
`Smithy-Session-Id` on its responses, and the client sends it on each later
POST. WebSocket carries one message in each text frame.

Check a log with one command. Swap the two `--direction` values for a terminal
log.

```shell
smithy validate rpc transcript --protocol example.payments#TerminalProtocol --version 2.0 \
  --log-preset dir-message --direction send=pos --direction recv=terminal --complete \
  --expect examples/payment-terminal/scenarios/<scenario>.expect.json \
  examples/payment-terminal/model.smithy <log.jsonl>
```

`mise run test:payment-terminal` runs the MoonBit POS against the Python
terminal over stdio for each scenario, and checks the POS log and the terminal
log. Normal CI runs it. The manual matrix workflow runs every pair of languages
over every transport.

## Scenarios

All amounts are in USD, and the card is `**** 4242`. The terminal rules depend
only on the input:

| Amount cents | Terminal answer |
| --- | --- |
| `.13` | `CardDeclined`, data `"test decline"` |
| `.14` | `CardRemoved`, no data |
| `.15` | `TerminalBusy`, data `{"retryAfterSeconds": 1}` |
| `.16` | `Timeout`, no data |
| `.17` | Progress `insertCard`, then a wait for `$/cancelRequest` |
| `.21` | Outcome `declined` with reason `test decline` |
| `.22` | Outcome `partiallyApproved` with 1.00 |
| other | Progress `insertCard` and `enterPin`, `pos.confirmTip` with 2.50, `pos.requestSignature`, `pos.display`, progress `authorizing`, outcome `approved` with `TEST-OK` |

A POS name that ends with `(no payment)` gets `capabilities: {"payment": false}`.
The terminal keeps approved payments for status, receipt, refund and void. A
receipt has the merchant `Test shop` at `Test street`, the lines `Test item` (the
paid amount) and `Test tip` (2.50), the exact total of the two, and
`customerCopy: true`. Each page of transactions lists the kept payments with
`createdAt` 1792886400 and the labels `checkout: test` and `card: **** 4242`; the
first page has `nextToken: test-page-2`, and the page for that token is empty. A
refund over the paid amount gives `RefundExceedsAmount` with the paid amount as
`maximum`. An unknown payment gives `PaymentNotFound`. The POS answers
`pos.confirmTip` with `true` and `pos.requestSignature` with the base64 text of
`test-signature`.

| Scenario | POS steps |
| --- | --- |
| `payment` | Ping, initialize, pay 20.00 with the callbacks, status, receipt, two pages of transactions, refund 2.50 (the POS checks the exact text `2.50`), void, shutdown, exit. |
| `errors` | Pay 1.13, 1.14, 1.15 and 1.16 (each modeled error and its data), 1.21 and 1.22 (the outcomes), pay 12345678901234567.00, refund 12345678901234568.00 (the POS checks the exact `maximum` 12345678901234567.00), void an unknown payment, shutdown, exit. |
| `cancellation` | Pay 12345678901234567.17. On the first progress, the POS sends `$/cancelRequest`, and the terminal answers the payment with `-32800`. Shutdown, exit. |
| `refusals` | Each refusal twice: first a checked call, which the POS refuses locally with the modeled code and does not send; then an unchecked call, which the terminal refuses with the modeled code. `payment.status` before initialize (1007), `payment.start` without the payment capability (1008), `payment.status` after shutdown (1007). The log has three expected sender findings, in `scenarios/refusals.expect.json`. |
