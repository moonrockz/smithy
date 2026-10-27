# Morphir codec coverage

This inventory states what the Morphir bundles in `model/` check, which pinned cases pass, and what is not
covered. The authorities and pins are in [README.md](README.md).

## Supported releases

The `morphir` bundle (`model/morphir-bundle.smithy`) has this support table, in the canonical notation of the
format-version contract:

```
[3.0.0,3.2.0),[4.0.0,4.1.0)
```

| Releases | Root | Profiles | Notes |
| --- | --- | --- | --- |
| `[3.0.0,3.1.0)` | `morphir.ir.v3#IRFile30` | `morphir-v3` | Library only. A Specs distribution at `3` or `"3.0.x"` is refused (specs_before_3_1). |
| `[3.1.0,3.2.0)` | `morphir.ir.v3#IRFile31` | `morphir-v3` | Library and Specs. |
| `[4.0.0,4.1.0)` | `morphir.ir.v4#IRFile` | `morphir-v4` (default), `morphir-v4-expanded` | Library, Specs and Application. |

Morphir v1 and v2 (integer `1` and `2`) are not supported: the bundle reports them as unsupported releases.
Releases `3.2.0` and later v3 minors, `4.1.0` and later v4 minors, and every later major are also unsupported.
A document is read with the root of its own release. No release is converted to another: a v3 artifact is
written as v3, and a v4 value cannot be written through a v3 root.

The canonical writers emit integer `3` or `4` for a baseline release and the exact string for any other
release, and put `formatVersion` before `distribution`. A decoded release is kept on output: a `"3.1.0"`
Library is written as `"3.1.0"` (D14).

## What the bundles check

The bundles check the **JSON representation** and the constraints that the models declare:

- every v3 and v4 node family: names, paths and FQNames; access control and documentation; packages, modules,
  type and value specifications and definitions; all type expressions, patterns, literals and value expressions
  (18 v3 and 19 v4 value kinds); v4 attributes, annotations, incompleteness, holes, native and external bodies,
  Specs and Application distributions;
- the v3 tagged-array arity, the v3 word grammar, Elm Dict key order and duplicate-key refusal;
- the v4 canonical and compact forms, the expanded forms, the documented legacy reader spellings, the name
  grammar and the legacy word-array decoding, key order preservation and duplicate-member refusal;
- the format-version grammar, the integer and baseline-string spellings, and exact number tokens (integers of
  any size, decimals and floats as written, document literals verbatim).

The bundles do **not** perform Morphir's semantic passes: type checking, reference and name resolution (an FQName
need not name a declared type or value), the uniqueness of type variables, the agreement of an inferred type with
its value, entry-point targets, or migration between releases. YAML, document trees, the MCK adapter protocol
and warning diagnostics (`legacy_spelling`, `format_version_not_first`) are also out of scope: legacy spellings
are accepted silently.

## Pinned cases

`cases.json` lists 323 cases. `mise run test:bdd` runs all of them (tests/bdd/morphir_codecs_world_wbtest.mbt)
and the scenarios of tests/features/morphir-codecs.feature.

| Group | Cases | Pass | Recorded gaps | Out of scope |
| --- | --- | --- | --- | --- |
| Full artifacts (v3 greeting, direct-rules, rule-set; v4 complete, books-and-records, MCK library) | 6 | 6 | 0 | 0 |
| MCK JSON and text fences | 228 | 219 | 8 | 1 (YAML file) |
| Format-version corpus (scalars, JSON header order, JSON root diagnostics) | 42 | 42 | 0 | 0 |
| Naming corpus (uppercase style) | 47 | 47 | 0 | 0 |
| **Total** | **323** | **314** | **8** | **1** |

A valid case passes when it decodes, its canonical output equals the expected canonical JSON byte for byte
(whitespace removed from the expected fence), and canonicalizing that output again gives the same text. An
invalid case passes when checking refuses it. The three v3 artifacts round-trip byte for byte; the v4 complete
example canonicalizes to the canonical fence of MCK distributions-0004.

The feature adds negative cases that the upstream corpus lacks: duplicate and escaped-equal member names below
the root, legacy and canonical spellings of one name used as two keys, alias and canonical member spellings
together, two definition variants beside one `doc`, v3 duplicate keys, extra positions and non-empty type
attributes, Specs before 3.1, unsupported and invalid releases, and a payload of another family.

