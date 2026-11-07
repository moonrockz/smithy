# Direct value validation

For JSON-RPC requests, notifications and contextual responses against a modeled service, see the
[RPC package](rpc/README.mbt.md) and `smithy validate rpc`.

Validate application values against assembled Smithy data shapes through a reusable library and the `smithy validate value` command. This module depends on the Smithy model and core libraries; optional format integrations belong in separate modules.

## Library

```mbt check
///|
test {
  let loaded = @smithy.Loader::new()
    .add_idl(
      "model.smithy", "$version: \"2\"\nnamespace example\n@range(min: 1, max: 100)\ninteger Count\nstructure Input { @required count: Count }",
    )
    .assemble()
  let prepared = @validation.PreparedValidator::prepare(
    loaded.model.unwrap(),
    @smithy.ShapeId::parse("example#Input").unwrap(),
  )
  assert_true(
    prepared
    .validate_json(@validation.parse_json_value("{\"count\":2}"))
    .is_valid(),
  )
  let result = prepared.validate_json(
    @validation.parse_json_value("{\"count\":0}"),
  )
  assert_false(result.is_valid())
  assert_eq(result.findings[0].code, @validation.Range)
  assert_eq(result.findings[0].path.pointer(), "/count")
  assert_eq(result.findings[0].shape.to_string(), "example#Input$count")
}
```

Prepare once and validate repeatedly. Preparation snapshots the selected shape's reachable contract,
including member trait overrides. Later edits to the source model do not change it. Targets may be
data shapes or members. Services, operations, resources, mixins and missing targets fail preparation.
NodeValue inputs use `prepared.validate(value)` directly. Other types implement `ValueView`.

Use `parse_json_value` for text input. It rejects duplicate decoded keys, limits nesting to 128
containers and input to 16 MiB of UTF-8, and preserves every numeric token. A caller-supplied `Json`
can preserve only numbers the caller retained: ordinary core JSON parsing may already have rounded
decimals. A valid numeric `repr` is authoritative; without one, only the supplied finite Double
value is available.

This test checks two orders. The first order is valid, and the second order has a quantity out of range.

<!-- tour:start value-api -->
```mbt check
///|
test "validate an order" {
  let model = @smithy.Loader::new()
  .add_idl(
    "order.smithy",
    (
      #|$version: "2"
      #|
      #|namespace example.orders
      #|
      #|/// An order in a shop.
      #|structure Order {
      #|    @required
      #|    id: String
      #|
      #|    @range(min: 1, max: 10)
      #|    quantity: Integer
      #|
      #|    @length(max: 20)
      #|    note: String
      #|}
    ),
  )
  .assemble().model.unwrap()
  let prepared = @validation.PreparedValidator::prepare(
    model,
    @smithy.ShapeId::parse("example.orders#Order").unwrap(),
  )
  let order =
    #|{
    #|    "id": "A-1001",
    #|    "quantity": 2,
    #|    "note": "Leave at the door"
    #|}
  assert_true(
    prepared.validate_json(@validation.parse_json_value(order)).is_valid(),
  )
  let too_many =
    #|{
    #|    "id": "A-1001",
    #|    "quantity": 11,
    #|    "note": "Leave at the door"
    #|}
  let result = prepared.validate_json(@validation.parse_json_value(too_many))
  assert_false(result.is_valid())
  assert_eq(result.findings.length(), 1)
  assert_eq(result.findings[0].code, @validation.Range)
  assert_eq(result.findings[0].path.pointer(), "/quantity")
  assert_eq(
    result.findings[0].shape.to_string(),
    "example.orders#Order$quantity",
  )
}
```
<!-- tour:end value-api -->

## CLI

```sh
smithy validate value --shape example#Input --value request.json model.smithy
smithy validate value --shape example#Input --value - --diagnostics json model.smithy
```

Text success is quiet; text findings go to stderr. JSON diagnostics go to stdout with `valid`,
`complete` and `findings`. Invalid models/values, malformed input, I/O errors and incomplete checks
exit 1. Invalid usage, targets and unsupported configurations exit 2. Existing `smithy validate`
continues to check model definitions. Stdin may appear once across model and value inputs.

## Policies

