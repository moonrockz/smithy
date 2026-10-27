# Tasks

Implementation is in progress. The planning task `smithy-2qe.53.1` is separate from these implementation groups. Claim a group's bead before work, check off tasks only after verification, and close the bead only when every checkbox in that group is complete.

The behavioral contracts are [json-codecs](specs/json-codecs/spec.md) and [serialization-profiles](specs/serialization-profiles/spec.md). [design.html](design.html) records the architecture and authority pins. Dependencies below are also recorded in beads.

## 1. Prepare portable profiles and object codecs (smithy-2qe.53.2)

- [x] 1.1 Add `pkgs/smithy-codec`, its `/contract` package, typed profile/tag/member identities and trait loader; register the module and shared-version/publication inputs, and verify package/version validation plus boundary-constructor refusal tests pass.
- [x] 1.2 Implement declared profile resolution, including selected-profile rules, defaults, base traits and same-precedence conflicts; verify unknown profile, invalid target, name collision and unsupported-declaration preparation tests.
- [x] 1.3 Implement model-aware values, validated builders and external-object check/decode/encode as the first working slice; verify executable examples round-trip recursive values and refuse incompatible semantic roots and invalid caller-created values.
- [x] 1.4 Compose exact-number and duplicate-aware text input with existing value constraints, source mapping and cumulative request budgets; verify escaped duplicate names, large integers/decimals, incomplete work and no-partial-output cases agree between checking and decoding.
- [x] 1.5 Document the runtime API and profile declarations in checked `README.mbt.md` examples, add the external-object acceptance scenarios, and verify the focused library tests and BDD scenarios pass on the pinned toolchain.

## 2. Add internal, adjacent and deterministic untagged unions (smithy-2qe.53.3)

Depends on group 1.

- [x] 2.1 Add internally tagged unions to the prepared contract and runtime; verify object-only target checks, effective `jsonName` handling, discriminator collisions and nested source diagnostics.
- [x] 2.2 Add adjacently tagged unions with distinct tag/content fields; verify scalar, Unit and composite payload round-trips and missing/extra-field failures.
- [x] 2.3 Implement the JSON-kind-disjoint untagged scalar rule from `smithy-2qe.34.22`; verify number/string selection, boolean/object refusal, overlapping numeric kinds and overlap introduced by scalar policy. Record runtime coverage on that issue while leaving its generator acceptance open.
- [x] 2.4 Extend checked API documentation and acceptance scenarios for all object layouts and scalar unions; verify each supported layout has valid, malformed and incompatible-contract cases and default RPC golden output remains unchanged.

## 3. Add positional tuples, tagged arrays and dictionary layouts (smithy-2qe.53.4)

Depends on group 1.

- [x] 3.1 Implement explicit structure tuple positions, fixed arity, optional-tail policy and final rest-list bindings; verify missing/duplicate positions, required-member holes, invalid rest placement and source-index findings.
- [x] 3.2 Add tag-first arrays using prepared tuple payloads and declared Unit handling; verify recursive examples, unknown tags, extra elements and exact positional output without deriving order from model maps.
- [x] 3.3 Support object dictionaries and two-element entry arrays with checked logical key identity and declared canonical ordering; verify normalized duplicate keys, malformed entries, stable key/value associations and deterministic output across targets.
- [x] 3.4 Add tuple/array/dictionary checked examples and BDD scenarios; verify the focused tests pass and document the distinction between tuple projection, tagged-array splicing and dictionary entry order.

## 4. Add compact forms and registered scalar adapters (smithy-2qe.53.5)

Depends on groups 2 and 3.

- [x] 4.1 Add explicit host scalar-adapter registration with declared input/output kinds, source paths, work charges and optional key ordering; verify missing bindings, malformed adapter output, failing adapters and bounded expansion cannot yield successful values.
- [x] 4.2 Implement the finite compact-form vocabulary and deterministic reader/writer guards from FORM-1; verify canonical/expanded logical equivalence, ambiguity refusal, bare-array versus wrapped-array distinctions and no declaration-order dependence.
- [x] 4.3 Add reader-only aliases and source mapping through scalar, tuple and synthetic-field projections; verify alias/canonical collisions, precise nested wire paths and cumulative budget exhaustion across projection and semantic checking.
- [x] 4.4 Document adapter laws, canonical-form selection and semantic equality in executable examples; verify encode/decode and idempotent canonicalization laws for compact, expanded and caller-constructed values.

## 5. Expose version dispatch and CLI/build selection (smithy-2qe.53.6)

Depends on group 4.

