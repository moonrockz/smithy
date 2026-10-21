# Smithy Ion validation

Validate an immutable `moonrockz/ion@0.6.0/ion.Ion` directly against an assembled Smithy shape. This optional module adds Ion to applications that need it. `smithy`, `smithy-validation`, JSON validation and RPC validation do not depend on Ion.

```mbt check
///|
test {
  let loaded = @smithy.Loader::new()
    .add_idl(
      "model.smithy", "$version: \"2\"\nnamespace example\nstructure Input { @required name: String }",
    )
    .assemble()
  let prepared = @adapter.PreparedValidator::prepare(
    loaded.model.unwrap(),
    @smithy.ShapeId::parse("example#Input").unwrap(),
  )
  let value = @ion.Ion::from_fields([
    @ion.Field("name", @ion.Ion::string("Ada")),
  ])
  assert_true(prepared.validate(value).is_valid())
}
```

`PreparedValidator::prepare(model, shape, config~)` raises the shared validator's `PreparationError`. It preserves the supplied configuration's policies and limits, and selects `NativeProfile`. `validate(value)` returns `ValidationResult` with `complete`, `findings` and `is_valid()`. Reuse a prepared validator for multiple values. The executable [consumer example](../../examples/ion-validation-consumer/main.mbtx) pins every published import.

Each finding exposes `code`, `severity`, `path`, `shape`, `message` and `native_kind : @ion.IonType?`. Missing required members have no native kind. Duplicate fields retain zero-based occurrences in structured paths. Map-key findings identify the field-name symbol. Unresolved names use `FieldNamePosition(index)`; their values use `FieldPosition(index)`. Both project to `/index` in the convenience pointer, so retain the structured path when distinguishing them matters. JSON diagnostics include `nativeKind` and the complete structured path.

| Ion value | Smithy mapping |
| --- | --- |
| `bool`, `string` | Boolean, String and matching string enums; normal constraints apply |
| `int` | Exact numeric token; numeric targets apply their bounds and range |
| `decimal` | BigDecimal, Float or Double; coefficient, exponent and signed zero stay exact |
| `float` | Float or Double; exact binary numeric magnitude and range checks |
| `timestamp` | Timestamp with valid calendar, seconds precision and known offset |
| `blob` | Blob with byte length constraints |
| `list`, `struct` | List, structure, map, union or Document as appropriate |
| null and typed null | Document or sparse collection positions; never an absent member |
| `symbol`, `clob`, `sexp` | UnsupportedValue |
| annotated value | UnsupportedValue, with descendants still inspected at their original paths |

Native values do not use JSON serialization coercions. A string cannot stand in for a blob or timestamp, an integral decimal cannot stand in for an integer, and a symbol cannot stand in for a string. Native floats require `nonnumeric_floats=true` for NaN and infinities, and modeled range restrictions still apply. Document and ignored unknown content accept finite numeric values, nulls, booleans, strings, lists and structs; unsupported native kinds still produce findings. Unknown field, duplicate, union, enum, member and execution-limit policies come from the shared engine.

The adapter reads one node at a time through `ValueView`. It does not serialize Ion to JSON, convert through Ion Schema, recursively project an entire input tree, or mutate annotations and values. See [DESIGN.md](DESIGN.md) for the dependency boundary and diagnostic indexing.
