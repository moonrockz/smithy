# Agent Instructions

This is a [MoonBit](https://docs.moonbitlang.com) monorepo for a Smithy implementation. Read [README.md](README.md)
for the layout and the task list.

## Toolchain

- `mise` installs and pins every tool (`.config/mise/config.toml`). Run `mise trust` and then `mise install` once.
- The MoonBit version is pinned there. Change it in the version field and in each URL together.
- `moon.work` lists the workspace members. `moon build`, `moon test`, `moon check` and `moon fmt` at the root act
  on all of them.

## Task scripts

Write task and automation scripts in MoonBit, as standalone `.mbtx` scripts, not as bash or PowerShell. One script
then works on every platform, and it uses the toolchain that mise already installs.

- Put the script in `scripts/` and run it with `moonx scripts/<name>.mbtx`.
- Declare its mise task in `.config/mise/config.toml`: `run = "moonx scripts/<name>.mbtx"`.
  `scripts/validate-packages.mbtx` (`mise run validate:packages`) is the reference example.
- Pin the version of each import: `"moonbitlang/async@0.22.5/process"`. Use `moonbitlang/async` for processes
  (`@process.run`, `@process.collect_output`), files (`@fs`) and `@stdio`; `moonbitlang/core/env` for `@env.args()`
  and environment variables; `moonbitlang/x/sys` for `@sys.exit`.
- `@env.args()` has the script binary at index 0. Task arguments start at index 1 (`mise run task -- arg`).
- A `.mbtx` file cannot start with a shebang line, so a mise file task cannot be a `.mbtx` file. Keep the toml
  task declaration.
- Exit with a non-zero code on failure. Do not print and continue.

## Pre-push checks

`mise run lint` and `mise run validate` must pass before a push. The git hooks are managed by
[lefthook](https://lefthook.dev/) and defined in `lefthook.yml`. Install them once with `mise run hooks:install`.
The pre-commit hook runs `moon fmt --check` and `moon check --deny-warn`. The pre-push hook runs lint, validate
and test. `mise run check` runs lint, validate, test and build, which is what CI runs.

## Working rules

- Commits use Conventional Commits, in plain English, with no AI attribution and no `Co-Authored-By` lines.
- Run `mise run format` before you commit MoonBit code.
- New packages go under `pkgs/` (libraries) or `apps/` (executables), and into `moon.work`.

## Working documents

`.dev/` is a gitignored area for AI-assisted work: specs, plans, brainstorming notes, scratch scripts and
their output. Nothing in it is committed. This overrides the default location of every skill or tool.

- Specs (superpowers `brainstorming`): `.dev/docs/superpowers/specs/YYYY-MM-DD-<topic>-design.html`.
- Plans (superpowers `writing-plans`): `.dev/docs/superpowers/plans/YYYY-MM-DD-<topic>-plan.html`.
- Scratch scripts and output: `.dev/scripts/`, `.dev/out/`.
- Write these documents as standalone HTML, not Markdown: one file with inline CSS that works in light and
  dark mode, and inline SVG for diagrams. Screenshots go next to the file.
- Never put a spec or plan under `docs/`, and never `git add` anything under `.dev/`. When a design is
  final and meant for readers, write it up on purpose in a committed location.

## Syntax module

`pkgs/smithy-syntax` is the IDL syntax layer. Its design is
`docs/superpowers/specs/2026-10-15-idl-syntax-design.md`; keep it current when
the API changes. Rules that tests enforce:

- The scanner and the CST are lossless: `to_source()` is the input text.
- Every diagnostic code is in `src/diagnostic/codes.mbt`; messages are in the
  first person and name the construct and the token found.
- The parser never panics and never raises out of `parse`; laws in
  `*_law_test.mbt` check this with quickcheck.
- `tests/tck` holds the vendored reference corpus; refresh it with
  `mise run tck:vendor`, and record skipped cases on the beads task.
- `tests/features/*.feature` are the acceptance contract, run by moonspec from
  `tests/bdd` (`mise run test:bdd`). Change the scenario when you change the
  behavior.

## Traversal

`pkgs/smithy-syntax/src/traversal` is the node model and the traversal styles over the AST. Rules that tests
enforce:

- No walk recurses: `walk`, `fold`, `reduce`, the event reader, `Tree` and the cursor each keep their own stack.
- The kind table in `src/traversal/README.mbt.md` (between `<!-- kinds:start -->` and `<!-- kinds:end -->`)
  is the contract. `tests/features/traversal.feature` checks it against `kind_table()`. When you add a kind or
  a field, update both.
- Kind and field names follow the Smithy JSON AST where it has a name, and the IDL grammar for the rest.
- `NodeRef::span()` widens the AST span over doc comments, so a child always lies inside its parent.
- With the same `Control` decisions, every style gives the same enter and leave order; laws in
  `src/traversal/*_law_test.mbt` check this.

## Release process

Smithy publishes to **mooncakes.io** and **GitHub Releases**, and records every release in `CHANGELOG.md`.

- The release-manager skill (`.claude/skills/release-manager/`) walks an agent through a release, the
  troubleshooting (`TROUBLESHOOTING.md`) and the improvement of the process. Agents other than Claude Code can read
  its `SKILL.md`.
- `mise run release:status` checks that main, the tags, the GitHub release and mooncakes.io agree. Each problem it
  prints names the command that fixes it.
- All modules share one version. The root `moon.mod` is the source of truth. `mise run validate:versions` (part of
  `validate`) fails when a module, a sibling import or a `version()` string has another version.
  `moonx scripts/versions.mbtx set X.Y.Z` rewrites them. The first release is `0.0.1`.
- To release, run `mise run release:prepare [X.Y.Z]` on a clean working tree. It computes the next version with
  git-cliff (`cliff.toml`), sets the version everywhere, prepends the section to `CHANGELOG.md`, commits
  `chore(release): vX.Y.Z` on `release/vX.Y.Z`, pushes it and opens a draft pull request. `--local` stops before
  the push.
- Replace the highlights comment in `CHANGELOG.md` with a few sentences. Push, then run `mise run release:refresh`.
  It writes the notes into the pull request body and marks the pull request ready. Then merge. Do not bump the
  version in another pull request.
- The merge changes `moon.mod` on main, so the Release workflow (`.github/workflows/release.yml`) runs. The jobs are:
  - `plan` (`mise run release:plan`) releases when `vX.Y.Z` has no GitHub release and `CHANGELOG.md` has the
    section with its highlights. It fails when the section is missing or has the placeholder.
  - `validate` runs `mise run check`, `mise run test:scripts` and the version check.
  - `build` (`mise run build:release`) cross-builds five native binaries with zig on one Ubuntu runner, builds
    `smithy.wasm` and `smithy-gc.wasm`, and packs `dist/` (`mise run release:assets`).
  - `smoke` runs `smithy version` from each archive on a runner of its own OS.
  - `publish` (`release:credentials`, `release:publish`) publishes the modules in `scripts/publish.mbtx`:
    `pkgs/smithy-syntax` and `apps/zig-cross`. It needs the `MOONCAKES_USER_TOKEN` org secret. It runs after
    `smoke`, because a mooncakes.io version is permanent.
  - `release` (`release:notes`, `release:github`) creates the tag and the GitHub release with the 8 assets.
- A pull request that changes a release file, and a manual run with `dry_run`, run `plan`, `validate`, `build` and
  `smoke` only. They never publish and never create a release.
- **Re-run failed jobs.** After a transient failure, use "Re-run failed jobs" on the run (or
  `gh run rerun <run-id> --failed`). GitHub runs the failed job again, and the jobs after it. The jobs that passed
  keep their outputs and the `dist` artifact (30 days), so the retry ships the bytes that `smoke` checked.
  `publish` skips a version that is already published, and `release` uploads only the missing assets, so a retry
  after a partial run continues where it stopped. Network calls also retry 3 times (waits of 5, 20 and 60 s), but
  not after a 401, 403 or 409. For any other failure, run `mise run release:status` first.
- The zig cross-build is the module `apps/zig-cross` (`moonrockz/zig-cross`). The wrappers add `-D_CRT_RAND_S` and,
  for each named target, drop the host-only simdutf and libbacktrace objects. See `apps/zig-cross/README.md`.
  `mise run build:cross` builds some targets, and `mise run test:native-zig` runs the native tests with zig.
- Write commit and pull request titles for the changelog: the squash-merge title is the changelog line.

## Work tracking

Issues live in [beads](https://github.com/steveyegge/beads) (`bd`), in a Dolt database that syncs through
`refs/dolt/data` on the GitHub origin, separate from the source branches. The config in `.beads/` is
committed; the database is not. On a fresh clone run `bd bootstrap`, or `bd init -p smithy --shared-server`
when the clone has no Dolt data yet.

- `bd prime` prints the workflow; `bd ready` lists unblocked work; `bd show <id>` gives the context.
- `bd update <id> --claim` before starting, `bd close <id> --reason "..."` when done.
- `bd sync` publishes issue changes. Run it at the end of a session; it needs no commit.
- The top epic is `smithy-2qe`, one child epic per sub-project.
