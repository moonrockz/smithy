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
to. Any other class counts its source length. The charge is a heuristic bound on the engine's
work, not an exact count. Matching charges eight times
the expanded estimate times the input UTF-16 length plus one against the call's work budget.
Patterns exceeding the preparation caps raise `UnsupportedConstraint`; exhausted matching work
returns `LimitExceeded` before executing the pattern.

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
