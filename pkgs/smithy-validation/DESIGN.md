# Direct instance validation

Model assembly checks a Smithy definition. Instance validation checks an application value directly
against a selected assembled data shape. It requires neither JSON Schema conversion nor a service.

Preparation walks only the reachable data graph with an explicit stack. It resolves member target
kinds, applies explicit member trait overrides once, and snapshots scalar constraints, copied
member arrays and private name indexes. It retains no caller model maps or mutable trait payloads.

Validation consumes a read-only ValueView. JSON and NodeValue adapters inspect one value at a time
without converting descendants and retain exact numeric values. JSON map keys are sorted for
deterministic findings. Native adapters can retain repeated fields and richer scalar payloads.

Instance paths are domain values with validated indices/occurrences and private storage. Getters
copy the step array. LocatedObject explicitly maps logical members to original source positions;
map-key validation uses a distinct step. Rendering is a diagnostic/serialization boundary operation.

Validation and uniqueness comparison each maintain their own explicit stack and share one call-local
budget. Queued frames count against available work. Instance walking never globally deduplicates
shape IDs: recursive shapes must validate each occurrence. Every call owns its findings and counters.
Unsupported values and incomplete checks cannot produce a valid result.

Existing assembly value checks are not reused wholesale because their coercion, severity, regex
fallback and UTF-16 length policies differ. Text input first checks UTF-8 size, depth and decoded
duplicate keys, then calls smithy-syntax's existing exact JSON parser. Its iterative token rebuild
retains decimals that ordinary core JSON parsing would round.

The CLI delegates to this same API. Tests cover library policies, generated adapter equivalence,
the actual CLI on all four targets, acceptance scenarios and an isolated packaged consumer with its
own workspace and registry cache. The consumer cannot obtain new APIs from the enclosing workspace.

Date-time validation parses the full RFC 3339 string before checking seconds. A `:60` value must
resolve, after subtracting its numeric offset and adjusting the calendar day, to 23:59 on a
recorded positive UTC insertion date. The offline IERS table contains 27 insertions through
2016-12-31 and must be updated for future announcements. No negative leap seconds are recorded;
future deletions would also require a rule update. Fractional text is never converted to a host
date or floating-point value. Neutral NativeTimestamp values retain their separate `0..59` second
boundary. The same string policy applies to library and CLI validation.

Optional format modules depend inward on model/validation contracts. A future Ion profile can use
the exposed native payloads without an Ion-to-JSON conversion. WIT conversion remains independent.
This module implements no RPC envelopes, handlers or transports. The finalized
[shared design](JSON_RPC_DESIGN.md) records those later contracts.
