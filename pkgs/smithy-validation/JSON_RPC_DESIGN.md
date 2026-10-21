# JSON-RPC integration contract

This is the shared design for Smithy value validation, JSON-RPC modeling/message checks, optional Ion
validation and OpenRPC export. Direct JSON value validation is implemented in this module and the
`validate value` CLI. The `rpc` package implements opt-in JSON-RPC trait definitions, prepared
methods, request/notification and contextual response/error validation through `smithy validate rpc`.
Batches, exchanges and the Ion adapter remain follow-on capabilities. The separate
`moonrockz/smithy-openrpc` module implements description export through a library and build plugin.
See the [message validator](rpc/README.mbt.md) for executable examples and implemented boundaries.

The goal is to define an API in Smithy and check actual messages against it. A description export is
a separate deliverable. Model assembly validates definitions; instance validation checks application
data; envelope validation checks protocol structure; exchange validation checks supplied relationships.
No isolated message check can establish transport delivery or prove that a peer remained silent.

## Dependencies and delivery

| Work | Deliverable | Prerequisite |
|---|---|---|
| smithy-2qe.34.1 | Shared method/value/format contracts and rule matrix | Design review |
| smithy-2qe.34.3 | Direct JSON value validation, reusable API and CLI | Shared value contract |
| smithy-2qe.34.4 | Requests and notifications | Generic validator and prepared methods |
| smithy-2qe.34.6 | Contextual successful/error responses | Request/method contract |
| smithy-2qe.34.7 | Versioned batches | Request and response validators |
| smithy-2qe.34.8 | Explicit exchanges/transcripts | Response and batch validators |
| smithy-2qe.34.2 | OpenRPC export | Shared method/schema contract, independently of runtime validation |
| smithy-2qe.34.5 | Native Ion value validation | Generic engine and adapter contract |

`moonrockz/smithy-validation` depends inward on the model/syntax modules and core libraries.
JSON-RPC and OpenRPC consumers must not acquire Ion, WIT, WAC or wasm-devkit dependencies.
The Ion adapter belongs in its own publishable module with an Ion dependency; WIT conversion belongs
in another module using the separately published `moonrockz/wit`. Subpackages within one module do
not isolate module dependencies. The CLI may compose optional capabilities at the app layer.

Qualify these boundaries with isolated packaged consumers, not workspace imports: JSON validation
without Ion/WIT, later Ion validation without WIT, and later WIT conversion without Ion. Keep
cross-integration tests out of the core published manifest. New modules follow shared-version and
publication conventions.

## Shared value contract

See [the executable library examples and policies](README.mbt.md) and [engine design](DESIGN.md).
The generic validator selects a typed ShapeId, snapshots reachable contracts and supports repeated
read-only validation without a service or schema conversion. Findings preserve classification,
severity, semantic member IDs and structured instance paths. Numbers remain exact; input is never
silently coerced, normalized, defaulted or mutated. Limits produce an explicitly incomplete result.

For a trait ID, an explicit member trait replaces that target trait as a whole; otherwise it inherits
the target trait. Required/null/unknown/default/sparse/union/naming policies are explicit. Selected
result and error-data members must use their effective member contract, including overrides, rather
than validating only the unconstrained target shape.

ValueView inspects one source node at a time. Its neutral NativeScalar payloads distinguish typed
null, binary float, exact decimal token, native timestamp, symbol and binary data. Annotated values
and sexps remain distinct. Object fields retain occurrence identity. LocatedObject explicitly maps
logical members onto original source locations; a positional parameter can therefore report
`/params/0` while naming `example#Input$count`. Base paths compose structurally, not by rewriting
rendered pointer strings. Unsupported mappings produce findings, not a JSON round trip.

## Method modeling

ProtocolVersion has exactly V1_0 and V2_0, corresponding to the published JSON-RPC 1.0 and 2.0
specifications. Do not infer a version or imply support for 1.1 drafts. Keep these versions distinct
from Smithy RPC v2 JSON, OpenRPC document versions and JSON Schema dialects.

The opt-in `smithy.rpc` trait model supplies:

| Trait | Contract |
|---|---|
| Service `jsonRpc` | Explicit supported versions. |
| Operation `method` | Nonempty wire name, parameter mode named/positional/either, explicit positional input-member order, and result selection. |
| Error `rpcError` | Integer application code and error-data selection. |

