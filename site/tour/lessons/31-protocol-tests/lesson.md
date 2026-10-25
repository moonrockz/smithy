# Protocol tests

A protocol defines how a message goes on the wire. [Protocol compliance tests](https://smithy.io/2.0/additional-specs/http-protocol-compliance-tests.html) help to make sure that a client or a server follows its protocol. They are two traits: [`@httpRequestTests`](https://smithy.io/2.0/additional-specs/http-protocol-compliance-tests.html#httprequesttests) on an operation, and [`@httpResponseTests`](https://smithy.io/2.0/additional-specs/http-protocol-compliance-tests.html#httpresponsetests) on an operation or an error structure. Each trait holds a list of cases.

A request case names the protocol under test. It gives the HTTP method, the URI, the headers and the body of the request. Its `params` are the input values of the request. A response case gives the status code, and its `params` are the output or error values.

The command `smithy validate` checks the cases when you add the option `--protocol-tests`. The option loads the `smithy.test` traits. The check validates `params` against the input shape of the operation. So a wrong `params` value gives the error `HttpRequestTestsInput` on the operation.

The CLI does not run the cases. The library [moonrockz/smithy/protocoltests](../../../../pkgs/smithy/protocoltests/README.mbt.md) lists them, and compares the messages of a protocol adapter that you supply. This runner is part of this project.

This lesson does not run in the browser. The blocks below show the CLI and the MoonBit library on the greeting model of the example [protocol-tests](../../../../examples/protocol-tests/README.md). The tests of this repository run them. In the second model, the request case has `params: {name: 1}`. The member `name` targets `String`, so the check gives one error.

```include
CLI: apps/smithy/README.md#protocol-tests-cli
MoonBit: pkgs/smithy/protocoltests/README.mbt.md#protocol-tests-api
```
