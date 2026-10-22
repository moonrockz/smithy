# JSON-RPC message validation

Validate JSON-RPC 1.0 or 2.0 messages and explicit 2.0 batches against a Smithy service.
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
`result_selection`. Result validators snapshot the effective selected member contract.
Every modeled operation error and service error needs `rpcError` with an integer application
code outside -32768 through -32000. Codes must be unique within each operation, including
service errors. `dataMember` selects an effective error member contract, `absentData: true`
requires absent data, and the default selects the whole error structure. Conflicting or
undeclared selectors fail preparation.

## Responses

`validate_response(text, context=Some(...))` and `validate_response_json(json, context=Some(...))`
check one response. Supply a `ResponseContext`:

| Context | Checks |
|---|---|
| `Method(MethodName)` | Envelope and the selected wire method's result/application error data |
| `Operation(ShapeId)` | Envelope and the selected reachable operation's result/application error data |
| `OriginalRequest(String)` | Envelope, available method contracts, exact ID and single-request compatibility |
| `EnvelopeOnly` | Envelope only, with a `LimitedScope` advisory |

Omitting context returns `MissingContext`. A response's extension fields never select a method.
Method/operation context cannot prove ID correlation. `ResponseResult.scope` reports `Envelope`,
`MethodPayload` or `RequestContext`. JSON diagnostics render these as `envelope`, `methodPayload`
and `requestContext`. `complete` describes completion within that declared scope.

```mbt check
///|
test {
  let loaded = @rpc.loader()
    .add_idl(
      "api.smithy", "$version: \"2\"\nnamespace example\nuse smithy.rpc#jsonRpc\nuse smithy.rpc#method\n@jsonRpc(versions: [\"2.0\"])\nservice Api { version: \"1\", operations: [Ping] }\n@method(name: \"ping\", params: \"either\", positional: [], nullResult: true)\noperation Ping {}\n",
    )
    .assemble()
  let service = @rpc.PreparedService::prepare(
    loaded.model.unwrap(),
    @smithy.ShapeId::parse("example#Api").unwrap(),
    @rpc.V2_0,
  )
  let response = service.validate_response(
    "{\"jsonrpc\":\"2.0\",\"result\":null,\"id\":9007199254740993}",
    context=Some(
      @rpc.OriginalRequest(
        "{\"jsonrpc\":\"2.0\",\"method\":\"ping\",\"id\":9007199254740993}",
      ),
    ),
  )
  assert_true(response.is_valid())
  assert_eq(response.scope, @rpc.RequestContext)
}
```

Version 2.0 requires the literal version, an ID of string/number/null, and exactly one of
result or error. An error is an object with an exact integer code, string message and optional
data. Defined protocol codes and -32099 through -32000 server errors bypass application data
contracts. Unassigned reserved codes fail. Other codes must be modeled for the selected
operation. Whole-structure data is required; selected member data may be absent when the member
is optional. Explicit null always undergoes the member's value validation. No message-length
limit is invented beyond the shared resource limits.

Version 1.0 requires result, error and an arbitrary JSON ID. Success has null error, including
when the result itself is null. Failure has nonnull error and null result. Legacy errors are
opaque by default, with a `LimitedScope` advisory. Explicit `legacy_errors=CodeMessageData`
opts into the code/message/data application mapping; 1.0 itself does not require that schema.

Original-request context uses original text. In 2.0, parse failures can match -32700 with null ID.
Invalid envelopes match -32600, unknown methods match -32601, and invalid modeled parameters
match -32602. Detectable valid request IDs are echoed exactly; unknown/invalid IDs become null.
Exact numeric identity compares mathematical values without rounding, including nested legacy
IDs. Valid notifications cannot have a supplied response. Duplicate keys and incomplete
resource checks fail context validation rather than becoming protocol parse errors. Invalid
1.0 original request envelopes have no standardized protocol-error mapping and fail context validation.
Well-formed 1.0 calls with unknown methods or invalid modeled parameters require a nonnull legacy
error, without inventing a required 2.0 error code. Original-request arrays are unsupported batch contexts. This API checks a single supplied association, not transcript completeness.

