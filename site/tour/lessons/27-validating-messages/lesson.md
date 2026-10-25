# Validating JSON-RPC messages

> **Our extension:** Standard Smithy has no command that checks a JSON-RPC message. This check is part of [moonrockz/smithy-validation](../../../../pkgs/smithy-validation/rpc/README.mbt.md). No Java reference exists for it.

This check compares one JSON-RPC message with a service of the model, as the command `smithy validate rpc --message` does. Here the service is `example#Calculator`, the version is 2.0, and the message is the request in `call.json`.

The trait `@method` gives the wire name of each operation ([lesson 22](../22-json-rpc/lesson.md)). The method `subtract` has the parameter mode `either`. It takes an array in the order of `positional`, or an object with the member names.

The Message findings tab shows one line for each finding. A line starts with the file name and the JSON pointer of the value. The start call has no findings.

Make these changes in `call.json` one at a time. Change the message back after each change.

- Change the params to `{"minuend": 42, "subtrahend": 23}`. The mode `either` accepts named parameters, so the tab shows no findings.
- Change `23` to `"23"`. The check does not change a string into a number, so the tab shows `call.json/params/1: error[TypeMismatch]` on `example#SubtractInput$subtrahend`.
- Change the params to `[42, 23, 5]`. The array has more items than `positional`, so the tab shows `InvalidParams` on `example#Subtract`.
- Change the method to `"multiply"`. The service has no such method, so the tab shows `UnknownMethod` at `/method`.
- Delete the line of `id` and the comma before it. A 2.0 message without an ID is a notification, and the tab shows no findings.

## On your computer

The `smithy` CLI and the MoonBit library run the same check on this model. The command prints nothing for a valid call. For the second call, it prints a `TypeMismatch` line and exits with the status 1. The tests of this repository run both blocks.

```include
CLI: apps/smithy/README.md#message-cli
MoonBit: pkgs/smithy-validation/rpc/README.mbt.md#message-api
```
