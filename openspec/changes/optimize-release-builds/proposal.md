# Proposal

## Why

PR #91 ran two Windows-plus-cross-build chains concurrently in CI and Release preview. Each serialized independent non-Windows compilation behind Windows qualification. Optimize that measured orchestration cost while retaining every existing check.

## What Changes

- Produce Windows and non-Windows release inputs concurrently in one reusable workflow, then package the exact outputs after both succeed.
- Give CI sole ownership of PR preview artifacts and smoke, retaining the prior release-file selector and fingerprint evidence policy.
- Keep Release ownership of actual releases, scheduled qualification and manual rehearsals. Preserve 30-day retry artifacts and exact-byte release smoke.
- Reject required skipped, missing, failed or cancelled work at the CI aggregate. Measure execution, queueing, critical path and runner work separately.

## Capabilities

No public behavior contract changes. This is build tooling; `skip_specs: true` is explicit.

## Beads

- **Tracked by**: `smithy-2qe.58`
- **Related**: `smithy-2qe.57` supplies coverage and timing baseline; `smithy-2qe.56.1` fixes the prior validation timeout.

## Impact

CI/Release workflow graph, reusable release builder, MoonBit distribution staging and CI selection/gate scripts, smoke fingerprint inputs, README and agent/release documentation. No dependency or compiler changes; no test category is deferred or removed.
