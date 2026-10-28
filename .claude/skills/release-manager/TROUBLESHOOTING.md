# Release troubleshooting

Each entry has the symptom (the text you see), the cause and the fix. Start with `mise run release:status`.

A transient failure in `publish` or `release` needs no change. Use "Re-run failed jobs" on the run
(or `gh run rerun <run-id> --failed`). GitHub runs again the failed job and the jobs after it. The jobs that
passed keep their outputs and the `dist` artifact, so the retry ships the bytes that `smoke` checked. `publish`
skips a version that mooncakes.io already has. `release` creates the GitHub release only if it does not exist,
and uploads only the missing assets. Do not use "Re-run all jobs": it builds again.

Add an entry for every new failure. Keep the newest entries at the end of their section.

## release:prepare

**One standalone consumer package pin keeps the previous version**
Cause: the old version script used only the first registered prefix for each file, so a consumer
importing two different workspace modules left its second pin unchecked and unchanged.
Fix: use the updated script, which checks and rewrites every registered prefix and reads each source
file once. Run `moonx scripts/versions.mbtx set X.Y.Z` again on the release branch and verify the
standalone example imports before refreshing its PR.

**`the working tree has changes; commit them or set them aside first`**
Cause: `prepare` switches to `origin/main` and needs a clean tree.
Fix: commit the work on its branch, or set it aside with a WIP commit.

**`git-cliff could not compute the next version; run mise run release:prepare so mise provides git-cliff`**
Cause: git-cliff is not on the PATH. mise installs it from `.config/mise/config.toml`.
Fix: `mise install`, then run the task through mise.

**`version X is not above the latest tag vY; nothing to release, or pass a higher version`**
Cause: no commit since the last tag changes the version, or the version you passed is too low.
Fix: if a release is still wanted, pass a version: `mise run release:prepare 0.0.2`.

**`tag vX.Y.Z already exists`, or `branch release/vX.Y.Z already exists`**
Cause: an earlier `prepare` for the same version. `prepare` checks the tag, the local branch and the
branch on origin before it makes anything, and then puts the checkout back where it started.
Fix: if you only want to continue the release, do not run `prepare` again: `git switch release/vX.Y.Z`.
To start the release again, close its pull request, delete the branch (`git branch -D release/vX.Y.Z` and
`git push origin --delete release/vX.Y.Z`), then run `prepare` again.

**After a stopped `prepare`, HEAD is detached on `origin/main`**
Cause: the `prepare` of v0.7.0 or earlier switched to `origin/main` before its checks, and did not go back
when a check stopped it. The release branch is not changed.
Fix: `git switch release/vX.Y.Z`, or `git switch <your branch>`.

## Release pull request

**A pull request merged to main after `prepare`**
Cause: the new section was made before that merge. The tag will include the commit, but no section lists it.
Fix before the release merges: close the release pull request, delete its branch, run `prepare` again.
Fix after: add the line to the released section in a `docs(changelog)` pull request, then
`gh release edit vX.Y.Z --notes-file <(mise run release:notes X.Y.Z 2>/dev/null)`.

**The pull request body still shows the highlights placeholder, or the pull request stays a draft**
Cause: `prepare` writes the body before the highlights exist, or the pushed section has no highlights.
Fix: push the highlights commit, then run `mise run release:refresh` on `release/vX.Y.Z`. It is safe to repeat.

## Release workflow

**`plan` fails: "still has the highlights placeholder"**
Cause: the release pull request merged without its highlights.
Fix: write the highlights in a `docs(changelog)` pull request. That merge does not change `moon.mod`, so run
`gh workflow run release.yml --ref main` after it.

**No Release run started after the release pull request merged**
Cause: the workflow runs on a push to main only when `moon.mod` changes, or the workflow is disabled.
Fix: `gh workflow run release.yml --ref main`.

**`plan`: `tag vA does not match moon.mod version B`**
Cause: a tag was pushed by hand for a commit whose `moon.mod` has another version.
Fix: with the user's approval, delete that tag (`git push origin --delete vA`) and release through
`release:prepare`.

**`validate` fails**
Cause: main is not releasable, or a module has another version than the root `moon.mod`.
Fix: read the failed step. For a version error, run `moonx scripts/versions.mbtx check` to list each place,
then `moonx scripts/versions.mbtx set X.Y.Z`. Fix other errors on main with a normal pull request. Then run
`gh workflow run release.yml --ref main`.

**`validate` is cancelled with `maximum execution time of 30m0s`**
Cause: the full check and task-script suite can use the entire job budget. In v0.8.0 all 38 script tests
and the version check passed, but GitHub cancelled the job during cleanup at the 30-minute deadline.
Fix: inspect the completed job log and its annotations before treating cancellation as a test failure.
Retry only failed jobs on the original run to retain the built and smoke-tested `dist` artifact.
The validation job now allows 45 minutes, giving the observed 30-minute run headroom without removing
checks. An older run keeps its original workflow budget on retry; if it times out again, qualify and
run the corrected workflow on main before publishing. Never bypass validation to publish manually.

