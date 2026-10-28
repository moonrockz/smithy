# Tasks

## 1. Parallel artifact production and packaging (smithy-2qe.58.1)

- [x] 1.1 Add narrow release-input staging and packaging support with missing-input regression tests; verify dist script tests and packaging fixture.
- [x] 1.2 Add the shared parallel producer/package workflow and document its artifact and retry contract; verify actionlint and workflow graph.

## 2. Unify PR preview ownership and gate semantics (smithy-2qe.58.2)

- [x] 2.1 Move PR preview selection into CI with focused event/path/evidence decision tests and required-result refusal tests; verify MoonBit script tests and local PR-ref selection.
- [x] 2.2 Wire CI and Release to the shared builder, update fingerprint inputs and maintainer documentation; verify selectors, actionlint, lint, validate and existing Release/smoke tests.

## 3. Measure and land orchestration optimization (smithy-2qe.58.3)

- [x] 3.1 Run local integration checks for input transfer, packaging, event/path selection and aggregate refusal; verify script tests, actionlint, lint, validate and OpenSpec strict validation.
- [x] 3.2 Prepare a PR description with preserved assurance, artifact trust/retry contract, retained PR #91 timing baseline and live verification plan; verify the submitted scope matches this design.

## Workflow follow-up

- Maintain the PR through selected CI, site and five-platform smoke gates. Record actual candidate/run/artifact evidence and timing comparison in the PR and smithy-2qe.58.3, so live observations do not cause documentation-only build reruns.
- Under the user's merge approval, squash-merge once ready, verify the merged tree, close the remaining beads and sync.
- Archive the completed change when requested.
