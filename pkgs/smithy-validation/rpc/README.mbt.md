# JSON-RPC request validation

Validate one JSON-RPC 1.0 or 2.0 request or notification against a Smithy service.
The library reports findings and never executes handlers or sends responses.

## Library

Use `rpc.loader()` to opt in to the bundled `smithy.rpc` trait definitions, or add
`rpc.trait_definitions()` to an existing loader. Models may be IDL or Smithy JSON AST.
The ordinary Smithy loader does not automatically install these optional traits.

```mbt check
///|
test {
  let loaded = @rpc.loader()
    .add_idl(
      "api.smithy", "$version: \"2\"\nnamespace example\nuse smithy.rpc#jsonRpc\nuse smithy.rpc#method\n@jsonRpc(versions: [\"2.0\"])\nservice Api { version: \"1\", operations: [Ping] }\n@method(name: \"ping\", params: \"either\", positional: [])\noperation Ping {}\n",
    )
    .assemble()
  let service = @rpc.PreparedService::prepare(
    loaded.model.unwrap(),
    @smithy.ShapeId::parse("example#Api").unwrap(),
    @rpc.V2_0,
  )
  let result = service.validate_request(
    "{\"jsonrpc\":\"2.0\",\"method\":\"ping\"}",
  )
  assert_true(result.is_valid())
  assert_eq(result.kind, Some(@rpc.Notification))
}
```

Prepare once and reuse the service snapshot. `validate_request` parses bounded JSON text,
rejects duplicate decoded keys and preserves exact numbers. `validate_json` accepts in-memory
JSON; it cannot recover precision lost by an earlier parser. IDs distinguish absent from
present values and retain legacy structured IDs as exact `NodeValue` data.

The `jsonRpc` service trait declares supported versions. Every operation reachable through
the service or its resources needs a `method` trait with a nonempty unique wire name and
`params` mode `named`, `positional` or `either`. Positional-capable methods must declare a
complete `positional` array of Smithy input member names, even for an empty input. This order
never comes from map iteration. Named-only methods cannot belong to services declaring 1.0.
The `rpc.` namespace is reserved and this profile provides no system extensions.

`resultMember` selects an output member contract; `nullResult: true` selects a null result.
The default is the output structure. Preparation checks selectors and exposes them with
`result_selection`, but this entry point does not validate responses. The bundled `rpcError`
trait reserves error-mapping syntax for the later contextual response validator; application
error codes and data mappings are not prepared or checked by this request slice.

## CLI

From the repository root:

```sh
smithy validate rpc --version 2.0 --service example#Calculator \
  --message examples/json-rpc/call.json examples/json-rpc/calculator.smithy
smithy validate rpc --version 2.0 --service example#Calculator \
  --message examples/json-rpc/invalid.json --diagnostics json examples/json-rpc/calculator.smithy
```

The first succeeds quietly. The second exits 1 with `TypeMismatch` at `/params/1`, associated
with `example#SubtractInput$subtrahend` and operation `example#Subtract`. A message or model may
use stdin `-` once; stdin models require `--from idl` or `--from json`. Model arguments and
options follow `validate rpc`. Use `smithy validate rpc --help` for nested command help.
`smithy validate model.smithy` continues to validate model definitions.

JSON diagnostics go to stdout. Text findings go to stderr, including advisory severity.
Invalid messages, malformed JSON, I/O errors, invalid models and incomplete checks exit 1.
Invalid usage, service contracts and unsupported constraint configurations exit 2.

## Version and parameter policies

| Concern | 1.0 | 2.0 |
|---|---|---|
| Version selection | Explicit 1.0; `jsonrpc` marker rejected | Explicit 2.0; literal `"jsonrpc":"2.0"` required |
| Params | Required positional array | Omitted, object or array, subject to method mode |
| Notification | Present null ID | Absent ID |
| Call ID | Any nonnull JSON value | String, number or null |
| Recommendations | None for legacy ID types | Null and fractional IDs produce advisories, not errors |

Named parameters use Smithy member names by default. `--member-names json` uses `jsonName`.
Positional order always names Smithy members; findings retain original array positions,
including missing required argument slots. Trailing optional arguments may be omitted.
Interior slots must contain values satisfying their member contracts. Omitted 2.0 params
means an empty input and still checks required members.

The generic validator supplies required/type/range/length/pattern/enum/collection checks,
null/default/sparse policies and exact numeric validation. It inserts no defaults and performs
no coercion. Unknown input members are rejected unless `--unknown-members ignore` is selected.
Unknown envelope extension fields are ignored. These are separate policies.

Findings have stable codes, severity, structured paths, semantic shape/member IDs, optional
operation IDs and parse offsets in UTF-16 code units. `kind` can classify an unknown method's
notification independently of validation success. `is_valid()` requires completion and no
error findings; advisories do not invalidate a message.

## Limits and scope

The shared text parser caps input at 16 MiB UTF-8 and depth 128. Each request first runs a
bounded document check over the entire envelope, including IDs and ignored extensions, then
a bounded input check over mapped parameters. Each pass uses the configured generic limits.
The combined report is capped by the configured finding limit and reports incomplete checks.
See the [value profile](../README.mbt.md) for default limits and unsupported constraints,
including runtime contract conditions and regex features.

Response objects and top-level arrays produce `UnsupportedMessage`. Contextual responses,
error payloads, batches, exchange correlation and transport behavior belong to later slices.
The package introduces no Ion, WIT, WAC, wasm-devkit or JSON Schema conversion dependencies.
`mise run test:validation-consumer` builds separate packaged JSON and RPC consumers, audits
their resolved dependency manifests and runs both examples on all four targets.

The [shared design](../JSON_RPC_DESIGN.md) records the remaining integration contracts.
