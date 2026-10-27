# JSON codecs

`moonrockz/smithy-codec` checks, decodes and writes application JSON against Smithy data shapes. The model
declares the JSON representation in traits and names it with a profile. A caller selects a profile; the
caller cannot change its rules. Checking, decoding and encoding use one prepared wire contract, so a
complete check without findings agrees with a successful decode.

- The `contract` package holds the typed identities, the trait definitions and the detached wire contract.
  A generator or a schema exporter can read the contract without the runtime.
- The `morphir` package holds the scalar adapters of the Morphir IR. General codecs do not import it.
- Without a selected profile, the base rules apply. `moonrockz/smithy-validation`, JSON-RPC and the Smithy
  JSON AST do not change. A profile in a model does not change any protocol that does not select it.

## Prepare once, check, decode and encode

`PreparedCodec::prepare` snapshots the reachable contract of a root under a profile. Later edits to the
model do not change the codec. The model loads with `@contract.loader()`, which knows the
`smithy.serialization` traits.

```mbt check
///|
test "one model with two representations" {
  let model = @contract.loader()
  .add_idl(
    "expr.smithy",
    (
      #|$version: "2"
      #|namespace example
      #|use smithy.serialization#jsonProfiles
      #|use smithy.serialization#jsonEncoding
      #|
      #|@jsonProfiles([
      #|  {id: "object"}
      #|  {id: "array", defaults: {union: {style: "tagArray"}}}
      #|])
      #|union Expr {
      #|  Num: Count
      #|  Add: Add
      #|}
      #|
      #|@range(min: 0, max: 100)
      #|integer Count
      #|
      #|@jsonEncoding(profiles: {array: {tuple: {members: ["left", "right"]}}})
      #|structure Add {
      #|  @required
      #|  left: Expr
      #|  @required
      #|  right: Expr
      #|}
    ),
  )
  .assemble().model.unwrap()
  let root = @smithy.ShapeId::parse("example#Expr").unwrap()
  let object = @codec.PreparedCodec::prepare(
    model,
    root,
    profile=Some(@contract.ProfileId::parse("object")),
  )
  let array = @codec.PreparedCodec::prepare(
    model,
    root,
    profile=Some(@contract.ProfileId::parse("array")),
  )
  let value = object.decode(
    "{\"Add\":{\"left\":{\"Num\":1},\"right\":{\"Num\":2}}}",
  )
  inspect(array.encode(value), content="[\"Add\",[\"Num\",1],[\"Num\",2]]")
  // A finding names the semantic shape and the original JSON location.
  let result = array.check("[\"Add\",[\"Num\",1],[\"Num\",101]]")
  inspect(result.findings[0].code, content="Range")
  inspect(result.findings[0].path.pointer(), content="/2/1")
}
```

`check` returns a `CodecResult` with findings and a completeness flag; `to_json()` gives the structured
diagnostic of `smithy validate value --format json`. `decode` returns a `CodecValue`, `encode` returns
text, and `canonicalize` does both under one request budget. A failed decode, encode or canonicalization
raises `CodecFailure` with the findings and returns no value and no partial output.

## Values

A `LogicalValue` is model-aware: a structure holds its present members by Smithy member name, a union
names its selected member, and a map holds logical keys. Equality compares numbers by exact value and
compares members and entries without regard to order.

A `CodecValue` keeps its semantic root: the root shape and the fingerprint of the logical contract
reachable from it. Profiles of one model and root share the root, so a value decoded under one profile
can be written under another. A value of another root, such as another version of a model, is refused
with `IncompatibleValue`; convert it explicitly. `PreparedCodec::value` is the validated builder: it
checks a caller's value, copies it into its normal form and returns a `CodecValue`.

```mbt check
///|
test "build a value and encode it" {
  let model = @contract.loader()
  .add_idl(
    "pair.smithy", "$version: \"2\"\nnamespace example\nstructure Pair { @required left: BigDecimal, right: String }",
  )
  .assemble().model.unwrap()
  let codec = @codec.PreparedCodec::prepare(
    model,
    @smithy.ShapeId::parse("example#Pair").unwrap(),
  )
  let value = codec.value(
    Structure([
      ("left", @codec.LogicalValue::number("12345678901234567890.000000001")),
    ]),
  )
  inspect(
    codec.encode(value),
    content="{\"left\":12345678901234567890.000000001}",
  )
  // An incomplete structure is refused before any output exists.
  try codec.value(Structure([("right", String("r"))])) catch {
    @codec.CodecFailure(result) =>
      inspect(result.findings[0].code, content="RequiredMember")
  } noraise {
    _ => fail("expected a refusal")
  }
}
```

