# JSON-RPC code generation contracts

`moonrockz/smithy-codegen-jsonrpc` prepares a language-neutral description for
JSON-RPC generators. It has no language writer, runtime, file access, or network
access. It uses `moonrockz/smithy-validation/rpc` preparation for all RPC traits.
A bad contract raises the same preparation error as the validator.

Use `Description::for_service` for a `jsonRpc` service. It supplies the implicit
`client` and `server` peers. Use `Description::for_protocol` for a
`jsonRpcProtocol` structure. It supplies the modeled peers and session rules.
Both constructors select one declared JSON-RPC version.

`Description::peer` selects the service that a peer accepts and the service that
it calls. A peer can accept no service. An unknown peer returns `None`.

Each `ServiceDescription` has:

- `service`, the semantic service shape ID.
- `methods`, the prepared `MethodContract` values, in lexical wire name order.
  Each contract has its operation and input IDs, parameter mode, explicit
  positional member order, method kind, result selection, active call reference,
  and application errors. An error has its exact code, data selection, and
  required data flag. Notification methods keep their kind in the contract.
- `shapes`, the service closure in lexical shape ID order. The closure includes
  member shapes. Resolve a member's target in the semantic model before you use
  a list or map element. Keep the service `rename` map when you choose symbols.
- `values`, the prepared structure policies and member names for parameters,
  results, and error data. Nested structures are included. A member has its
  semantic shape ID, wire name, required flag, and critical path separator.
- `value_config`, the effective value codec config. It keeps the member name
  mode for union tags, the default timestamp format, and the other value options.

`Description.session` is a prepared `SessionContract`, or `None`. It gives the
states, capability sources and JSON Pointers, method lifecycle rules,
cancellation ID mappings and codes, state refusal codes, and capability refusal
code. The first state is the initial state. Cancellation ID mappings include the
wire member name and its positional index when the method supports positions.
A method's active call reference works with or without session rules.

The default generation config ignores unknown structure members. Pass a config
to change that default. The service `unknownMembers` trait overrides the config;
a structure trait overrides the service policy. These are the same precedence
rules that the validator uses. If you validate messages with the same config,
the checks and the description use the same effective policies. The regular
validator CLI keeps its default of rejecting unknown members.

The description keeps semantic IDs and prepared values. It does not parse trait
text a second time. The RPC package exposes detached snapshots through
`PreparedService::contracts`, `PreparedService::value_contracts`, and
`ProtocolDescription::session_contract`. Changes to snapshot arrays do not
change the prepared validator. The description does not retain the model.

All text order uses lexical comparison. Peer, method, shape, member, capability,
and refusal output is deterministic on wasm, wasm-gc, JS, and native. State
order and positional parameter order keep their declared meaning. Walks over
the model use explicit stacks in the code generation core.

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
        #|service Echo { version: "1", operations: [EchoValue] }
        #|@method(name: "echo", params: "named", kind: "request")
        #|operation EchoValue { input: Input, output: Input }
        #|structure Input { @required text: String }
      ),
    )
    .assemble()
  let description = @jsonrpc.Description::for_service(
    loaded.model.unwrap(),
    @smithy.ShapeId::parse("example#Echo").unwrap(),
    @rpc.V2_0,
  )
  let peer = description.peer(@rpc.PeerName::parse("client").unwrap()).unwrap()
  assert_eq(peer.accepts, None)
  assert_eq(peer.calls.unwrap().methods[0].name.to_string(), "echo")
  assert_eq(peer.calls.unwrap().methods[0].kind, @rpc.RequestOnly)
}
```

The sample in `examples/payment-terminal/` supplies two peer services and checked
transcripts. Language generators and runtimes belong to stages 3 to 5 of
`smithy-2qe.46`. No plugin is registered by this module. The Smithy CLI does not
import it.
