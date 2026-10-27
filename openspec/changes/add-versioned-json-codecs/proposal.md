# Versioned JSON codecs

## Why

Smithy's value checker and generated JSON codecs assume object-wrapped unions, so they cannot directly handle Morphir v3 tagged arrays or v4 compact values. Projects need one declared serialization contract to check, read and write versioned documents without maintaining inconsistent encoding rules in each tool.

## What Changes

- Add a schema-driven MoonBit runtime API for preparing codecs, checking JSON, decoding model-aware values and writing canonical JSON.
- Describe external, internal, adjacent, positional-array and deterministic untagged union forms through serialization traits and named profiles. Include explicit tuple ordering, dictionary layouts, compact forms and reader aliases.
- Let library, CLI and build configuration select declared profiles. Preserve standard behavior when no profile is selected; do not change Smithy's JSON AST or existing protocol encodings.
- Dispatch versioned documents once from their declared version. Keep different semantic versions distinct and require explicit conversion between them.
- Provide registered scalar adapters for domain-specific spellings, with Morphir v3/v4 as the first conformance target. Readers accept the pinned profile's compatible forms; writers emit its canonical form or explicitly selected expanded output.
- Reuse value constraints, exact numbers, bounded traversal and source-based findings. Expose the prepared wire contract for later generator and schema-export integration.
- Add profile-aware CLI checking and JSON canonicalization. Generated typed codecs, Morphir v1/v2, semantic IR migrations and non-JSON formats are outside this first implementation.

## Capabilities

### New Capabilities

- `json-codecs`: Prepare, check, decode and encode application JSON with configurable representations, model-aware values, exact scalars and bounded diagnostics.
- `serialization-profiles`: Declare and select portable representation profiles, dispatch versioned documents and apply Morphir v3/v4 profile bundles without implicit migration.

### Modified Capabilities

None. No durable OpenSpec capabilities exist yet; existing validator and protocol behavior remains the compatibility baseline.

## Beads

- **Tracked by**: `smithy-2qe.53`
- **Related**:
  - `smithy-2qe.34.22`: supplies the confirmed JSON-kind-disjoint untagged-union rule; generated JSON-RPC ID support remains on that issue.
  - `smithy-2qe.41.8.13`: existing Morphir tour demonstrates the representation gaps and supplies checked examples.
  - `smithy-2qe.41.13`: recursive Morphir checks must retain bounded, near-linear work.
- Planning and validation are tracked separately by `smithy-2qe.53.1`; implementation groups will remain open until implemented and verified.

## Impact

The proposed codec library is `pkgs/smithy-codec`, with reusable contracts and an optional Morphir adapter package. Integration touches `pkgs/smithy-validation` only where shared budgets or location-aware value views require an additive API, and `apps/smithy` for profile selection and canonicalization. Models, pinned conformance fixtures and examples belong under `examples/morphir-codecs/`; acceptance scenarios belong under `tests/features/`. The Morphir tour must describe the resulting supported forms accurately.

Adding a module requires workspace, shared-version and publication-list updates under the repository's normal gates. This change does not bump the release version. The three language generators, JSON Schema exporter and RPC runtimes retain their current contracts; profile-aware generation/export is follow-up work, not an implied capability of a declared trait.
