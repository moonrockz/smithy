# MoonBit JSON-RPC code generator

`moonrockz/smithy-codegen-moonbit` generates a MoonBit JSON-RPC 2.0 peer from a
Smithy model with `smithy.rpc` traits. The Smithy CLI registers it as the build
plugin `moonbit-jsonrpc-codegen`. The generator has no file access; the build
runner writes its files.

The generator reads the prepared contracts of
`moonrockz/smithy-codegen-jsonrpc`: methods, parameter modes, result selection,
modeled errors, structure member names, unknown member policies and session
rules. It does not read the RPC traits a second time, so the generated peer and
`smithy validate rpc` use the same rules.

## Settings

| Setting | Required | Meaning |
|---------|----------|---------|
| `service` | yes | The service shape ID. With `protocol`, a service of the protocol. |
| `protocol` | no | A `jsonRpcProtocol` structure. Without it, the service has the peers `client` and `server`. |
| `peer` | yes | The peer to generate. |
| `transports` | no | `stdio`, `http` and `websocket`. All by default. |
| `module` | yes | The MoonBit module name of the output, such as `example/terminal`. |

```json
{
  "version": "1.0",
  "sources": ["model.smithy"],
  "plugins": {
    "moonbit-jsonrpc-codegen::moonbit-terminal": {
      "service": "example.payments#PaymentTerminal",
      "protocol": "example.payments#TerminalProtocol",
      "peer": "terminal",
      "module": "example/terminal"
    }
  }
}
```

## Output

The output is one MoonBit module. The root package holds the generated code. The
package `rpc` is a copy of the runtime in `runtimes/moonbit/rpc`, which is real
MoonBit code with its own tests. `mise run runtime:embed` copies the runtime into
`runtime_files.mbt`, and `mise run validate` fails when the copy differs.

| File | Content |
|------|---------|
| `moon.mod` | The module name and `moonbitlang/async@0.22.5`. |
| `moon.pkg` | The import of the runtime package as `@rpc`. |
| `types.mbt` | A struct for each structure, an enum for each union and enum, each with `to_json` and `from_json`. |
| `errors.mbt` | A struct for each modeled error, the error type `ServiceError`, and the conversions to and from `@rpc.RpcError`. |
| `handler.mbt` | The trait `<Service>Handler` of the service that the peer accepts, and `register_<service>(peer, handler)`. |
| `client.mbt` | The typed client `<Service>Client` of the service that the peer calls. |
| `session.mbt` | `session_rules()` from the prepared session contract, and `new_peer(log?)`. |
| `session_test.mbt` | A test that builds the rules and a peer. |
| `rpc/` | The runtime. |

Type mapping: `String`, `Bool`, `Int` (byte, short, integer), `Int64` (long),
`Double` (float, double), `@rpc.Decimal` (bigDecimal), `@rpc.BigInteger`
(bigInteger), `Bytes` (blob, base64 text), `Json` (document), `@rpc.Timestamp`,
`Array[T]`, `Map[String, T]`, and `T?` for a member that is not required. A
decimal or a big integer keeps the exact text of its JSON number; no value goes
through a `Double`. Enums are closed: an unknown value is a decode error.

Names: fields and methods are `snake_case`, types are `PascalCase`, and enum and
union variants are `PascalCase` (`INSERT_CARD` is `InsertCard`). A MoonBit
keyword gets a `_` suffix. The service `rename` map applies through
`ServiceNames`. Two members or shapes with one MoonBit name are an error that
names both.

The modeled cancel method of the peer is not in its handler trait: the runtime
cancels the call and answers with the modeled code. A method with a
`jsonRpcRefersToCall` member is registered with `Peer::call_reference`.

## Example

```mbt check
///|
test {
  let loaded = @rpc.loader()
    .add_idl(
      "echo.smithy",
      (
        #|$version: "2"
        #|namespace example
        #|use smithy.rpc#jsonRpc
        #|use smithy.rpc#method
        #|@jsonRpc(versions: ["2.0"])
        #|service Echo { version: "1", operations: [Say] }
        #|@method(name: "say", params: "named", resultMember: "text")
        #|operation Say { input: SayInput, output: SayInput }
        #|structure SayInput { @required text: String }
      ),
    )
    .assemble()
  let files = @moonbit.run(
    @codegen.PluginContext::from_build(loaded.model.unwrap(), {
      "service": "example#Echo",
      "peer": "server",
      "module": "example/echo",
    }),
  )
  assert_true(
    files["handler.mbt"].contains(
      "async say(Self, SayInput, @rpc.CallContext) -> String raise",
    ),
  )
}
```

The sample in `examples/payment-terminal/` has golden output in
`generated/moonbit/`. `mise run codegen:payment-terminal` writes it, and
`mise run codegen:payment-terminal -- --check` fails when it is not current.