**`publish`: `401` or `403`**
Cause: the `MOONCAKES_USER_TOKEN` org secret is missing or expired. The job fails at once and does not retry.
Fix: ask the user to renew the secret, then "Re-run failed jobs".

**`publish`: `failed to open credentials file` or `Not logged in`**
Cause: `moon` reads `$MOON_HOME/credentials.json`. The setup action sets `MOON_HOME`, so a file in `~/.moon` is not found.
`scripts/credentials.mbtx` writes to `$MOON_HOME` when it is set. Check that the `credentials` step ran after `setup`.
Fix: correct the step order in `release.yml`, then "Re-run failed jobs".

**`publish`: `is duplicated with an existing version`**
Not an error: the script reports the module as already published and goes on.

**`release`: `403` or `Resource not accessible by integration`**
Cause: the job lacks `contents: write`.
Fix: check the `permissions` of the `release` job in `release.yml`.

## zig cross-build

The tool is maintained in [moonx-tools](https://github.com/moonrockz/moonx-tools/tree/main/apps/zig-cross).
Smithy's `scripts/zig-cross.mbtx` holds its exact published package pin. Tool fixes and publication happen
in moonx-tools; verify the new registry version before updating this pin. Smithy retains its own packaging
and native Windows build.

**`build` fails with `undefined symbol: moonbit_simdutf_*` or `invalid cpu architecture`**
Cause: moon links the prebuilt host objects `moonbit_simdutf.o`, `simdutf.o` and (on macOS) `libbacktrace.a`
for every target. Their architecture is not the target architecture. The cc and ar wrappers of
the published `moonrockz/zig-cross` tool drop them for each named target.
Fix: check that the wrapper still drops `-DMOONBIT_USE_SIMDUTF` and the arguments that end in
`/moonbit_simdutf.o`, `/simdutf.o` and `/libbacktrace.a`. Run `moonx scripts/dist.mbtx build` with the
moon version of CI to reproduce. A new moon version can add one more host object: fix the wrapper in
moonx-tools, release it there, then update Smithy's launcher pin.

**`build` fails with `call to undeclared function 'rand_s'` (windows-x64)**
Cause: `env.c` of the MoonBit runtime includes `<stdlib.h>` before it defines `_CRT_RAND_S`. The mingw headers
of zig then never declare `rand_s`.
Fix: every wrapper must pass `-D_CRT_RAND_S`. See the
[zig-cross README](https://github.com/moonrockz/moonx-tools/tree/main/apps/zig-cross).

**`build` fails with a wrong-architecture message**
Cause: the header check of `zig-cross` found a binary whose machine field does not match the target.
Fix: look at the table that `zig-cross` prints. Check that `MOON_CC` and `MOON_AR` point to the wrapper of that
target, and delete `_build/cross/<target>` for a stale build.

**`build` fails after a zig version change**
Cause: the zig version is pinned in `.config/mise/config.toml` (0.17.0). A new zig can change the flags or the
bundled headers.
Fix: pin zig back, or fix and release the wrapper in moonx-tools, then update Smithy's launcher pin.
Record the cause in the zig-cross README there.

## smoke

**The `smoke` leg for windows-x64 prints the usage text for `smithy.exe version`**
Cause: the archive holds a cross-built Windows binary. Moon resolves the `platform` setting of `core` from the
host OS, so a Windows binary built on Linux or macOS reads its arguments wrongly.
Fix: build `windows-x64` on a Windows runner (job `build-windows`). Check that `build` downloaded the artifact
`windows-x64-exe` into `_build/cross/windows-x64/native/release/build/moonrockz/smithy-cli/` before it packed.

**One `smoke` leg fails, the others pass**
Cause: the binary of that OS does not start, or `smithy version` did not print the version.
Fix: open the leg and read the output. A crash at start-up on one OS is a build problem for that target. For
example, a host-only object is linked, or the header is wrong. Reproduce with `moonx scripts/dist.mbtx build`
and fix the wrapper in moonx-tools if needed. Do not run `publish` while any leg is red: it needs all legs.
A runner that did not start is a transient problem. Use "Re-run failed jobs".
If `macos-15-intel` is not available, change the `darwin-x64` leg to run on `macos-latest` with
`arch -x86_64`.

**`smoke`: `the caller gave no version`**
Cause: `plan` (Release) or `smoke-plan` (CI) wrote no `version` output.
Fix: read that job. Run `gh workflow run release.yml --ref main`.

**A `smoke-breach` issue is open ("Smoke failed on main: <platforms>")**
Cause: a trusted run on main or on a release tag (CI after a push, the nightly run, a release, a dry run)
smoked binaries that failed on these platforms. A release of the same inputs will fail its `smoke` job too.
Fix: read the run and the messages in the issue, and fix the cause as for a failed leg above. To smoke again,
run `gh workflow run release.yml --ref main -f dry_run=true`. Do not close the issue by hand: a passing smoke in
a trusted run closes it. The same breach in a later run does not add a comment; a changed breach (other
platforms, results or inputs) edits the issue and comments.

**A `smoke-breach` issue stays open after a passing smoke**
Cause: the step `Close the open smoke breach` of `Record smoke evidence` failed after its retries. The step
cannot fail smoke (`continue-on-error`), because publish needs smoke, so the run shows only a warning.
Fix: read the step log. The next passing smoke in a trusted run closes the issue. If the breach is fixed and
no smoke will run soon, close the issue with a comment that links the passing run.

**`Report the smoke breach` fails with `HTTP 403`**
Cause: the calling job lacks a permission. The report reads the jobs (`actions: read`) and the annotations
(`checks: read`) of the run, and writes issues (`issues: write`).
Fix: give the job that calls `smoke.yml` in `ci.yml` or `release.yml` these permissions, then re-run the failed
jobs.

**A pull request or the nightly run skipped build and smoke**
Cause: a trusted run already smoked the same inputs. `plan` (or CI `smoke-plan`) found the cache key
`smoke-evidence-<fingerprint>`. This is expected.
Fix: none. To see the evidence, run `gh cache list --key smoke-evidence-` and open the run in the step summary of
`Record smoke evidence`. To smoke on demand, run the Release workflow with `dry_run`. To list the inputs, run
`mise run smoke:inputs`.

**`Record smoke evidence`: `HEAD has fingerprint ..., not ...`**
Cause: the record job checked out other inputs than the job that looked up the evidence.
Fix: re-run the whole run, so that both jobs use the same commit. Do not save the evidence by hand.

## After a partial release

**`status`: `vX.Y.Z is tagged but has no GitHub release`, or `lacks assets`, or `mooncakes.io has ...`**
Cause: the run stopped after the tag was made, or a transient failure stopped `publish` or `release`.
Fix: `gh workflow run release.yml --ref vX.Y.Z`. The run is safe to repeat.

**A version is on mooncakes.io but has no GitHub release**
Cause: `publish` passed and `release` failed (for example a network failure while it uploaded the assets).
The mooncakes.io version is permanent, so do not bump the version.
Fix: "Re-run failed jobs" on the run. If the artifact has expired (30 days), run
`gh workflow run release.yml --ref main`: it builds again and `publish` skips the published modules.
Then `mise run release:status`. Check that the 8 assets are on the release.

**`status`: `moon.mod on main is X but vX has no tag`**
Cause: the Release run for the merge failed or has not finished.
Fix: read the run (`gh run view <run-id> --log-failed`), fix the cause, then
`gh workflow run release.yml --ref main`.

**The GitHub release notes are wrong or out of date**
Fix: correct `CHANGELOG.md` in a `docs(changelog)` pull request, then
`gh release edit vX.Y.Z --notes-file <(mise run release:notes X.Y.Z 2>/dev/null)`.

**A broken version is on mooncakes.io**
A version cannot be replaced or deleted. Fix forward: release a patch version with the fix.

**`status` reports a newly added module as missing from an older release**
Cause: status used the working copy's publication list to judge a tag that never published that module.
Fix: use the updated status command, which reads `scripts/publish.mbtx` from the release tag, or
from `origin/main` when its version is untagged. Do not republish an older version to fill this gap.

**`status` reports zig-cross 0.1.2 as a problem for the Smithy 0.1.1 release**
Cause: zig-cross now releases independently from moonx-tools. Comparing only the registry's latest version
rejects an older release that is still published.
Fix: use the updated status command. It reads the original tag's publication list and checks for that exact,
unyanked version in the registry's version list. Do not rerun an old release to replace an immutable package.

**`status` reports `malformed publication entry: (` after formatting a long tuple**
Cause: an older reader required each tuple on one physical line.
Fix: use the updated reader, which joins formatter-wrapped tuples before parsing them.

## CLI checks

**`test:cli -- wasm-gc` cannot find `model.json` on Windows**
Cause: an older stdin guard also skipped file fixtures and conversion checks.
Fix: use the updated script. Only the stdin pipe check is skipped; file checks still run.
The skipped-stdin regression uses fresh fixtures so old output cannot hide this failure.

## Changelog generation

**The breaking-change line stops halfway through a migration sentence**
Cause: an older template took only the first physical line of a wrapped footer.
Fix: use the updated template, which joins the first paragraph of the footer.
For an already prepared release, restore the complete migration text in CHANGELOG.md,
then run `mise run release:refresh`. `mise run test:changelog` checks the real template offline.

## Published moonx CLI

**The immediate moonx smoke fails with `Prebuilt wasm asset does not exist`**
Cause: registry metadata can appear before the executable asset is available. During v0.1.0,
all four module publications succeeded and the same pinned moonx command worked shortly afterward.
Fix: re-run failed jobs on the original run. Published versions are skipped and the already-tested
dist artifact is reused. `release:verify-cli` retries this exact availability error for about 18
minutes (`cli_waits` in `scripts/publish.mbtx`: 5 s, 20 s, 60 s, 2 min, 5 min and 10 min; it was
85 seconds until v0.6.0, which failed this way). Authorization errors and non-transient failures
still stop at once. Before the re-run, check the asset by hand with the CLI package, not the
library module: `moonx moonrockz/smithy-cli@X.Y.Z version` must print the version.
`moonx moonrockz/smithy@X.Y.Z` always gives this error, because `moonrockz/smithy` has no
executable.