| Concern | Default and explicit choices |
|---|---|
| Unknown structure fields | Reject by default. `@smithy.rpc#unknownMembers("ignore")` on a structure overrides the config or CLI policy. Unknown union alternatives always fail. |
| Member names | Smithy names; `member_names=JsonName` or CLI `--member-names json` uses `jsonName`. Preparation rejects collisions. |
| Null | Distinct from absence. Optional members may be absent but must match their target when present. Document and sparse list/map values permit null. |
| Defaults/coercion | No mutation, default insertion or string-to-number coercion. Defaults do not excuse an absent required member. |
| Constraints | Exact range, Unicode scalar string length, decoded blob byte length, collection length, pattern, uniqueness and enum checks. Each explicit member trait replaces that same target trait as a whole. |
| Numbers | Exact mathematical integers and byte/short/integer/long bounds. BigInteger/BigDecimal remain exact. Float/double magnitude is checked without rounding input. |
| Nonnumeric floats | Opt-in `nonnumeric_floats=true` permits exactly `NaN`, `Infinity`, `-Infinity` strings, subject to range rules. |
| Blob | Canonical padded RFC 4648 base64, including zero padding bits. |
| Timestamp | Exact epoch-seconds number; `timestamp_format=DateTime` or effective `timestampFormat("date-time")` selects a calendar-checked string with an offset, including recorded positive leap seconds. HTTP-date is unsupported. |
| Runtime contracts | Reachable `smithy.contracts#conditions` raises `UnsupportedConstraint`. Assembly still validates the expression definition. |

