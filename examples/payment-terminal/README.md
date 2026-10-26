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
existing `openrpc` plugin. It writes them under `.dev/out/payment-terminal/`.

```shell
mise exec -- moon run apps/smithy --target native -- build --config examples/payment-terminal/smithy-build.json
```

Language generators and sample handlers belong to stages 3 to 5 of
`smithy-2qe.46`. This stage supplies the shared model and the hand-written
transcripts for those handlers.
