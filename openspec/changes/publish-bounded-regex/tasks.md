# Tasks

Owning epic: `smithy-2qe.60`. Claim each group before implementation. Close a group only after its checkboxes and evidence are complete. Dependencies are `1 -> 2 -> 3 -> 4`; these edges are recorded in Beads.

## 1. Public module and bounded compilation (smithy-2qe.60.1)

- [x] 1.1 Create `pkgs/regex` as `moonrockz/regex`, with core-only dependencies, the repository version and workspace membership; verify `mise run validate:packages`, `mise run validate:versions` and compiler checks for the new module.
- [x] 1.2 Introduce validated `CompileLimits` and `WorkLimit`, structured compilation/configuration errors and `MatchOutcome`; document zero allowance and supported maxima, and verify constructor boundaries and counter overflow rejection with focused public API tests.
- [x] 1.3 Copy the required core 0.10.18 packages at `417988f6e19738a7f683ce19a6cf5aaf52c96965`, retaining upstream licenses, tests and recognizable paths; record the initial source map and every added/changed file in NOTICE and the module README, and verify those paths against the pinned source without inherited `GIT_*` variables.
- [x] 1.4 Implement source and parser-nesting guards, checked pre-expansion counting and capture erasure before producing an immutable program; verify ordinary/named grouping, class/lowering costs, exact cap boundaries and rejection of `(?:a{256}){256}` before expanded allocation.
- [x] 1.5 Add checked compilation examples and an isolated compile-only packaged consumer; verify it builds using only this module and core, and run the parser/compiler-focused tests on native, JS, wasm and wasm-gc.

## 2. Meter the 0.10.18 regex engine (smithy-2qe.60.2)

- [x] 2.1 Separate immutable program data from fresh per-call execution state and expose bounded Boolean search through the public outcome type; verify search versus anchors, grouping erasure, Unicode and nullable repetitions against core with focused differential tests on all four targets.
- [x] 2.2 Implement a deterministic meter-aware state index and charge probes, key comparisons and rehash/growth work; verify collision-heavy cases, stable counts across fresh processes/targets and exhaustion during lookup and resizing.
- [x] 2.3 Meter initialization, the input/end charge, NFA closure, tag/register/key work, array allocation/copying and any retained cache-reuse/flush paths before performing their work; verify exact-budget boundaries, zero allowance, table growth and interruption inside a transition. Document the charge sites and derived storage bound alongside these changes.
- [x] 2.4 Ensure exhaustion discards partial runners and leaves immutable programs reusable; verify fresh/reused equivalence, repeated calls after exhaustion and cross-target outcome/count fixtures. Run the retained upstream engine tests and record necessary adaptations in the vendoring inventory.
- [x] 2.5 Extend the independent packaged consumer to execute and handle every public outcome, and add checked matching examples; verify the consumer builds/runs on all four targets without Smithy or async dependencies.
- [x] 2.6 Measure nested/overlapping repetition, optional chains, DFA state explosion, long inputs and useful Morphir patterns on native and JS or wasm-gc; deliver timings, allocation/peak-memory scope and cold/repeated-call comparisons in module documentation. Verify finite work stops pathological cases and document meaningful changes from the old cost model without raising validation defaults.

## 3. Integrate Smithy validation (smithy-2qe.60.3)

- [x] 3.1 Add the versioned sibling dependency and replace the private matcher adapter with `moonrockz/regex`, keeping ECMA translation, existing preparation guards and diagnostics in validation; prove accepted translations fit the adapter's larger finite library caps, and verify supported-profile laws, a translated pattern longer than 4,096 units and unsupported-constraint regressions.
- [x] 3.2 Preserve remaining-call and cumulative request allowances and map exhausted outcomes to incomplete `LimitExceeded`; verify shared-budget, RPC and codec composition tests, the 97-unit FQName, 16-reference record and deal record at the existing 100,000-unit default.
- [x] 3.3 Review algorithm-specific exhaustion fixtures: retain newly cheap optional-chain cases for correctness and use measured expensive cases for exhaustion expectations; verify an explicit inner-transition stop regression and warm/fresh equivalence without preserving old numeric work counts.
- [x] 3.4 Add the new module to isolated validation/Ion consumer dependency staging and allow lists; verify `mise run test:validation-consumer` and `mise run test:ion-consumer` resolve the complete packaged closure.
- [x] 3.5 Remove `pkgs/smithy-validation/internal/regex` after the replacement passes, update the validation README cost-model section and affected feature scenarios, and retarget the vendor check to the new location so `mise run validate` remains coherent. Verify `mise run test:bdd`, the validation package tests on all targets and absence of imports of the old path.