## Batches

`validate_request_batch(text)` checks a nonempty 2.0 request array. Its in-memory counterpart is
`validate_request_batch_json(json)`. `RequestBatchResult.entries` retains each original `index`
and its `RequestResult`. Findings in both entries and the combined report use original array
paths, such as `/2/params/1`, with the semantic member and operation IDs preserved.

`validate_response_batch(Some(text), context=Some(...))` checks a supplied batch response.
`validate_response_batch_json(Some(json), context=Some(...))` accepts in-memory JSON.
Pass `None` for an absent response. JSON `null`, an empty string and `[]` are supplied values,
and none represents absence. Supply a `BatchResponseContext`:

| Context | Checks |
|---|---|
| `OriginalBatch(String)` | Complete response to the original batch, including unordered exact-ID association, payloads, protocol errors, duplicate/unsolicited/missing replies and notification omissions |
| `BatchMethod(MethodName)` | Every supplied response against the same method; no ID correlation |
| `BatchOperation(ShapeId)` | Every supplied response against the same operation; no ID correlation |
| `BatchEnvelopeOnly` | Envelopes with `LimitedScope` advisories; no modeled payload or correlation checks |

`ResponseBatchResult` reports its `scope`, findings and indexed entries. Each entry has a response
`index` and an associated `request_index` when known. Response findings use response-array indices,
independently of request order. An invalid whole batch requires a single error object; that entry's
`index` is `None`. Malformed original JSON expects -32700, while empty/non-array originals expect
-32600. Nonempty batches containing invalid entries require corresponding -32600 responses within
an array, including when every entry is invalid. Unknown methods and invalid modeled parameters
use the existing contextual -32601 and -32602 rules. A request batch can therefore fail validation
while a supplied response batch correctly reports those protocol errors and passes.

OriginalBatch declares one complete batch response. Every call or invalid request element needs
one response; well-formed notifications need none, including unknown methods and invalid modeled
parameters. All-notification batches accept only absence. Empty response arrays always fail.
Repeated valid call IDs produce an `AmbiguousId` advisory in request validation and an error in
contextual response validation. Repeated null IDs for invalid elements form an unordered multiset
of protocol errors. Explicit-null calls remain distinct from invalid elements. Numeric keys use
normalized exact coefficients/exponents, so `1`, `1.0` and `1e0` correlate without rounding or
expanding large exponents. Numeric IDs remain distinct from strings.

Both batch APIs report `UnsupportedMessage` under 1.0. Multiple 1.0 objects in HTTP/stream framing
are a separate transport concern. The batch APIs check one supplied association. They do not
define scheduling, handler execution, peer direction or outstanding calls across batches;
`TranscriptChecker` links batches between two peers (see Transcripts).

## Two-peer protocols

A `@jsonRpcProtocol` structure names two peers and the service each peer accepts. A peer with no
`accepts` accepts nothing. `ProtocolDescription::from_smithy` selects a version and prepares one
`PreparedService` per receiving peer. See `examples/json-rpc/peers.smithy`.

```mbt check
///|
test "describe a two-peer protocol" {
  let loaded = @rpc.loader()
    .add_idl(
      "peers.smithy",
      (
        #|$version: "2"
        #|namespace demo
        #|use smithy.rpc#jsonRpc
        #|use smithy.rpc#jsonRpcProtocol
        #|use smithy.rpc#method
        #|@jsonRpcProtocol(versions: ["2.0"], peers: [{name: "client"}, {name: "server", accepts: Api}])
        #|structure Link {}
        #|@jsonRpc(versions: ["2.0"])
        #|service Api { version: "1", operations: [Ping] }
        #|@method(name: "ping", params: "named", nullResult: true)
        #|operation Ping {}
      ),
    )
    .assemble()
  guard loaded.model is Some(model) else { fail("model did not load") }
  let link = @rpc.ProtocolDescription::from_smithy(
    model,
    @smithy.ShapeId::parse("demo#Link").unwrap(),
    @rpc.V2_0,
  )
  let server = @rpc.PeerName::parse("server").unwrap()
  assert_true(link.service_for(server) is Some(_))
  assert_eq(link.other(server).map(p => p.to_string()), Some("client"))
}
```

