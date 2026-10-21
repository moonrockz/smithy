# Model diff reference corpus

Pinned Smithy source: `30bdab593f0c2cdf96036782cc3ce15c43a711ef`.
`inventory.json` records the upstream path and exact Git blob hash of every
vendored file, including the upstream license. `REFERENCE_SHA` records the pin.

The 176 upstream resources are all represented:

| Resources | Use |
| --- | --- |
| 124 model files | 62 old/new model comparisons |
| 39 `.events` files | Original reference-runner goldens |
| 13 single-model fixtures | Trait, pagination and legacy box mutations |

`events.json` records full events and breaking status from the actual Java
`ModelDiff` implementation. It covers the 62 upstream pairs, one additional local
pair that exercises the remaining built-in evaluators, and 21 mutations declared
in `mutations.json`. Mutation instructions reproduce the upstream Java unit
tests against assembled models, including mutations that intentionally bypass
assembly validation. Every upstream model is covered by the permanent inventory
test.

The original `.events` files have partial IDs and message prefixes. Reference
generation also executes the pinned `SmithyDiffTestSuite` against them. All
`diffs` and `testrunner/valid` cases must pass. The `testrunner/invalid` suite must
contain failing cases, as its upstream suite test requires. One unchanged pair in
that directory passes individually. The generated manifest records actual
events for all six test-runner pairs, including the intentional mismatches.

The portable tests compare exact event ID, severity, shape ID and message
multisets, plus breaking status. Event source offsets are not compared because
the MoonBit semantic model retains shape locations rather than every trait-node
location. Normal tests use these committed expectations without Java or network.

Regenerate or verify with a JDK and the pinned source snapshot:

```sh
mise run tck:vendor:diff -- .dev/reference/snapshot
mise run tck:reference:diff -- .dev/reference/snapshot
mise run tck:reference:diff -- .dev/reference/snapshot --check
```

The launcher verifies both corpus and Java source bytes against the pinned Git
tree before compilation. It writes temporary classes and source inventories only
under `.dev/out/reference-diff/`. These tasks are on demand. Committed parity and
acceptance tests run through the existing repository test pipeline.
