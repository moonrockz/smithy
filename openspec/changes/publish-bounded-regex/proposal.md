# Publish a reusable bounded regex module

## Why

Smithy validation needs runtime regular expressions with interruptible, deterministic work limits, which MoonBit core does not expose. Its private copy cannot be reused by other moonrockz libraries, and the 0.10.18 engine replacement makes this a useful point to establish a maintained public module.

## What Changes

- Add `moonrockz/regex` under `pkgs/regex`, with only MoonBit core dependencies. The user selected this module name for reuse beyond Smithy.
- Vendor the required engine, parser and support code from core commit `417988f6e19738a7f683ce19a6cf5aaf52c96965`, bundled with MoonBit 0.10.18. Record the source, license and complete hook inventory.
- Expose Boolean search, validated compilation limits and work limits, and a typed outcome distinguishing a completed non-match from budget exhaustion. Bound compilation as well as execution.
- Use an immutable compiled program and fresh execution state for each call. Meter transition construction, scanning and allocation so results and charges do not depend on prior calls.
- Keep Smithy's portable ECMA translation and shape-specific diagnostics in `smithy-validation`. Replace its private matcher with the public module and remove the old engine when integration passes.
- Prepare the new module for the existing versioned publication process. Actual publication belongs to the normal release workflow.
- Establish tests and documentation for downstream users. Capture extraction, lexer/token APIs, generated `lexmatch` and a full ECMA implementation are outside this change.

## Capabilities

### New Capabilities

- `bounded-regex`: Independent runtime Boolean matching with finite compilation limits, interruptible work accounting, deterministic outcomes, portable targets and verifiable vendoring provenance.

### Modified Capabilities

None. There are no existing main capability specs. The new capability records the existing Smithy integration guarantees alongside the new reusable API.

## Beads

- Owning epic: `smithy-2qe.60`, reused and expanded from the original re-vendor task, under `smithy-2qe`.
- Spec ID: `openspec/changes/publish-bounded-regex`.
- Implementation groups: `smithy-2qe.60.1` through `smithy-2qe.60.4`, with sequential dependencies.
- Related evidence: `smithy-2qe.41.13` and the investigation comment on `smithy-2qe.60`. Valid Morphir inputs must continue to pass without raising the default allowance or making pattern work free.

## Impact

New public module and dependency of `smithy-validation`; no reverse dependency on Smithy. Public types and examples are new. Existing Smithy APIs, accepted portable pattern profile, incomplete-result behavior and default limits remain the compatibility contract; exact numeric work units will be specific to the new engine and documented.

Affected integration points include `moon.work`, `pkgs/smithy-validation/moon.mod` and package imports, isolated consumer dependency resolution, `scripts/regex-vendor-check.mbtx`, module validation and version checks, the publication lists in `scripts/publish.mbtx` and `scripts/release.mbtx`, and their documentation. Historical release inventories must remain readable without adding the new module retroactively.

No new upstream dependency, workflow or release is needed to begin implementation. The current pinned copy remains until the replacement satisfies the verification gates.