## Transcripts

`TranscriptChecker` checks a conversation between the two peers of a `ProtocolDescription`.
Each `TranscriptEntry` names its sender and holds the original message text. The receiver is
the other peer. `feed` returns the findings for one entry at once, and `feed_all` accepts a
group of any size; both give the same findings in the same order. `finish` returns the
end-of-input findings and a summary. It is idempotent, and a feed after it is ignored. The
checker does no I/O and never raises: problems are `TranscriptFinding` values.

```mbt check
///|
test "check a two-peer transcript" {
  let loaded = @rpc.loader()
    .add_idl(
      "peers.smithy",
      (
        #|$version: "2"
        #|namespace demo
        #|use smithy.rpc#jsonRpc
        #|use smithy.rpc#jsonRpcProtocol
        #|use smithy.rpc#method
        #|@jsonRpcProtocol(versions: ["2.0"], peers: [{name: "client"}, {name: "server", accepts: Api}])
        #|structure Link {}
        #|@jsonRpc(versions: ["2.0"])
        #|service Api { version: "1", operations: [Ping] }
        #|@method(name: "ping", params: "named", nullResult: true)
        #|operation Ping {}
      ),
    )
    .assemble()
  guard loaded.model is Some(model) else { fail("model did not load") }
  let link = @rpc.ProtocolDescription::from_smithy(
    model,
    @smithy.ShapeId::parse("demo#Link").unwrap(),
    @rpc.V2_0,
  )
  let client = @rpc.PeerName::parse("client").unwrap()
  let server = @rpc.PeerName::parse("server").unwrap()
  let checker = @rpc.TranscriptChecker::new(link, completeness=Complete)
  let found = checker.feed_all([
    {
      sender: client,
      message: "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
      location: None,
    },
    {
      sender: server,
      message: "{\"jsonrpc\":\"2.0\",\"id\":1.0,\"result\":null}",
      location: None,
    },
    {
      sender: server,
      message: "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":null}",
      location: None,
    },
  ])
  assert_eq(found.map(f => f.code.to_string()), ["UnsolicitedResponse"])
  assert_eq(found[0].entry, Some(2))
  assert_eq(checker.finish().outstanding, 0)
}
```

Correlation follows these rules:

- Each sender has its own ID space. A reply matches a call by caller, responder and exact ID.
  `1`, `1.0` and `10e-1` are the same ID; the string `"1"` is not. Structured 1.0 IDs compare
  structurally.
- A matched reply is validated with `OriginalRequest` context from its call, and its findings
  name the call in `related`. The call is then answered.
- A null-ID reply answers the earliest unreadable entry (invalid JSON, or an invalid envelope with
  no usable ID) of the other peer, else an active explicit-null 2.0 call. When both exist, it
  answers the earlier one and adds an `AmbiguousReplyId` advisory (code `AmbiguousId`).
- Otherwise a reply is a `DuplicateReply` (code `DuplicateResponse`, with the first reply in `related`), a
  `WrongResponder` (the ID is active for the sender itself), a `ResponseToNotification` (a 1.0
  null-ID reply after a 1.0 notification), or an `UnsolicitedResponse`. These replies are still
  checked as envelopes, and only their error findings are kept.
- A call that reuses an ID still active for its sender is `ActiveIdReused`.
- `finish` reports each active call and each 2.0 unreadable entry as `MissingReply` (code `MissingResponse`, error)
  when the transcript is `Complete`, and as `OutstandingCall` (advisory) when it is `Partial`, the
  default. Notifications never need a reply.
