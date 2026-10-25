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
| Unknown structure fields | Reject; `unknown_members=Ignore` or CLI `--unknown-members ignore` permits them. Unknown union alternatives always fail. |
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
Lookaround, backreferences, flags, Unicode properties, complement escapes inside classes and
unsupported core regex constructs fail preparation. Matching searches unless anchored. This is
not the full ECMA-262 language.

Preparation limits patterns to 4,096 source UTF-16 units, 32 nested groups and 1,024 expanded
expression units. Each repetition counts the copies the automaton builds (`*` once, `?` and `+`
twice, `{n}` n times, `{n,}` n+1 times, `{n,m}` m times). A positive BMP-only class counts its
members, each single character or range as one and each class escape as the intervals it expands
to. Any other class counts its source length. Patterns exceeding the preparation caps raise
`UnsupportedConstraint`. The caps bound the size of the automaton, not the work of a match.

The matcher is a copy of the lazy DFA of `@string.Regex` from moonbitlang/core, in
`internal/regex` (see its README and NOTICE), and it matches as `@string.Regex` does. Budget hooks
in the copy count its work while it runs and charge the count to the call's work budget:

- Each input UTF-16 unit costs one unit, and the end of the input costs one, charged before the
  search starts.
- Building a transition computes a derivative. It costs one unit for each expression node and each
  thread that the derivative visits, and five units for each thread that duplicate removal visits:
  the visit, the slot scan, the slot assignment, the hash and the state-table comparison. It also
  costs a share of table growth: 6 * (4 * symbols + 2) table cells, at 8 cells to the unit. Table
  doubling allocates and copies at most that many cells for each state that it adds.
- The automaton remembers each transition with what it cost to build. A search pays that cost the
  first time it takes the transition, also when the automaton built it for an earlier value. Later
  steps on the same transition in the same search cost only the step.

So the units of a search depend only on the pattern and the value, never on the values that the
prepared validator saw before, and a value gives the same result on a new and on a used validator.
The count is a bound on the work: each search pays at least what a search on a new automaton does.
A visit does constant work: the translated pattern captures only group 0, so a mark map holds at
most two marks. The scratch set and the slot book of a derivative are reset in time proportional to
what they hold. When a search needs more units than the call has left, it stops at once, also in
the middle of a derivative, keeps no partial state, and the call returns `LimitExceeded`.

The automaton keeps at most 4,096 states between searches, a power of two with at most about 2^17
table cells. Before a search, a full automaton forgets all its states. Over the life of the
automaton, the growth shares pay for all table growth. The first table doubling in a search
allocates and copies at most 3 * states * (4 * symbols + 2) <= 3 * 2^17 cells, about 393,000 cells:
about 0.03 ms native and 1 ms on js. The growth shares of earlier searches pay for that doubling,
and the states that the search adds pay for its later doublings.

A search can add more states than the cap, and each one is charged to it, so the work limit, not
the cap, bounds the memory of one search. The tables hold about 4 bytes per cell and at most about
5 cells per work unit: about 2 MB at the default limit of 100,000 units, and about 200 MB at the
largest configurable limit of 10,000,000 units. The next search starts from empty tables again.

Measured on an Apple M5 Max, one unit takes 12 to 20 ns; allocating or copying a table cell takes
0.07 ns native, 0.4 ns wasm-gc and 2.4 ns js. The Morphir FQName pattern costs 2,295 units for a
97-unit name, and 920 for `morphir/SDK:basics#int`. The pattern `^(a?){150}a{150}$` needs 899,611
units for ten `a` characters, because each derivative visits the chain of optional items again. The
default limit stops it after 100,000 units, in about 2 ms native and 1 ms wasm-gc and js.

The copy adds a second regex engine to the builds, because `moonrockz/smithy` still uses
`@string.Regex` for its model checks. Release builds, before and after the copy:

| Build | Before | After | Change | Gzip change |
|---|---|---|---|---|
| CLI `smithy.wasm` (wasm) | 2,503,178 B | 2,586,211 B | +83,033 B (+3.3%) | +26,038 B (+2.9%) |
| CLI `smithy-gc.wasm` (wasm-gc) | 2,082,278 B | 2,123,222 B | +40,944 B (+2.0%) | +18,720 B (+2.7%) |
| Playground worker, `moon build` js | 5,337,424 B | 5,647,105 B | +309,681 B (+5.8%) | +30,483 B (+5.1%) |
| Playground `worker.js`, bundled | 1,310,959 B | 1,386,063 B | +75,104 B (+5.7%) | +14,330 B (+4.3%) |

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
