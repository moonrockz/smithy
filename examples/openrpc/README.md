# Export a service as OpenRPC

This example turns a JSON-RPC service in Smithy into an OpenRPC 1.3.2 document.
It shows two ways: the `build` command with the `openrpc` plugin, and a library consumer.

`model.smithy` defines the service `example.rpc#Calculator` with three operations:
`subtract`, `history` and `clear`. It uses `@jsonRpc`, `@method`, `@examples` and an `@rpcError` error.

## Build with the CLI

`smithy-build.json` selects `model.smithy` and the `openrpc` plugin for `example.rpc#Calculator`.
Run from the repository root:

```shell
mise exec -- moon run apps/smithy --target native -- build --config examples/openrpc/smithy-build.json
```

The command prints nothing and exits with status 0. It writes the document to
`.dev/out/openrpc/source/openrpc/openrpc.json`. The document has these values:

- `openrpc` is `1.3.2`.
- `info.title` is `Calculator`, and `info.version` is `2026-10-21`.
- `methods` has `clear`, `history` and `subtract`.
- `components.schemas` has the schemas that the methods reference.

## Export from a program

`main.mbtx` builds a smaller `example#Calculator` model, calls `@openrpc.convert_result` and prints the document.
The program uses only published modules (`moonrockz/smithy`, `moonrockz/smithy-validation/rpc` and `moonrockz/smithy-openrpc`).

Run it from the repository root:

```shell
mise exec -- moonx scripts/test-validation-consumer.mbtx --openrpc native
```

The script copies the program into an isolated module and runs it. It checks that the output is an OpenRPC
document with version `1.3.2` and one method. The output ends with these lines, and the exit status is 0:

```text
Isolated openrpc passed: native
Audited 11 resolved manifests within the consumer's dependency profile
```

To run all four targets, and the checks of the built document, run `mise run test:openrpc`.