- A peer that accepts nothing receives no methods: a request to it is `UnknownMethod` on the
  protocol shape.
- With `correlation=false` the checker validates each message only; replies keep the
  `LimitedScope` advisory and no call is tracked.
- A 2.0 array entry is a batch. It is a reply batch when an element is an object with `result`
  or `error` and no element has `method`. Any other array, `[]` too, is a request batch.
- A request batch is one unit. It is checked with `validate_request_batch` and waits for one
  reply batch. An all-notification batch needs no reply. An empty batch waits for one null-ID
  `-32600` error object, as an unreadable entry does.
- A reply batch answers the earliest pending batch of the other peer whose IDs include every reply
  ID. It is checked with `OriginalBatch` context, so missing replies inside the batch are reported
  at once, and its findings name the batch in `related`. A reply batch that fits no batch is an
  `UnsolicitedResponse`. A single reply to a call inside a pending batch is `WrongReplyForm`.
- At `finish`, each pending batch is one `MissingReply` or `OutstandingCall`, with the batch in
  `related`. A 1.0 array entry is `UnsupportedMessage`, because 1.0 has no batches.

`TranscriptLimits::new` bounds memory and output: `active_calls` (1024, per sender, also for
unreadable entries and pending batches), `answered_ids` (4096, per sender, also for remembered 1.0 notifications),
`entry_bytes` (1 MiB) and `findings` (10,000). An unknown sender gives `UnknownPeer` and an
oversized entry gives `EntryLimit`; both entries are skipped. A call beyond `active_calls` gives
`ActiveCallLimit` and is not tracked. When the answered memory forgets an ID, a late duplicate is
reported as unsolicited and the message says so. The last finding within the budget is
`FindingLimit`. The two limit findings set `complete` to false in the summary.

## JSON transcript documents

`read_json_transcript` reads a JSON document into a `TranscriptDocument`: an object with `entries`
(each `{"from": peer, "message": value}`) and optional `version` (`"1.0"` or `"2.0"`), `complete`
(boolean) and `expect`, or a bare array of entries. Each `message` is the exact source text of its
value, so numbers and IDs stay as written, and each entry's location is the line and column of that
value. The reader never raises: a problem is an `InvalidTranscript` finding with a location, and an
entry with a problem is dropped. It does not know the protocol, so a peer name that the protocol
lacks is reported by the checker as `UnknownPeer`.

`expect` lists `{code, entry?, related?}` items. `match_expected` pairs each item with one distinct
finding of the same code name (`to_string`), entry and related entry. `ExpectationResult::is_match`
holds when no item is missing and every unlisted finding is an advisory.

## CLI

From the repository root:

```sh
smithy validate rpc --version 2.0 --service example#Calculator \
  --message examples/json-rpc/call.json examples/json-rpc/calculator.smithy
smithy validate rpc --version 2.0 --service example#Calculator \
  --message examples/json-rpc/invalid.json --diagnostics json examples/json-rpc/calculator.smithy
smithy validate rpc --version 2.0 --service example#Replies \
  --response examples/json-rpc/reply.json --method subtract examples/json-rpc/responses.smithy
smithy validate rpc --version 2.0 --service example#Replies \
  --response examples/json-rpc/error.json --request examples/json-rpc/call.json \
  --diagnostics json examples/json-rpc/responses.smithy
smithy validate rpc --version 2.0 --service batch#Api --batch \
  --response examples/json-rpc/batch-replies.json --request examples/json-rpc/batch-mixed.json \
  --diagnostics json examples/json-rpc/batches.smithy
smithy validate rpc --version 2.0 --service batch#Api --batch \
  --no-response --request examples/json-rpc/batch-notifications.json examples/json-rpc/batches.smithy
```

