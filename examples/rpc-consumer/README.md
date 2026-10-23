# Validate JSON-RPC messages from a library consumer

This example validates JSON-RPC 2.0 requests, responses and batches from a MoonBit program.
The program uses the published `moonrockz/smithy` module and the `moonrockz/smithy-validation/rpc` package.
It does not use the Smithy workspace.

`main.mbtx` defines a service `example#Api` with one operation, `count`. The operation takes one positional
parameter, `value`, with `@range(min: 1)`. The program then checks these messages:

- A request with `params: [2]` and the id `9007199254740993` is valid. The id is larger than 2^53.
  The library keeps it exact.
- A request with `params: [0]` is not valid. The first finding points to `/params/0`.
- A response with the same id as the request is valid.
- A response with the id `9007199254740992` is not valid. Its finding has the code `IdMismatch`.
- A batch of two requests is valid. A batch of two responses in the other order is valid too.
  The result entries name the request index of each response.
- A batch of notifications has no response. The program accepts an absent response and rejects `[]`.

Run it from the repository root:

```shell
mise run test:validation-consumer
```

The task copies the program into an isolated module and runs it on the native, wasm, js and wasm-gc targets.
It checks that the program prints this line:

```text
rpc valid=true invalid=Range at /params/0
```

The same task also runs [`validation-consumer`](../validation-consumer/README.md).

To run one target, name it after the script:

```shell
mise exec -- moonx scripts/test-validation-consumer.mbtx native
```

The output has one `Isolated rpc-consumer passed: native` line, and the script exits with status 0.
It exits with a non-zero status when a check fails.

To check messages from the command line, use `smithy validate rpc`. See the [JSON-RPC example](../json-rpc/README.md).
