# Transcripts

> **Our extension:** Smithy defines no JSON-RPC transcripts. The check is part of [moonrockz/smithy-validation](../../../../pkgs/smithy-validation/rpc/README.mbt.md). No Java reference exists for it.

A transcript is a conversation between the two peers of a `@jsonRpcProtocol` structure ([lesson 22](../22-json-rpc/lesson.md)). Here the protocol is `example#WeatherProtocol`. The client calls `weather/forecast` on the server, and the server sends the alert `weather/alert` to the client.

In `exchange.json`, each entry names its sender in `from` and holds one message. The receiver is the other peer.

Select the Transcript tab and click Step: the checker reads one entry. Run all reads the rest. The start transcript is valid. The checker matches a reply with its call by the caller, the responder and the exact ID.

Make these changes one at a time. Change the transcript back after each change.

- Delete the last entry and the comma before it. After one Step, the checker shows no finding yet. At the end, it reports `MissingResponse` on entry 0. The transcript is complete (`"complete": true`), so each call needs a reply.
- Delete the last entry again, and set `"complete": false`. The call is now outstanding. The finding is the advisory `OutstandingCall`, and the transcript stays valid.
- Change the ID of the reply to `2`. The reply matches no call, so the checker reports `UnsolicitedResponse` on entry 2. The call has no reply, so it also reports `MissingResponse` on entry 0.
- Change the sender of the alert to `client`. The server receives the alert, and its service `WeatherApi` has no method `weather/alert`. So the checker reports `UnknownMethod` on entry 1.

## On your computer

The CLI and the MoonBit library run the same check on this model and this transcript. The tests of this repository run both blocks.

```include
CLI: apps/smithy/README.md#transcript-cli
MoonBit: pkgs/smithy-validation/rpc/README.mbt.md#transcript-api
```