Date-time strings accept `:60` only when their calendar date and offset identify a recorded UTC
insertion minute. For example, `2016-12-31T23:59:60Z` and
`2017-01-01T05:29:60.5+05:30` are valid. Fractional seconds and lowercase `t`/`z` are accepted.
`-00:00` retains RFC 3339's unknown-local-offset convention with a known UTC time.
The offline table contains all 27 positive insertions through 2016-12-31, checked against
[IERS Bulletin 72's table](https://hpiers.obspm.fr/iers/bul/bulc/Leap_Second.dat), July 2026.
Unlisted `:60` dates, including future insertions, fail with `InvalidTimestamp` until the table
is updated. Ordinary future timestamps remain valid. No negative leap seconds are recorded;
a future deletion would require updating the validation rules as well.
`NativeTimestamp::new` separately restricts seconds to `0..59`, including with unknown offsets.
See [RFC 3339 sections 4.3 and 5.7](https://www.rfc-editor.org/rfc/rfc3339).

The portable pattern profile supports literals, classes/ranges, groups, alternation, repetitions,
whole-input anchors and common digit/word/whitespace escapes. Dot excludes line terminators.
A '-' at the start or end of a class, or after a range, is a literal, as in ECMA-262. A '-' after a class escape is a literal, so `[\d-a]` matches a digit, '-' or 'a'. A '-' before a class escape, as in `[a-\d]`, fails preparation.
A class range cannot end in `\d`, `\w` or `\s`. A `\u{...}` escape fails preparation; write `\uXXXX`.
An astral character or a surrogate UTF-16 unit inside a class, including a `\uXXXX` spelling,
fails preparation with `UnsupportedConstraint`. Java reads class members as code points, while
ECMA-262 without the `u` flag reads UTF-16 units. `\B` inside a class also fails preparation:
Java rejects it, while ECMA-262 without `u` reads it as the letter 'B'.
Lookaround, backreferences, flags, Unicode properties, complement escapes inside classes and
unsupported core regex constructs fail preparation. Matching searches unless anchored. This is
not the full ECMA-262 language.

Preparation limits patterns to 4,096 source UTF-16 units, 32 nested groups and
1,024 portable expanded expression units. The estimate retains its definition
across engine upgrades: `*` counts once, `?` and `+` twice, `{n}` n times, `{n,}`
n+1 times and `{n,m}` m times. A positive BMP-only class counts each member or
range once and each class escape as its expanded intervals. Other classes count
source length. Exceeding these caps raises `UnsupportedConstraint`. These bounds
limit preparation, not the work of a match.

The matcher is [`moonrockz/regex`](../regex/README.mbt.md), a reusable core-only
module based on MoonBit core `417988f6e19738a7f683ce19a6cf5aaf52c96965`, bundled
with 0.10.18. Smithy's ECMA translation and diagnostics stay here. Translated text
can exceed 4,096 units, so the adapter uses the library's larger finite compiler
caps after the existing portable guards. Every source unit writes fewer than
128 translated units; the generic expansion estimate is bounded by 16 times the
portable estimate. The secondary caps of 1,048,576 source units and 65,536
expanded units cover those translations without loosening the portable profile.

Each search receives only the validation call's remaining work allowance. Input
UTF-16 length plus one end marker is charged first. The Boolean lazy DFA also
charges NFA closure visits, class lookups, deterministic state-index probes and
key comparisons, buffer growth and logical storage allocation/copying before
performing the work. It can stop inside a transition. Exhaustion produces
`LimitExceeded` and incomplete validation, never a completed pattern mismatch.

Compiled programs are immutable and each call owns fresh execution state.
Identical patterns and values have identical logical costs on fresh and reused
validators, including after exhaustion. Every matching allocation is charged,
so matcher storage is O(remaining work) in addition to the compiled program.
The units bound logical work and storage, not a deadline or whole-process RSS.
The exact charge table, storage bound, source inventory, target laws and native/JS
measurements are in the regex module README.

On an Apple M5 Max, the Morphir FQName cases cost 801 units for
`morphir/SDK:basics#int` and 2,012 for the 97-unit name. A record of 16 references
passes at the unchanged 100,000-unit default. The optional-chain pattern
`^(a?){150}a{150}$` on ten `a` characters now completes as a non-match in 28,229
units; on 150 characters it exhausts the default allowance during transition
work. Numeric units differ from the old engine's model. Backtracking-style
pathologies, DFA state explosion and long inputs remain bounded by the call's
allowance. A later call starts with fresh execution state.

## Findings, adapters and limits

Findings carry a stable code, Error/Advisory severity, typed instance path, semantic shape/member ID
and message. `pointer()` renders JSON Pointer; retain `steps()` to distinguish repeated fields and
map keys. LocatedObject adapters preserve original source positions. An optional `base_path` lets
an RPC parameter finding remain `/params/0` instead of becoming `/params/count`.

`Limits::new` defaults to depth 128, 100,000 value/constraint/equality work units and 100 findings.
Positive configurable maxima are depth 1,024, 10,000,000 work units and 10,000 findings. The last
finding slot is reserved for `LimitExceeded`. Exhaustion sets `complete=false`; `is_valid()` requires
completion and no Error findings. Iterative walking/equality also checks document values, ignored
fields and cyclic inputs. Adapters themselves are trusted code. An adapter that allocates child
wrappers in `inspect` overrides `ValueView::expansion_size` with a non-allocating immediate width.
The engine checks that width before inspecting values in validation and uniqueness comparisons;
the default zero preserves existing adapters that already inspect without expansion.

Native scalar, annotation and sexp values are explicitly unsupported by the JSON profile. The
neutral view retains exact decimals, floats, timestamps, symbols and bytes. Select
`Config::new(profile=NativeProfile)` for native adapters, or preserve an existing configuration
with `config.with_profile(NativeProfile)`. Decimal values match BigDecimal/Float/Double, finite
binary floats match Float/Double, blobs match Blob and full native timestamps with known offsets
match Timestamp. NativeProfile does not accept JSON serialization forms for blobs or timestamps.
Document accepts finite numeric kinds, nulls, strings, booleans and list/object descendants.
Symbols, clobs, sexps and annotations remain unsupported, including in ignored content.

Native uniqueness compares numbers mathematically across numeric kinds and bytes by content.
Timestamps compare retained components, offsets and exact fractional tokens, preserving fractional
precision. NativeObject preserves duplicate resolved fields and unresolved names. FieldPosition
identifies an unresolved field's value; FieldNamePosition identifies its field-name token. Both
remain distinct from array indices in structured findings. Annotations are rejected while their
underlying values are inspected at the same path within the shared execution limits.

The optional `moonrockz/smithy-ion-validation` module supplies the direct Ion adapter. Ion and WIT
remain outside this library's dependency graph.

Run `mise run test:validation-consumer` to audit resolved packaged dependencies and run an isolated
example on all four targets. See [design](DESIGN.md) and the
[shared RPC contract](JSON_RPC_DESIGN.md).

## Model member policies

The `smithy.rpc` trait bundle defines `@unknownMembers("reject" | "ignore")`
for services and structures. A structure trait overrides the service policy.
The service policy overrides `Config::new(unknown_members=...)` and the CLI flag.
Value validation uses the structure policy and the config only. The RPC loader
supplies the trait definitions. Other loaders can use `@rpc.trait_definitions()`
as a built-in source. The value validator has no dependency on the RPC package.

`@criticalPaths(separator: ".")` applies to a structure member with a list-of-string
target. Each string must name a declared member path from that structure.
The path uses the selected member name policy. A member can be absent in the
value. Paths can pass through nested structures, including recursive structures.
They cannot pass through lists, maps, unions, or scalar values. An unknown or empty
path gives `UnknownCriticalPath` at the list element. Unknown fields that no
critical path names follow the unknown member policy. The work limit also bounds
critical path checks.

`PreparedValidator::config()` returns the preparation config.
`unknown_members(target)` returns the effective policy for a prepared target.
`critical_paths(target)` returns the critical path separator for a prepared member.
