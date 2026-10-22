# OpenRPC adapter on moonrockz/openrpc 0.2.0

`pkgs/smithy-openrpc` now builds its documents with the published
`moonrockz/openrpc` library. This is group 12 of moon-lander's OpenSpec change
`add-standalone-openrpc` (bead `lander-bwk.13`), tracked in Smithy as
`smithy-2qe.34.14`.

## Identity

| Item | Value |
| --- | --- |
| Dependency | `moonrockz/openrpc@0.2.0` from mooncakes.io, imported in `pkgs/smithy-openrpc/moon.mod` |
| Archive SHA-256 | `8f5c8785377676aefd3e038aed21853e533354f9a378c70306f3efad7238a659`, equal to the registry index entry and to the cached archive |
| Library source | moon-lander `1de7e46`, GitHub release `v0.2.0` |
| Recorded baseline | `c36698b3bd08be62d5d80e93b727ce736388adf6`, head of Smithy PR #45 |
| Baseline equivalence | PR #45 squash-merged as `edc6ba3`; `git diff c36698b edc6ba3` is empty |
| Migration base | `main` at `a9d3525135c0a8043705b8e31dadfcf39e7b4f2d`, which contains `edc6ba3`. No OpenRPC file (package, example, script, TCK, feature or plugin test) changed between `edc6ba3` and this base |
| Source | the commit that adds this record |
| Rollback | revert that commit; its parent is `a9d3525`, the qualified implementation |

No `moon.work` member or path override supplies the library. The isolated
consumer resolves it from a registry fixture seeded from the public index entry,
and checks that entry's checksum and the resolved manifest version.

## What moved

The library owns the OpenRPC object model (`Document`, `Info`, `Method`,
`ContentDescriptor`, `ErrorObject`, `ExamplePairing`, `Example`, `Components`),
draft-07 schema values, exact JSON values and document validation. The adapter
keeps the Smithy mapping, the runtime contract preparation, example checks
against the runtime validator, the extension loss policies, structured warnings
and shape-linked errors.

Each conversion runs `@openrpc.validate` with the `MetaschemaCompatibility`
profile. Any error fails conversion: `SchemaConversion` for schema-document and
reference findings, `UnsupportedMapping` otherwise. The subject is the operation
of the method that the finding is under, or the service. The profile reports an
optional parameter before a required one as a warning. Smithy keeps that order
on purpose.

## Public API and observable output

- `pkg.generated.mbti` for `moonrockz/smithy-openrpc` is identical before and
  after (`moon info`). `convert_result`, `convert`, `Conversion`,
  `ConversionWarning`, `WarningCode`, `OpenRpcError`, `Config` and
  `ExtensionPolicy` are unchanged.
- The owner approved one observable change on 2026-10-22: object members in
  `Conversion.document`, and so in `openrpc.json`, follow the library's
  constructor order. Values are unchanged. moonrockz/moon-lander#57 asks the
  library to define that order.
- Schema graphs: the library checks each schema position within fixed node and
  edge bounds that a caller cannot lift (moonrockz/moon-lander#56). The adapter
  does not fail conversion on `LimitExceeded`, so large services still convert
  as before. A 350-structure test with about 4,200 references covers this.

## Parity evidence

The parity check used a temporary, uncommitted print in `convert_result` and ran
the unit, CLI and BDD suites on native at the base and on the migration. That
gave 51 conversions: 18 documents, 18 warning lists and 15 errors. Every warning
list and error message is identical. Every document has the same value, with
exact number tokens; only member order differs. The final code repeats this
result. Its one extra conversion, from the new large-graph test, has no
baseline counterpart. The CLI build of
`examples/openrpc` gives equal values with three settings: default; `omit`; and
`useJsonName`, `date-time`, `title` and `apiVersion`.

## Compatibility rows

| Row | Smithy evidence |
| --- | --- |
| S01 | Settings tests reject 1.4.0 and JSON-RPC 1.0; README example and the consumer check `openrpc: 1.3.2`; `apiVersion` overrides `info.version` in the CLI parity run |
| S02 | Identical `pkg.generated.mbti`; `convert_result` returns `Json` and shape-linked warnings; `convert` returns `Json` |
| S03 | Positional order and naming-policy tests; parity run |
| S04 | `subtract` keeps optional `right` before required `left`; `document_wbtest.mbt` keeps optional-before-required order |
| S05 | Explicit null and empty-object result tests; example null result |
| S06 | Recursive `Nested` reference test; library reference facet; `check_references` in `test:openrpc`; large-graph test |
| S07 | Large exact integer example test; parity compares number tokens |
| S08 | Title, description and deprecation in the parity run; naming and timestamp schema tests |
| S09 | `x-smithy-protocol`, `x-smithy-error-data`, `x-smithy-error-examples` and `x-smithy-param-structure` in unit tests, BDD and the parity run |
| S10 | Error-data schema checks in `test:openrpc`; literal `$ref` example-data test |
| S11 | All warning codes, subjects and messages identical in the parity run; omit and fail policy tests; BDD omission scenario |
| S12 | Invalid modeled examples fail before export (`examples_test.mbt`) |
| S13 | `test:openrpc` rebuild and alias output equality on four targets |
| S14 | `mise run test:openrpc`: frozen digests, Ajv against the official 1.3.2 metaschema on four targets |
| S15 | Plugin tests in `apps/smithy`; `test:openrpc` failed-build status and no artifact on failure |
| S16 | `test:openrpc` compares Ajv with the RPC CLI for parameter, result and error data |
| S17 | Isolated consumer on native, wasm, js and wasm-gc with byte-identical output |
| S18 | Consumer manifest audit excludes Ion, WIT, WAC and wasm-devkit; `moonrockz/openrpc` is allowed only in the OpenRPC profile |

## Four-target results

| Check | native | wasm | wasm-gc | js |
| --- | --- | --- | --- | --- |
| `moonrockz/smithy-openrpc` unit tests | 21 passed | 21 passed | 21 passed | 21 passed |
| `apps/smithy` tests, including the plugin tests | 43 passed | 43 passed | 43 passed | 43 passed |
| `tests/bdd` | 16 passed | 16 passed | 1 passed, see below | 16 passed |
| Isolated consumer (`--openrpc`) | passed | passed | passed | passed |
| `mise run test:openrpc` | passed | passed | passed | passed |

On wasm-gc, `tests/bdd` runs only its synchronous test. The async feature
tests, including the OpenRPC feature, do not run there, at the base or now. The
unit tests, plugin tests and `test:openrpc` cover OpenRPC on wasm-gc.
