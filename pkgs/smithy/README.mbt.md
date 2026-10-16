# moonrockz/smithy

An in-memory Smithy semantic model and multi-file loader for MoonBit. IDL
and JSON AST inputs assemble together with the official Smithy prelude.

## Load a model

```mbt check
///|
test {
  let result = @smithy.Loader::new()
    .add_idl(
      "city.smithy",
      (
        #|$version: "2"
        #|namespace example.weather
        #|structure City {
        #|    @required
        #|    name: String
        #|}
      ),
    )
    .assemble()
  assert_true(!result.has_errors())
  let model = result.model.unwrap()
  let name = model.get("example.weather#City$name").unwrap()
  guard name.body is Member(target~) else { fail("expected a member") }
  assert_eq(target.to_string(), "smithy.api#String")
  assert_true(name.trait_value("smithy.api#required") is Some(_))
}
```

Use `add_json(name, text)` for JSON text, `add_ast(name, document)` for a
typed `@syntax.JsonAst`, or `add(ModelInput)` for an input chosen at runtime.
Names identify sources in diagnostics; `<prelude>` is reserved.
The loader does no file-system or network I/O. Repeated calls to `assemble`
build fresh state without changing caller-owned AST documents.

## Semantic records

- `ShapeId` is an absolute ID with validated namespace, shape name and
  optional member name. `ShapeId::parse` returns `None` for invalid input.
- `Model` contains metadata and a map of shape IDs to `Shape` records,
  including first-class member shapes. `Model::get` accepts a string ID.
- `ShapeBody` distinguishes simple shapes, lists, maps, structures, unions,
  enums, operations, services, resources and members. Every reference is a
  `ShapeId`. A member's body holds its target; its traits belong to that member.
- `NodeValue` holds null, Boolean, number, string, array and object values.
  `NodeNumber` retains the original number token and compares exact numeric
  values. `1` and `1.0` compare equal; adjacent integers above Double's exact
  range remain distinct. Large exponents are stored without expanding zeros.
- A `Shape` retains its source, applied traits and direct mixin IDs.
  Inherited members have IDs belonging to their containing shape.

These records can also be constructed directly. Assembly validates a model;
mutating its maps afterward requires the caller to maintain those invariants.

## Assembly rules

The loader collects names across all inputs before resolving IDL references.
Resolution checks imports, definitions in the current namespace, then public
prelude shapes. Absolute references remain absolute. Only public prelude names
participate in implicit resolution. Unquoted IDL node values resolve as shape IDs;
quoted values remain literal strings.

The loader expands mixins using an explicit dependency stack. It checks
cycles, compatible shape kinds, member target conflicts and mixin restrictions.
Members follow mixin order, followed by local members. Local traits override
inherited traits, and mixin-local traits stay on their defining mixin. Service
properties merge across mixins. Resource-bound `$member` elision resolves
against identifiers/properties and inherited members.

External `apply` entries merge onto shapes and members after their targets
are known. List-valued traits concatenate; equal values are accepted; other
collisions fail. Metadata arrays concatenate, equal metadata values are
accepted, and other metadata collisions fail. Conflicting duplicate shape
definitions are errors. The prelude cannot be redefined or modified.

Inline operation structures receive the `input` or `output` trait, with names
controlled by `$operationInputSuffix` and `$operationOutputSuffix`. Missing
operation inputs and outputs target `smithy.api#Unit`. Enum members receive
their inferred string values after mixin inheritance. Legacy sets load as
lists with `uniqueItems`; set syntax in a Smithy 2.0 input is an error.

Assembly checks reference existence and target kinds, member-name collisions,
required collection members, enum values, resource cycles and the structure
of applied trait values. This is model assembly, not a selector engine or a
runner for configurable Smithy validation plugins.

## Diagnostics

`LoadResult` contains diagnostics and an optional model. Errors prevent a
partial model from being returned; warnings permit a model. Each diagnostic
has a stable code, severity, message, source and optional shape ID. IDL parser
diagnostics keep their original codes and UTF-16 spans. JSON codec errors keep
their JSON Pointer paths. `diagnostic_codes()` lists the assembly codes.

## Export a model

```mbt check
///|
test {
  let result = @smithy.Loader::new()
    .add_json(
      "name.json", "{\"smithy\":\"2\",\"shapes\":{\"example.weather#Name\":{\"type\":\"string\"}}}",
    )
    .assemble()
  let document = result.model.unwrap().to_json_ast()
  assert_eq(document.smithy, "2.0")
  assert_eq(document.shapes.unwrap().length(), 1)
}
```

`Model::to_json_ast` exports Smithy 2.0 with inherited contents flattened into
each shape. The prelude is omitted unless `include_prelude=true`. Exact node
number tokens survive export. Source locations and mixin provenance belong
to the in-memory model and are not serialized.

The prelude is vendored from smithy-lang/smithy at `PRELUDE_SHA`, embedded in
`prelude_data.mbt`, and distributed under Apache-2.0. Refresh it with
`mise run prelude:vendor -- <git-ref>`.

The acceptance contract is `tests/features/model.feature`. Compatibility tests
compare every paired vendored IDL/JSON model, check reference flattened mixins,
load the unflattened JSON mixin corpus and reject every invalid IDL case.