## 4. Prepare publication and verify integration (smithy-2qe.60.4)

- [x] 4.1 Add `moonrockz/regex` before validation in the publication inventories in `scripts/publish.mbtx` and `scripts/release.mbtx`; verify inventory-equality, dependency-order, shared-version and historical-tag status script scenarios without publishing.
- [x] 4.2 Finish the new-engine source/hook inventory in `regex:vendor:check`, preserving unexplained-drift, NOTICE/pin consistency and decoy-`GIT_DIR` regressions; verify the focused script scenarios and `mise run regex:vendor:check -- --diff` against the explicit source pin.
- [x] 4.3 Update AGENTS.md, repository layout and publication documentation to point to the public module and its maintainer instructions; verify documented import coordinates, package paths, version consistency and checked README examples.
- [x] 4.4 Run `mise run format`, `mise run check`, `mise run test:scripts`, `mise run bench:validate` and strict validation of this OpenSpec change; record actual results and resolve failures before checking off this group. Reuse earlier focused results unless a later change invalidates them.

## Workflow follow-up

- Review the artifacts and start the apply workflow before implementation, as the proposal skill requires.
- After verified implementation, follow repository authorization for any source commit, push, PR, archive or release. Preparation does not publish a mooncakes.io version.
- When archiving, relink the owning epic and all group beads to the archived change path and close only verified completed work. Run `bd sync` at session end.

## Initial verification recorded after implementation

- `mise run format` and explicit formatting of changed standalone scripts/examples passed.
- `mise run check` passed: lint, package/version/source validation, 1,467 tests each on wasm and wasm-gc, 1,574 tests each on JS and native, and builds on all four targets.
- `mise run test:scripts` passed all 41 script suites, including publication inventory/history and independent consumer checks.
- `mise run test:regex-consumer`, `test:validation-consumer` and `test:ion-consumer` passed on all four targets. The regex consumer resolved exactly one non-core module.
- The focused regex suite passed 150 tests per target; the validation/RPC/codec suite passed 304 per target; `mise run test:bdd` passed 19 tests including the recorded Morphir corpus status.
- `mise run regex:vendor:check -- --diff` passed with 44 equal upstream files, two parser hooks and 15 added files. Injected unlisted drift and a wrong NOTICE pin failed as expected; an explicitly injected decoy git environment left its checkout unchanged.
- `mise run bench:validate -- --no-build` reused the verified native release build and passed at 0.20/0.38/0.71 seconds for 1,000/2,000/4,000 shapes. Matching measurements and cost-count fixtures are in the public module README.
- Strict OpenSpec validation and `git diff --check` passed. Local task execution selected the pinned MoonBit binary ahead of an older global moonx, with inherited `GIT_*` variables removed.
- No source commit, source push, archive or package publication was performed.

## Pull request delivery preparation, 2026-11-07

- Package and provenance commit: `2399455`.
- Smithy validation switch and packaged consumers: `022d6fc`.
- Publication inventory and repository documentation: `701c651`.
- The toolchain remains MoonBit `0.10.18+6c83a7f62`; the 0.10.20 rollout is separate.
- Fresh [native and JS benchmark evidence](benchmarks/2026-11-07-native-js.json) includes all 48 measurements, the benchmark source, input generation, tool versions and library source fingerprint. Timing excludes compilation/input construction; memory is whole-process peak.
- `moonrockz/regex` is not published yet. This change prepares publication through the normal release process.
- Post-rebase gate results, PR head, CI and review state are recorded in the PR and bead `smithy-2qe.60` when delivery completes.