The first succeeds quietly. The second exits 1 with `TypeMismatch` at `/params/1`, associated
with `example#SubtractInput$subtrahend` and operation `example#Subtract`. A message or model may
use stdin `-` once; stdin models require `--from idl` or `--from json`. Model arguments and
options follow `validate rpc`. Use `smithy validate rpc --help` for nested command help.
`smithy validate model.smithy` continues to validate model definitions.

JSON diagnostics emit one complete report to stdout, never JSONL.
Use exactly one of `--message`, `--response` and `--no-response`. Response context options are mutually exclusive.
`--batch --message` checks request arrays. `--batch --response --request` supplies the full original
batch for correlation; method/operation/envelope flags select their stated limited scopes instead.
`--no-response` requires `--batch --request` and checks absence without opening a response file.
`--operation` accepts a Smithy operation ID; `--envelope-only` reports its limited scope.
`--legacy-errors code-message-data` explicitly selects that 1.0 error mapping.
Message, response, original request and model inputs may use stdin `-` only once in total.
 Text findings go to stderr, including advisory severity.
Invalid messages, malformed JSON, I/O errors, invalid models and incomplete checks exit 1.
Invalid usage, service contracts and unsupported constraint configurations exit 2.

`smithy validate rpc transcript` checks a JSON transcript document with `read_json_transcript`,
`TranscriptChecker` and, when the document has `expect`, `match_expected`:

```sh
smithy validate rpc transcript --protocol example.peers#EchoChat \
  examples/json-rpc/peers.smithy examples/json-rpc/transcripts/chat.json
smithy validate rpc transcript --protocol example.peers#Editor --diagnostics json \
  examples/json-rpc/peers.smithy examples/json-rpc/transcripts/editor-negative.json
```

The positionals are the model files, then the transcript file or `-`. `--protocol` is required.
`--version` is required when the document gives no version, and must agree with it otherwise.
`--complete` or `--partial` overrides `complete` in the document; partial is the default.
`--input-format json|markdown|jsonl` defaults from the extension, and to `jsonl` for stdin; only
`json` is supported now. Text findings go to stderr as
`<file>:<line>:<column>: entry <n> <sender>: <severity> <code>: <message>`. JSON diagnostics are one
report with `valid`, `complete`, `entries`, `outstanding`, `correlation`, `findings` and, for an
`expect` list, `expectations` (`matched`, `missing`, `unexpected`). The command exits 0 when no
finding is an error, or when the findings match the `expect` list, and 1 otherwise. A malformed
transcript is an `InvalidTranscript` finding (exit 1). Invalid usage, a missing or conflicting version
and an invalid protocol exit 2.

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

The shared text parser caps input at 16 MiB UTF-8 and depth 128. Each message first runs a
bounded document check over the entire envelope, including IDs and ignored extensions, then
bounded payload checks over mapped parameters, result or error data. The supplied original request
runs its own bounded checks. Each pass uses the configured generic limits.
The combined report is capped by the configured finding limit and reports incomplete checks.
Batch validation first bounds the entire array, including ignored fields and every element,
then checks individual envelopes and payloads. Its combined finding budget retains all findings
up to capacity. A further attempted finding replaces the final summary slot with `LimitExceeded`
and stops validation, so entries can be a prefix of the original array. Original batch context must be
completely checked before association; duplicate-key and resource failures cannot masquerade as
protocol parse errors. Association uses indexed groups rather than scanning every call per reply.
See the [value profile](../README.mbt.md) for default limits and unsupported constraints,
including runtime contract conditions and regex features.

`validate_request` rejects response objects. Both entry points reject top-level arrays with
`UnsupportedMessage`. Explicit batch entry points handle arrays, and `TranscriptChecker` links
them in transcripts; transport behavior belongs to later slices.
The package introduces no Ion, WIT, WAC, wasm-devkit or JSON Schema conversion dependencies.
`mise run test:validation-consumer` builds separate packaged JSON and RPC consumers, audits
their resolved dependency manifests and runs both examples on all four targets.

The [shared design](../JSON_RPC_DESIGN.md) records the remaining integration contracts.