Inputs and outputs remain Smithy structures. Result selection is OutputStructure, OutputMember or
Null. `resultMember` selects a member contract so its wire result may be scalar, array, object or
null. Without a selection, output is the whole output structure. A conflicting result selector is
invalid. Error data similarly selects the whole error structure by default, a named member, or an
explicit absent-data mode. A data member selector cannot coexist with absent-data mode.

Request preparation rejects duplicate wire names, undeclared result member selectors, incomplete
or repeated positional ordering and mappings incompatible with a declared protocol version.
Preparation also rejects duplicate/reserved application codes and invalid error-data
selectors. Application methods cannot use reserved `rpc.` names. Supported system
extensions require explicit preparation rather than automatic acceptance of a reserved name.

Named parameters use the chosen Smithy/jsonName policy. Positional order is a complete explicit
list, never map iteration order. Missing trailing optional arguments are permitted; required ones
must be present. Interior omissions require explicit values satisfying the selected null policy.
For 2.0, omitted params means no arguments. For 1.0, params is always a positional array, including
an empty one. A named-only method cannot claim a usable 1.0 mapping.

The trait syntax is:

```smithy
$version: "2"
namespace example
use smithy.rpc#jsonRpc
use smithy.rpc#method

@jsonRpc(versions: ["1.0", "2.0"])
service Calculator { version: "1", operations: [Subtract] }

@method(name: "subtract", params: "either",
    positional: ["minuend", "subtrahend"], resultMember: "value")
operation Subtract { input: SubtractInput, output: SubtractOutput }
structure SubtractInput {
    @required
    minuend: Integer
    @required
    subtrahend: Integer
}
structure SubtractOutput { @required value: Integer }
```

With that contract, `[42,23]` is valid positional input in either version. In 2.0,
`{"minuend":42,"subtrahend":23}` is also valid. `[42,"23"]` fails at `/params/1` on
`example#SubtractInput$subtrahend`. Result `19` validates against `SubtractOutput$value`; result
`"19"` fails that member. `@rpcError(code: 1001, dataMember: "detail")` selects a modeled error's
detail member for application error data. A Null result selection validates a null success payload
independently of whether a request is a notification.

## Message and exchange APIs

PreparedService snapshots wire method names to operation IDs, input validators, result selections
and the chosen version/profile, together with result validators and per-operation application error
mappings including service errors. It returns findings; it does not invoke handlers or transmit
protocol errors. Parameters, results and error data delegate to the generic value engine.

RequestId distinguishes Absent from Present(NodeValue). Numbers remain exact; legacy structured IDs
retain structural identity. A 1.0 present-null ID is a notification. A 2.0 absent ID is a notification;
a 2.0 present-null ID remains a call, with a recommendation advisory. Fractional 2.0 IDs are also
permitted with an advisory. Advisories do not invalidate an otherwise valid message.

ResponseContext explicitly provides an operation or original request. Operation-only context can
validate payload shapes but cannot prove ID correlation. A bare response identifies no method;
envelope-only checks must state that limited scope. Original-request context permits exact ID checks.
ExchangeContext holds explicit direction, calls, notifications and supplied associations. Transcript
completeness must be declared before reporting missing responses. Duplicate IDs may leave otherwise
well-formed calls ambiguous for correlation; distinguish that finding from an invented envelope MUST.

Unknown envelope extension fields are ignored by the base profile unless an explicit extension
policy checks them. The payload's unknown-member policy is separate. Duplicate JSON keys are
rejected as an explicit deterministic-input compatibility policy.