- [x] 5.1 Implement typed bundle declarations, nonoverlapping release bindings and bounded version-header selection before payload decoding; verify missing, malformed, unsupported and explicitly conflicting versions and headers in either field order.
- [x] 5.2 Add profile/bundle selection to `smithy validate value` and nested `smithy codec canonicalize`; verify target/bundle conflicts, stdin-once handling, exit statuses, structured diagnostics and destination preservation through CLI fixtures.
- [x] 5.3 Register the `jsonCodec` build plugin with check/canonicalize actions and a shared selection parser; verify library/CLI/build agreement, config-relative input resolution and validated artifact output names using build fixtures.
- [x] 5.4 Add explicit refusal for requested profile-aware generator/schema-export modes that are not supported; verify ordinary generation/export stays unchanged and `unionStrategy` is not accepted as a wire-layout selector.
- [x] 5.5 Document CLI/build usage in executable README fences and add profile-selection acceptance scenarios; verify `mise run test:cli` and the relevant BDD/build tests execute both successful and failing documented commands.

## 6. Deliver the Morphir v3 conformance bundle (smithy-2qe.53.7)

Depends on group 5.

- [x] 6.1 Vendor the selected v3/v4 conformance authorities under `examples/morphir-codecs/` with immutable pins, blob inventory, LICENSE/NOTICE and expected case IDs; add a MoonBit refresh/check task and verify unchanged input number lexemes and duplicate-key negative fixtures are preserved.
- [ ] 6.2 Model the v3 single-file roots and recursive type/value/pattern/definition/distribution families, including separate v3.0/v3.1 bindings and entry dictionaries; verify greeting/family fixtures, refuse Specs before v3.1, and avoid replacing modeled nodes with catch-all Document values.
- [ ] 6.3 Add the optional `smithy-codec/morphir` adapter package and v3 profile bindings for historical names, fully qualified names, dictionary ordering and version scalars; verify upstream naming/version cases and normalized-key collision failures.
- [ ] 6.4 Add v3 runtime, CLI and build examples plus a coverage inventory; verify supported v3 release intervals, semantic round-trips, unchanged version identity and explicit refusal of v1/v2, unsupported minors and v4-only values.

## 7. Deliver the Morphir v4 conformance bundle (smithy-2qe.53.8)

Depends on group 6.

- [ ] 7.1 Model the v4 root and recursive node families with `morphir-v4` and `morphir-v4-expanded` profiles; verify complete/books-and-records artifacts and family fixtures against the pinned schema/specification authorities.
- [ ] 7.2 Complete v4 naming bindings, bare reference/variable rules, Tuple shorthand, wrapped Reference argument arrays, attribute-sensitive writers and documented legacy aliases; verify equivalent forms, ambiguous/colliding inputs and canonical output against upstream cases.
- [ ] 7.3 Verify full v4 document read/write behavior through runtime, CLI and build fixtures, including baseline/exact version spellings, header order, exact numbers and no implicit v3 migration; record any authority disagreement with a bead rather than blessing a conflicting golden.
- [ ] 7.4 Publish the v4 coverage inventory and checked examples, then extend the Morphir tour with opt-in profile-aware cases while preserving existing default-profile results; verify `mise run tour:check` and `mise run site:check` and review the documented limitations.

## 8. Verify integrated codec laws, limits and compatibility (smithy-2qe.53.9)

Depends on group 7.

- [ ] 8.1 Run integrated check/decode agreement, semantic encode/decode, canonicalization idempotence and same-root cross-profile laws across every representation and both Morphir bundles; verify the integrated suite passes on wasm, wasm-gc, JS and native.
- [ ] 8.2 Exercise whole-request limits and recursive/wide Morphir workloads across version parsing, adapters, projection, constraints and output; verify bounded refusal, original source diagnostics, stable near-linear scaling and no successful partial output using recorded commands and measurements.
- [ ] 8.3 Run `mise run format`, `mise run check`, `mise run test:scripts`, `mise run test:bdd`, `mise run test:cli`, `mise run tour:check` and `mise run site:check`; review workspace/version/publication metadata, default validator/RPC/export regressions and the final diff, and record the actual results on the group bead.

## Workflow follow-up

- Review the implementation before requesting archive; source commits, pushes, merges and releases require their own authorization.
- After an authorized archive, relink the epic and every group bead to the archived path and close the epic only after all groups are complete.
- Keep `smithy-2qe.34.22` open until its remaining typed JSON-RPC generator requirements are satisfied; runtime coverage in group 2 is not sufficient to close it.
- Track profile-aware generated codecs and schema export, Morphir v1/v2 and explicit IR migrations as separate future work.
