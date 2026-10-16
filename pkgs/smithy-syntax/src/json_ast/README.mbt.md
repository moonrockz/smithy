# Smithy JSON AST

Typed records and a JSON codec for the [Smithy JSON AST](https://smithy.io/2.0/spec/json-ast.html).
The package covers every shape kind, legacy `set`, member traits, mixins,
service renames, resource properties and separate `apply` entries.

Import `moonrockz/smithy-syntax/json_ast`, or use the root facade's
`JsonAst`, `parse_json_ast`, `decode_json_ast` and `encode_json_ast`.

## Read and write a document

```mbt check
///|
test {
  let document = @json_ast.parse(
    (
      #|{"smithy":"2.0","shapes":{"example.weather#CityName":{"type":"string"}}}
    ),
  )
  inspect(document.smithy, content="2.0")
  let shape = document.shapes.unwrap().get("example.weather#CityName").unwrap()
  inspect(shape.kind.keyword(), content="string")
  assert_eq(@json_ast.parse(@json_ast.stringify(document)), document)
}
```

`decode` accepts a core `Json` value and raises `@json.JsonDecodeError`.
`parse` accepts text and can also raise core `@json.ParseError` for invalid
JSON or excessive nesting. Decode errors carry a JSON Pointer, such as
`/shapes/example.weather#Names/member/target`. The records `JsonAst`,
`JsonShape`, `JsonMember` and `JsonReference` also implement core
`FromJson` and `ToJson`.

## Construct a document

```mbt check
///|
test {
  let names = @json_ast.JsonShape::new(
    List(Some(@json_ast.JsonMember::new("smithy.api#String"))),
  )
  let document = @json_ast.JsonAst::new(shapes={
    "example.weather#Names": names,
  })
  assert_eq(@json_ast.decode(@json_ast.encode(document)), document)
}
```

`JsonShape` contains common `traits` and `mixins`, plus a `JsonShapeKind`
with typed shape-specific fields. `JsonOperation`, `JsonService` and
`JsonResource` hold those shapes' properties. Constructors default optional
fields to absent. `JsonAst::new` defaults the specification version to `2.0`.
The encoder trusts caller-built records; callers must supply valid IDs and
leave mixins absent on an `Apply` entry.

## Preservation and validation

- Absent fields stay absent. Explicit empty maps and arrays stay present.
  Explicit `null` is rejected for structural fields; metadata and trait
  values can contain any JSON value, including `null`.
- Object maps retain insertion order, including the order of members.
  Encoding can rearrange a shape's fixed properties and changes whitespace
  and string escaping. This is a document codec, without source spans or CST.
- `parse` preserves every numeric token's spelling, including long decimals,
  large integers, signed zero and exponents beyond Double's range. It first
  validates with core JSON, then rebuilds values with an explicit stack to
  retain number representations. Duplicate object keys follow core JSON's
  last-key-wins behavior.
- `decode` retains the numeric representations present in its `Json` input.
  It cannot recover precision already lost by another parser. Use `parse`
  when reading Smithy JSON text. Core `Json` equality compares numbers as
  Doubles; use numeric representations or encoded text when checking exact
  precision.
- The decoder checks property types, required `smithy`, `type` and `target`
  fields, absolute ID syntax, member names and service rename names. Unknown
  properties are errors, including properties belonging to another shape
  kind. References permit `target` only; members permit `target` and `traits`.
- Model validation belongs to the semantic loader. This includes version
  support, reference resolution, target kinds, case-insensitive member
  collisions, mixin expansion, trait semantics and model merging. Collection
  members, map keys/values, named members and service versions may be absent
  because mixins can supply them. The codec preserves the version string
  and accepts legacy `set` without deciding whether a model's version allows it.

The unit tests cover every shape kind, malformed documents, exact numbers,
deep nesting and generated inputs. `tests/features/json-ast.feature` is the
acceptance contract. The compatibility suite round trips all 71 vendored
reference documents with no exclusions. `tests/tck/TCK_JSON_SHA` records the
upstream commit; refresh them with `mise run tck:vendor:json -- <git-ref>`.