## Recorded gaps

A case with a `gap` in `cases.json` must still fail; the harness reports an unexpected pass, so this list cannot
go stale.

| Gap | Cases | Reason | What would close it |
| --- | --- | --- | --- |
| G1 | mck/definitions-0002/json-accepted-1 | v4 also reads the v3-style tagged array `["OpaqueTypeSpecification", []]` (D2). A union form cannot check a tag at position 0. | A union rule that accepts a tag-array reader layout beside its main layout. |
| G2 | mck/definitions-0006, 0017, 0018, 0019 json-accepted-2; mck/definitions-0010/json-accepted-1 | The nested legacy wrapper `{"doc": ..., "value": {...}}` (decision 0010 window). The definition is a flattened union member, which has no named-field alternative. | A reader alias for a flattened member (`value` holding the flattened union), and for a value specification nested under `value`. |
| G3 | mck/definitions-0007/json-accepted-1 | The legacy ExternalBody with one top-level `externalName` and `targetPlatform` instead of `externals`. Two fields form one list element. | A structure form that builds a one-element list from sibling fields. |
| G4 | mck/definitions-0008/json-rejected-1 | `targetPlatform` must be unique within `externals`. Smithy `@uniqueItems` compares whole items, not one field. | A keyed-uniqueness constraint, or a model of `externals` as a map with a list-of-objects layout. |

The single out-of-scope case is mck/distributions-0004/text-canonical, which names the YAML rendering of the
complete example.

## Authority decisions

The wire reference (`.dev/out/morphir-wire-reference.md` during development) records these decisions; the
models cite them as D-numbers.

| # | Decision |
| --- | --- |
| D1 | v4 Reference with arguments: the array `{"Reference": ["fq", ...]}` is canonical (MCK types-0003); the object form is read. |
| D2 | v4 does not read v3 tagged-array distributions (MCK distributions-0003); see G1 for type specifications. |
| D3 | v4 literals are written typed, `{"Literal": {"IntegerLiteral": 42}}` (MCK), not in the most compact spelling. |
| D4 | A module's `doc` is written last; a definition's or value specification's `doc` first (MCK). |
| D5 | Number tokens are kept and written unchanged (MCK byte equality), for literals and document literals. |
| D6 | v4 maps keep their member order (MCK byte equality); v3 dictionaries use Elm Dict order. |
| D7 | MCK legacy spellings are reader aliases; the JSON Schema calls them invalid. |
| D8 | A bare v4 type variable uses the full Name grammar, wider than the schema's lowercase compact pattern. |
| D9 | A legacy v4 FQName is `[Path, Path, Name]`; each part may be a string or an array; 4 parts are refused. |
| D10 | v3 words use the v3 schema grammar `^([a-z][a-z0-9]*|[0-9]+)$`. |
| D11 | v3 is stricter than morphir-elm: exact arity, no unknown members, refused duplicate keys, `{}` type attributes, one-character CharLiteral. |
| D12 | v3 documentation is the `{"doc", "value"}` wrapper with a string doc; the unwrapped form is refused, as the v3 schema does. |
| D13 | v3 accepts the string release spellings of the format-version contract, which morphir-elm cannot read. |
| D14 | A decoded release is written back unchanged; a writer does not lower `"3.1.0"` to `3`. |
| D15 | MCK wins over the older BDD corpus: a string HoleReason and a PlatformSpecific hint without `platform` are refused. |
| D16 | A Hole incompleteness keeps a partial Type; an IncompleteBody keeps a partial Value. |
| D17 | A string directly under `Literal` or `LiteralPattern` (schema only) is refused as ambiguous. |
| D18 | A bare number is an IntegerLiteral when its token is an integer and a FloatLiteral otherwise, an exponent included. |

Other model choices: v4 Library, Specs and Application require `dependencies` and `def`/`spec`, and modules
require `types` and `values`, because the canonical writer emits them even when empty; the schema lets a reader
omit them. A `formatVersion` number token must be a plain unsigned integer: `3.0` and `3e0` are refused.
