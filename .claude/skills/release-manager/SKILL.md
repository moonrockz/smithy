---
name: release-manager
description: Runs, troubleshoots and improves the smithy release process (release pull request, CHANGELOG.md, Release workflow, zig cross-build, mooncakes.io, GitHub release). Use when the user wants to cut, prepare or publish a release, write release highlights, check release status, fix a failed or stuck release, or improve the release process.
---

# Release manager

The process is in AGENTS.md > Release process. The tools are the `release:*` mise tasks
(`scripts/release.mbtx`, `scripts/publish.mbtx`, `scripts/dist.mbtx`, `scripts/versions.mbtx`,
`cliff.toml`, `.github/workflows/release.yml`). This skill runs them in order, checks each result, and makes
the process better after every release.

Start every session with `mise run release:status`. It prints `ok:`, `info:` and `problem:` lines, and each
problem names its fix command. It exits 1 when there is a problem.

Smithy consumes `moonrockz/zig-cross` through the exact pin in `scripts/zig-cross.mbtx`.
The tool is built, tested and published by [moonx-tools](https://github.com/moonrockz/moonx-tools).
Do not version or publish it with Smithy. Fix tool changes there, then update the verified package pin here.
Keep `release:status` reading each tag's original publication list, including zig-cross in older releases.

## Release

Copy this checklist and tick it off:

```
- [ ] 1. Preflight
- [ ] 2. Track the release in bd
- [ ] 3. Prepare the release pull request
- [ ] 4. Write the highlights
- [ ] 5. Merge
- [ ] 6. Watch the Release run
- [ ] 7. Verify
- [ ] 8. Retrospective
```

1. **Preflight.** `mise run release:status` must have no problem. The working tree must be clean, `gh auth
   status` must pass, and the latest CI run on main must be green (`gh run list --branch main --workflow ci.yml
   --limit 1`). Show the user `mise run release:version` and the commits since the last tag. Merge the open
   pull requests that the user wants in this release first.
2. **Track.** `bd create "Release vX.Y.Z" -t chore -l release --parent=smithy-2qe`, then `bd update <id> --claim`.
3. **Prepare.** Get the user's approval, because this pushes a branch and opens a pull request. Run
   `mise run release:prepare` (add a version to override git-cliff; the first release is `0.0.1`). It sets
   one version in every module, sibling import and `version()` string. The pull request opens as a draft.
4. **Highlights.** In `CHANGELOG.md` on `release/vX.Y.Z`, replace the highlights comment with 2-5 plain
   sentences: what a user can now do, what breaks and how to migrate. Commit as
   `chore(release): highlights for vX.Y.Z` and push. Run `mise run release:refresh`. Check the text with
   `mise run release:notes X.Y.Z`. Ask the user to review it.
5. **Merge.** Get the user's approval. The merge publishes to mooncakes.io, and a published version is
   permanent. Make sure no other pull request merged after `prepare`. Then `gh pr merge <n> --squash`.
6. **Watch.** `gh run list --workflow release.yml --limit 1`, then `gh run watch <run-id> --exit-status`. The
   jobs are plan, validate, build, smoke (5 legs), publish and release.
7. **Verify.** `mise run release:status` must say `vX.Y.Z is released`. Open the GitHub release and check the
   8 assets. On a Mac, run `mise use -g github:moonrockz/smithy@X.Y.Z` and `smithy version`.
8. **Retrospective.** Do "Improve the process" below. Close the bd issue with
   `bd close <id> --reason "..."`, then `bd sync`.

## Troubleshoot

1. Run `mise run release:status` and read the failed job (`gh run view <run-id> --log-failed`).
2. A transient failure is a timeout, a 502, 503 or 504, or a connection reset. If it is in `publish` or
   `release`, use "Re-run failed jobs" on the run, or `gh run rerun <run-id> --failed`. Do not use
   "Re-run all jobs", because it builds again.
3. Find any other symptom in [TROUBLESHOOTING.md](TROUBLESHOOTING.md) and apply its fix. Every fix is safe to
   repeat. The publish job skips a published version. The release job uploads only the missing assets.
4. If the symptom is not there, find the cause before you change anything. Then add it to TROUBLESHOOTING.md.

Do not delete or move a pushed tag without the user's explicit approval. Do not delete a GitHub release without it.
A mooncakes.io version cannot be replaced. Release a new patch version instead.

## Improve the process

After every release and every incident:

1. Ask what was slow, unclear, manual or wrong. Read the notes of earlier release issues
   (`bd list -l release --status closed`).
2. Fix the cause at the lowest level that works: a check in `scripts/*.mbtx` with a scenario in
   `scripts/features/`; then `cliff.toml` or `release.yml`; then AGENTS.md and this skill.
3. Add each new failure mode to TROUBLESHOOTING.md: symptom, cause, fix.
4. Store a lesson that must outlive the session with `bd remember "..." --key release-<topic>`.
5. Ship the change in its own pull request, never in the release pull request. Keep this file under 100 lines.
