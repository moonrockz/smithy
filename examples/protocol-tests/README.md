# Validate HTTP protocol test cases

This example shows a model with Smithy HTTP protocol tests, and how the CLI checks them.

`greeting.smithy` defines a custom protocol `example#fixtureProtocol` and the operation `Greet`.
The operation has one `@httpRequestTests` case (`GreetingRequest`) and one `@httpResponseTests` case
(`GreetingResponse`). The request case sets the method, the URI, the headers, the body and the `params`.

Run from the repository root:

```shell
mise exec -- moon run apps/smithy --target native -- validate --protocol-tests examples/protocol-tests/greeting.smithy
```

The option `--protocol-tests` loads the Smithy protocol test traits. The command prints nothing and exits with
status 0 when the test cases are valid.

To see a finding, copy the file and change `params: {name: "Ada"}` to `params: {name: 1}`. The command then exits
with status 1 and prints:

```text
[ERROR] example#Greet: smithy.test#httpRequestTests.0.params: Error validating value/name: Expected string value for `smithy.api#String`. | HttpRequestTestsInput
```

The check covers the trait fields, `appliesTo`, duplicate test ids, and `params` and `vendorParams` against
the input, output or error shape.

To run the cases against a protocol implementation, use the `moonrockz/smithy/protocoltests` library.
See [HTTP protocol test suites](../../pkgs/smithy/protocoltests/README.mbt.md).
The CLI does not run the cases. It only checks that they are valid.
