# Direct instance validation

Model assembly checks a Smithy definition. Instance validation checks an application value directly
against a selected assembled data shape. It requires neither JSON Schema conversion nor a service.

Preparation walks only the reachable data graph with an explicit stack. It resolves member target
kinds, applies explicit member trait overrides once, and snapshots scalar constraints, copied
member arrays and private name indexes. It retains no caller model maps or mutable trait payloads.

Validation consumes a read-only ValueView. JSON and NodeValue adapters inspect one value at a time
without converting descendants and retain exact numeric values. JSON map keys are sorted for
deterministic findings. Native adapters can retain repeated fields and richer scalar payloads. Config selects an explicit
ValueProfile, defaulting to JsonProfile. Optional adapters use NativeProfile through
Config::with_profile without changing limits or other policies; the engine imports no format package.

Instance paths are domain values with validated indices/occurrences and private storage. Getters
copy the step array. LocatedObject explicitly maps logical members to original source positions;
map-key validation uses a distinct step. NativeObject retains optional resolved field names. Known
names use Field(name, occurrence); unresolved names produce UnsupportedValue at
FieldNamePosition(physical_index). Their values use FieldPosition(physical_index) and still consume
validation budgets. These distinct steps identify field-name tokens and field values without
relying on finding order or message text. Both project to a numeric JSON Pointer segment, while
structured paths retain their distinct kind.
Rendering is a diagnostic/serialization boundary operation.

Validation and uniqueness comparison each maintain their own explicit stack and share one call-local
budget. Queued frames count against available work. Instance walking never globally deduplicates
shape IDs: recursive shapes must validate each occurrence. Every call owns its findings and counters.
Unsupported values and incomplete checks cannot produce a valid result. ValueView::expansion_size
is a non-allocating immediate expansion hint, defaulting to zero for existing adapters. Views that
allocate wrappers or annotations override it with the immediate width. Validation and both
uniqueness operands preflight that width against remaining work and queued frames before calling
inspect, so wide values cannot allocate beyond the budget before rejection. Annotation tag counts
also consume aggregate work after inspection in both validation and uniqueness comparisons, so
repeated annotated values cannot expand tags without reducing the shared budget.

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

NativeProfile accepts exact Number values for numeric Smithy targets, native Decimal only for
BigDecimal/Float/Double and native Float only for Float/Double. Document accepts all three finite
numeric kinds. Float magnitude, range and uniqueness use an exact coefficient derived from IEEE
754 bits, with at most 1074 fractional decimal places. Display rounding never enters a comparison.
TypedNull follows the same placement rules as Null and never satisfies an absent required member.
Native blobs use byte length and only match Blob. Native timestamps only match Timestamp and must
retain valid full seconds precision with a known offset. InvalidTimestamp lets an adapter report
an invalid programmatic timestamp without inventing another scalar kind. JSON base64, epoch/date-time
and nonnumeric float string representations remain exclusive to JsonProfile. Native timestamps
ignore legal timestampFormat serialization directives, including http-date.

Document and ignored fields still reject blob, timestamp, symbol, clob and s-expression values.
Nonfinite floats require explicit nonnumeric_floats, match only Float/Double and obey modeled range
bounds; NaN never satisfies a range. Every annotation produces UnsupportedValue. An explicit frame
then inspects its underlying value at the same path, sharing work/finding budgets, and s-expression
children also remain subject to depth/work limits. All graph walking remains iterative.

Native uniqueness compares numbers mathematically across their native numeric kinds, typed nulls
as Null, enabled NaNs as equal, bytes by content and full timestamps by retained components and
offset. Timestamp fractions compare their retained exact tokens, including fractional precision;
`.0` and `.00` therefore remain distinct. Unresolved fields, annotations and unsupported scalar kinds never acquire guessed equality.
Inputs and native scalar payloads are never rewritten or mutated.

Optional format modules depend inward on model/validation contracts and use the exposed native
payloads without a whole-tree conversion. WIT conversion remains independent.
This module implements no RPC envelopes, handlers or transports. The finalized
[shared design](JSON_RPC_DESIGN.md) records those later contracts.