## Declaring profiles

The traits are in the `smithy.serialization` namespace. Their definitions are in
`@contract.trait_definitions()`.

| Trait | On | Meaning |
| --- | --- | --- |
| `jsonProfiles` | a root shape | Declares profiles: `id`, optional `ruleSet` (use another profile's rules), `writer` (`canonical` or `expanded`), `unknownMembers` (`reject` or `ignore`), `defaults` (`union`, `dictionary`) and `requires` (capabilities). |
| `jsonEncoding` | a shape or member | A `base` rule for every profile and `profiles` rules by profile identifier. |
| `untagged` | a union | The base rule `{union: {style: "untagged"}}`. |
| `emptyAsAbsent` | an optional member | An empty structure, list or map is the same logical value as absence. |
| `jsonBundle` | a structure | A versioned document bundle; see below. |

A profile applies to the declaring shape and every shape reachable from it. For each shape the codec
uses the selected profile's rule, then the profile's defaults, then the base rules (`jsonEncoding.base`,
`untagged` and `smithy.api#jsonName`), then the standard layout. Two different declarations at the same
precedence are a `ConflictingDeclaration`. An unknown profile, a missing adapter or a rule that the
runtime does not implement fails preparation and names the shape. The codec never falls back to an
object-wrapped union. Rule names are open strings in the trait definitions, so a model can name a rule
that a runtime does not implement, and that runtime refuses it.

A configuration, such as a CLI option or a build plugin setting, selects a profile. It cannot change a
tag, a position or a layout.

## Representations

| Rule | JSON | Preparation checks |
| --- | --- | --- |
| `union: {style: "external"}` | `{"Add": {...}}` | The standard layout. |
| `union: {style: "internal", tag: "kind"}` | `{"kind": "Add", "left": 1}` | Each member targets an object structure, and no payload field has the tag's name. |
| `union: {style: "adjacent", tag: "kind", content: "value"}` | `{"kind": "Add", "value": ...}` | Distinct tag and content fields. A Unit member has no content field. |
| `union: {style: "tagArray"}` | `["Add", 1, 2]` | The tag is element 0. A payload structure with a tuple rule is spliced after the tag; another payload takes one element; a Unit member is `["Tag"]`, or `["Tag", {}]` with `unit: "slot"`. |
| `union: {style: "untagged"}` | `1` or `"a"` | The JSON kinds that the members accept are disjoint, after adapters and timestamp formats. Two numeric members are refused even with different ranges. |
| `tuple: {members: [...], rest, optional}` | `["a", 1]` | Explicit positions; every member has one. An optional position needs `optional: "omit"` or `"null"`; a required position after an omitted one is a hole and is refused. `rest` is a final list member. |
| `dictionary: {layout: "object" or "entries", key, order}` | `{"k": v}` or `[[k, v]]` | A `key` adapter gives logical keys. Two entries with the same logical key are refused. `order` is `key` (code-unit order), `adapter` or `preserve`. A `null` value of a `@sparse` map, like a `null` element of a `@sparse` list, stays `null`. |
| `adapter` | any declared kind | A host adapter with the declared input and output kinds. |

Member rules set `name` (the field name), `tag` (the union tag), `aliases` (reader-only names and tags),
`absent: "null"` (write absence as `null`, read `null` as absence) and `flatten: true` (read the fields
that no other member claims as an external union). A union rule can `accept` reader-only alternative
object layouts; a dictionary rule can `accept` the other layout. Writers always use the declared layout.

Tuple projection, tagged-array splicing and dictionary entry order are different things. A tuple rule
maps array positions to named members of one structure. A tagged array splices that tuple after its tag,
so the second element of `["Add", 1, 2]` is position 0 of the payload and its findings name `/1`. A
dictionary entry array is a list of `[key, value]` pairs whose order comes from the `order` setting, not
from the model.

```mbt check
///|
test "positions keep their source paths" {
  let model = @contract.loader()
  .add_idl(
    "entry.smithy",
    (
      #|$version: "2"
      #|namespace example
      #|use smithy.serialization#jsonEncoding
      #|
      #|@jsonEncoding(base: {tuple: {members: ["head"], rest: "tail"}})
      #|structure Call {
      #|  @required
      #|  head: String
      #|  tail: Sizes
      #|}
      #|
      #|list Sizes {
      #|  member: Size
      #|}
      #|
      #|@range(max: 9)
      #|integer Size
    ),
  )
  .assemble().model.unwrap()
  let codec = @codec.PreparedCodec::prepare(
    model,
    @smithy.ShapeId::parse("example#Call").unwrap(),
  )
  inspect(codec.canonicalize("[\"f\",1,2]"), content="[\"f\",1,2]")
  let result = codec.check("[\"f\",1,20]")
  inspect(result.findings[0].path.pointer(), content="/2")
}
```

## Compact forms and canonical output

A `forms` rule declares compact spellings on a union or a structure. Each form has a reader guard and
binds members; it can also have a writer guard.

- `read: {kind, adapter, field, absent}` matches by JSON kind, and optionally by an adapter that accepts
  the value, a field that the object contains, or a field that it does not contain.
- `bind: "name"` binds the whole value to one member. `positions: [...]` and `rest` bind an array. A union
  form names its `member` and binds fields of that member's payload; without `bind` or `positions` it reads
  the whole value as the payload.
- `write: {empty: [...], present: [...]}` selects the form for canonical output when every `empty` member is
  absent and every `present` member is present and not empty. A present empty value counts as absent only
  for an `emptyAsAbsent` member, so a compact form never drops a present empty member. Every member that the form does not
  bind must be in `empty`, so the form never drops information.

Preparation refuses a form that overlaps the shape's own layout or another form unless guards tell them
apart. At run time, two forms that both accept a value are an `AmbiguousForm` finding: declaration order
never decides. Two writer forms that both apply are refused in the same way. A profile with
`writer: "expanded"` ignores every form and writes the declared layouts; use it with `ruleSet` to name an
explicit expanded output of the same rules.

Readers accept every declared form and alias. Writers emit one canonical form chosen from the logical
value, not from the input spelling. A document that gives a member under its name and under an alias is
refused with `MemberCollision`. Canonical output keeps declared member order and exact number tokens;
whitespace is not kept.

## Scalar adapters

A host registers trusted adapters in an `AdapterRegistry`. A model can name an adapter but cannot load
or install one. An adapter declares the JSON kinds that it reads and the logical scalar kind that it
produces, and can order dictionary keys. Preparation refuses a missing adapter or a kind that the target
cannot hold. At run time:

- a failure is a finding at the value's path joined with the adapter's relative path;
- an adapter charges its work through `AdapterContext::charge`, which shares the request budget;
- the reader checks the output kind, and the writer checks that the adapter writes a kind that it reads.

Adapter laws: `read(write(x)) == x` for every logical value `x` that the adapter accepts, and `write` is
deterministic. The Morphir adapters are tested against these laws.

## Versioned bundles

```smithy
@jsonBundle(
  id: "doc"
  version: {field: "formatVersion", adapter: "test.version"}
  releases: [
    {since: "1.0.0", until: "2.0.0", root: V1, profiles: ["v1"]}
    {since: "2.0.0", until: "2.1.0", root: V2, profiles: ["v2", "v2-expanded"]}
  ]
)
structure Documents {}
```

`PreparedBundle::prepare` prepares a codec for each release binding and profile. To read a document it
finds the version field in the parsed object, whatever the field order, reads it with the version adapter
and selects the one binding whose half-open interval contains the release. Then it decodes the payload
with that root and profile only. A missing version, an invalid version, an unsupported release and a
release that an explicitly selected profile does not read are the distinct findings `MissingVersion`,
`InvalidVersion`, `UnsupportedVersion` and `VersionConflict`.

A `VersionedValue` keeps its exact release. Encoding writes the canonical spelling of that release and
refuses a profile that does not write it. The codec never converts a document from one release to
another; a conversion between versions is an explicit operation outside this module.

## Limits

`CodecLimits` bounds one request: input bytes, output bytes, depth, work and findings. Parsing, form
selection, adapters, constraint checks and output all charge one work meter, and a later phase receives
only the work that is left. Text input is limited to 128 levels of JSON nesting. Every traversal uses an
explicit stack. When a limit is reached, the result is incomplete, never valid, and no value or output is
returned. Preparation visits each reachable shape once.

## Compatibility

Smithy value constraints come from `moonrockz/smithy-validation`: ranges, lengths, patterns, enums,
unique items and timestamp and blob formats apply to the logical value, with findings at the original
input location. Requests for profile-aware code generation or schema export are refused by the
generators and the JSON Schema exporter; they still use their standard contracts.