The request/notification milestone also fixes the shared JSON parser's error offsets, as reported
in [PR #38](https://github.com/moonrockz/smithy/pull/38#discussion_r4337569571).
Balanced malformed input such as `{"a":truX}` must report the parser's failure location instead of
the completed preflight scan's EOF position. Regression coverage must verify the library offset
and its propagation through structured CLI diagnostics for value and RPC validation.

The request validator is an `rpc` subcommand of `smithy validate`.
The CLI is `smithy validate rpc --version 2.0 --service example#Calculator --message call.json
model.smithy`. Responses use `--response reply.json` with one of `--method subtract`,
`--operation example#Subtract`, `--request call.json` or `--envelope-only`. Missing response
context fails. JSON diagnostics are one complete stdout report. The scope is explicit; method-only
checks cannot prove correlation. Legacy opaque errors remain distinct from the opt-in
`--legacy-errors code-message-data` mapping. Transcript mode with explicit directions remains planned.

## Rule and original-example coverage

The table separates request and single-response coverage from follow-on batch/exchange work. R = requests/notifications,
S = responses/errors, B = batches, E = exchanges, T = transport-only, C = explicit compatibility policy.

| Source | Class | Required check or classified boundary |
|---|---|---|
| 2.0 §§1–3 | R/S/C | Explicit version; JSON types and case-sensitive matching; 1.0 objects do not silently become 2.0. |
| 2.0 §4 version/method | R | Literal 2.0, string method, reserved rpc. prefix and modeled method lookup. |
| 2.0 §§4/4.2 params | R | Omitted/object/array only; named case, explicit positional order, parameter mode and value constraints. |
| 2.0 §4 IDs | R/S/C | String/number/null only when present; exact identity; null/fractional recommendations stay advisories. |
| 2.0 §4.1 notifications | R/E | Absent ID; no supplied response even within batches. Single messages cannot prove silence. |
| 2.0 §5 responses | S/E | Version and ID required; exactly one result/error; contextual payload shape and ID correlation; null unknown ID for parse/invalid-request errors. |
| 2.0 §5.1 errors | S/C | Integer code, string message, optional data; protocol/application separation. Reserve -32768 through -32000, including -32099..-32000 implementation server errors. No invented hard message-length limit. |
| 2.0 §6 batches | B/E | Nonempty request array, element checks, unordered exact-ID association and no scheduling claims. Invalid batch yields a single error object. |
| 2.0 §6 notification handling | B/E | Invalid elements and mixed batches; all-notification batches have no response; empty response arrays are forbidden. |
| 2.0 §7 subtract positional examples | R/S/E | Both argument orders, numeric results and original IDs. |
| 2.0 §7 subtract named examples | R/S | Both object orders; names determine arguments. |
| 2.0 §7 update/foobar notifications | R/E | Notification classification independently of modeled method existence. |
| 2.0 §7 nonexistent method | R/S/E | Unknown method and contextual -32601 error. |
| 2.0 §7 invalid JSON | R/S/E | Parse failure and -32700 response with null unknown ID. |
| 2.0 §7 invalid request | R/S | Wrong method/params types and contextual -32600. |
| 2.0 §7 invalid batch JSON/empty batch | B/S | Single protocol error object. |
| 2.0 §7 [1] and [1,2,3] | B/S | Error for each invalid element, with null IDs. |
| 2.0 §7 mixed batch | B/E | Calls, notification omissions, invalid elements, unknown method and unordered responses. |
| 2.0 §7 all-notification batch | B/E | No response. |
| 2.0 §8 extensions | C | Only supported explicit extensions, without inferred negotiation. |
| 1.0 overview/§1.1 | R | Object, method string, required positional params and arbitrary required JSON ID. This profile rejects a jsonrpc marker. |
| 1.0 §1.2 | S/E | result/error/id required; error null on success, result null on error, matching arbitrary ID. Null success allowed. Legacy error mapping is explicit, not a required 2.0 error envelope. |
| 1.0 §1.3 | R/E | Present-null notification; absent ID invalid; no supplied response. |
| 1.0 §2.1 bidirectional calls | E | Explicit peer directions and outstanding calls; unsolicited/duplicate replies fail exchange checks. |
| 1.0 §2.1 stream lifecycle | T | Framing, close behavior and pending-call exceptions need a transport implementation. |
| 1.0 §2.2 HTTP | T/C | POST framing, polling and unspecified sessions remain transport concerns. Multiple serialized objects are not standardized 2.0-style batch arrays. |
| 1.0 §3 class hints | C | __jsonclass__ is ordinary modeled data; never execute constructors. |
| 1.0 §4 echo | R/S/E | String argument/result and matching numeric ID. |
| 1.0 §4 chat transcript | R/S/E | postMessage calls 99/101, reverse handleMessage/userLeft null-ID notifications and matching results. |
| Adversarial fixtures | R/S/B/E | Exact large/fractional IDs, wrong case, absent/null, arbitrary scalar/array/null results, malformed errors, ambiguous IDs, duplicate/unsolicited replies, partial transcripts and limits. |

## OpenRPC mapping

Pin document version 1.3.2 and JSON Schema draft-07 independently of JSON-RPC wire versions. The
official metaschema release 1.14.9 artifact permits 1.3.2; its SHA-256 is
`e5f534fb0dd9dd3598d26414e278a8c96e923ee7b54bef7009c499f4c71d0f82`.
Vendor the released `open-rpc-meta-schema.json`, not the repository's generation template.

The library is `moonrockz/smithy-openrpc`: `Config::new(ServiceId, ...)` selects a typed service,
and `convert_result(model, config)` returns the document and structured conversion warnings.
A build plugin named `openrpc` writes deterministic `openrpc.json`. Settings select the service,
info metadata, naming and extension policy. Use the existing JSON Schema converter/reference index
with `#/components/schemas`, preserving effective member constraints and valid references.
`PreparedService::contracts()` supplies detached, sorted method/error mappings to the exporter.
JSON Schema's opt-in `SchemaIndex::for_values` and `convert_values` APIs preserve runtime member replacement semantics,
intrinsic numeric bounds, closed structures, union cardinality and sparse collections. Recursive
constrained members receive collision-checked shared definitions rather than recursive expansion.

Export service metadata, method names/docs, ordered Content Descriptors and requiredness, results,
application errors, examples and reusable schemas. Map parameter mode to by-name/by-position/either.
Result selection supports scalar, array, object or null schemas. Error data schemas use documented
x-smithy metadata because OpenRPC's error data field is not itself a schema keyword. Notification-only
conventions, batch and exchange rules require documented extensions or explicit loss diagnostics.
Reject conflicting names, invalid selections and unresolved refs instead of silently losing meaning.

OpenRPC standard output covers 2.0 only. Preserve 1.0 validation independently; do not invent standard
1.x OpenRPC. Consumers may serve a generated document via rpc.discover; a discovery server is not
required. Acceptance validates deterministic documents against the pinned official metaschema and
shares representative method/schema fixtures with message validation.
The [exporter guide](../smithy-openrpc/README.mbt.md) documents exact settings, error-data/example
extensions and schema limitations. `mise run test:openrpc` qualifies actual CLI/library artifacts
against the vendored official metaschema and compares representative schemas with runtime results.

## Ion profile and released API audit

The inspected `moonrockz/ion v0.6.0` API exposes immutable Ion, alias IonValue, IonValueKind,
SymbolToken and ordered struct Fields. It exposes exact BigInt, decimal coefficient/exponent/signed
zero, native timestamp precision/offset, annotations, binary data and distinct list/sexp kinds.
Field names may be unresolved symbols. Select and verify a compatible published pin when implementing
the adapter; reuse its codecs rather than writing an Ion parser or generating Ion Schema.

| Native kind | Explicit mapping policy for the later adapter |
|---|---|
| Null/bool/string | Generic presence/type rules; typed null retains its kind and requires nullable/sparse/document support. |
| Int/decimal | Exact comparison; preserve scale and signed zero. Integral decimal-to-integer mapping requires an explicit policy. |
| Float | Preserve binary value, signed zero and nonfinite status. Exact range comparison or an unsupported finding; no lossy decimal conversion. |
| Timestamp | Native Smithy timestamp profile, initially known offset and second precision. Unsupported precision/ranges report findings. |
| Symbol | Explicit text-symbol mapping only; unresolved symbol names fail. |
| Blob/clob | Blob uses bytes and byte lengths. Clob is unsupported without a separately named policy. |
| Struct | Structure/map with occurrence-aware fields; duplicate keys fail by default. |
| List/sexp | List maps to list; sexp remains distinct unless explicitly enabled. |
| Annotations | Reject by default; explicit ignore policy retains source annotations. Never infer a union from annotations. |
| Document | JSON-shaped by default; native open-content support requires an explicit profile. |

Take one in-memory Ion value first. A later CLI selects text/binary plus explicit single-value or
datagram behavior. Equivalent decoded text/binary inputs must yield equivalent findings, while
retaining native types and source values. This does not define an Ion-encoded JSON-RPC protocol.

## Sources

- [JSON-RPC 1.0](https://www.jsonrpc.org/specification_v1)
- [JSON-RPC 2.0](https://www.jsonrpc.org/specification)
- [OpenRPC specification](https://spec.open-rpc.org/)
- [Released metaschema](https://github.com/open-rpc/meta-schema/releases/download/1.14.9/open-rpc-meta-schema.json)
- [Ion v0.6.0 public API](https://github.com/moonrockz/ion/blob/v0.6.0/pkgs/ion/pkg.generated.mbti)
