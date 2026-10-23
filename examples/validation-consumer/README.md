# Validate a JSON value from a library consumer

This example validates JSON against a Smithy shape from a MoonBit program.
The program uses only the published `moonrockz/smithy` and `moonrockz/smithy-validation` modules.
It does not use the Smithy workspace.

`main.mbtx` does four things:

1. It loads a model with `@smithy.Loader` and assembles it. The model has `integer Count` with `@range(min: 1, max: 100)`
   and `structure Input { @required count: Count }`.
2. It prepares a validator for `example#Input`.
3. It validates `{"count":2}`. The value is valid.
4. It validates `{"count":0}`. The value is not valid, and the first finding has the code `Range`.

Run it from the repository root:

```shell
mise run test:validation-consumer
```

The task copies the program into an isolated module. It resolves the Smithy modules from local package archives.
It then runs the program on the native, wasm, js and wasm-gc targets. It checks that the program prints this line:

```text
valid=true invalid=Range at /count
```

The task also runs [`rpc-consumer`](../rpc-consumer/README.md).

To run one target, name it after the script:

```shell
mise exec -- moonx scripts/test-validation-consumer.mbtx native
```

The expected output is:

```text
Isolated validation-consumer passed: native
Audited 8 resolved manifests within the consumer's dependency profile
Isolated rpc-consumer passed: native
Audited 8 resolved manifests within the consumer's dependency profile
```

The script exits with status 0 when every check passes. It exits with a non-zero status when one check fails.
The `Audited` line shows that the program depends on the model and validation modules only.
