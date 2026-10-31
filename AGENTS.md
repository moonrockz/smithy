# Agent Instructions

This is a [MoonBit](https://docs.moonbitlang.com) monorepo for a Smithy implementation. Read [README.md](README.md)
for the layout and the task list.

## Toolchain

- `mise` installs and pins every tool (`.config/mise/config.toml`). Run `mise trust` and then `mise install` once.
- The MoonBit version is pinned there. Change it in the version field and in each URL together.
- The regex engine in `pkgs/smithy-validation/internal/regex` is a copy of the core regex engine,
  pinned to core commit `d3c49d103fbe7bcfe86a2299250bdfe52654e70d` (the core of 0.10.15+943464bfa).
  MoonBit 0.10.18 replaced that engine, so a MoonBit version bump deliberately does not re-vendor the
  copy until bead `smithy-2qe.60` gives the new engine a work-budget cost model.
  `mise run regex:vendor:check` (part of `mise run validate`) fetches core at the pinned commit and
  proves that the copy and its hooks match it; its README lists the steps for a re-vendor.
- The Windows `mise install` runs `tools/bootstrap-moonbit-windows.ps1`, which checks the core archive
  against `tools/moonbit-core-pin.json`. Copy both, and the `[tools."http:moonbit"]` block, from
  finos/morphir-moonbit `main` in a version bump. Do not compute a digest yourself.
- `moon.work` lists the workspace members. `moon build`, `moon test`, `moon check` and `moon fmt` at the root act
  on all of them.

## Task scripts

Write task and automation scripts in MoonBit, as standalone `.mbtx` scripts, not as bash or PowerShell. One script
then works on every platform, and it uses the toolchain that mise already installs.

- Put the script in `scripts/` and run it with `moonx scripts/<name>.mbtx`.
- Declare its mise task in `.config/mise/config.toml`: `run = "moonx scripts/<name>.mbtx"`.
  `scripts/validate-packages.mbtx` (`mise run validate:packages`) is the reference example.
- Put the imports in frontmatter, between two `----` lines at the start of the file. MoonBit 0.10.18
  warns about an import block outside frontmatter (`unfenced_import`).
- Pin the version of each import: `"moonbitlang/async@0.22.7/process"`. Use `moonbitlang/async` for processes
  (`@process.run`, `@process.collect_output`), files (`@fs`) and `@stdio`; `moonbitlang/core/env` for `@env.args()`
  and environment variables; `moonbitlang/x/sys` for `@sys.exit`.
- `scripts/test.mbtx`, the `tests` module, `site`, `runtimes/moonbit` and the generated MoonBit peers stay
  on async 0.22.5. async 0.22.7 fails wasm-gc validation when a module reaches its scheduler
  (moonrockz/moon-lander#154), and zig-cross 0.3.2 hides `O_PATH` from it on a Linux glibc host
  (moonrockz/moonx-tools#17). Generated peers are built with the consumer's toolchain, and async 0.22.6
  and later need the 0.10.18 core.
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
- Compound CLI commands use nested subcommands, such as `smithy validate value` and `smithy validate rpc`.

## Domain modeling

- Give distinct domain concepts distinct types with validated boundary constructors.
- Model relationships and acquisition history as structured data. Render strings only at filesystem, serialization and diagnostic boundaries.
- Keep physical locations, container entry paths and logical resource names distinct. Prefer behavior on domain values over parsing or rewriting rendered text.

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

## OpenSpec

Use [OpenSpec](openspec/README.md) for spec-driven changes. Its versioned changes and capability specs live
in `openspec/` and are committed. This is an explicit exception to the scratch-document rule above.
Superpowers documents and other scratch work still belong in `.dev/`.

- `openspec/config.yaml` selects the project-local `html-design` schema. Read the CLI's instructions for each
  artifact and operation; they carry the HTML and beads rules to every agent.
- A change has `proposal.md`, spec deltas, `design.html` and `tasks.md`. Keep the CLI-parsed files in Markdown.
  Write designs as standalone HTML with inline CSS for light/dark mode and inline SVG where useful. Generated
  skills may say `design.md`; use the schema's actual `design.html` path and CLI status instead.
- Search beads before creating work. Each change has an epic bead linked with
  `--spec-id openspec/changes/<name>` and named in the proposal's `## Beads` section. Reuse existing work where
  possible; otherwise parent the epic under the relevant Smithy epic, defaulting to `smithy-2qe`.
- Each numbered task group has one child task bead, named in its heading: `## 1. Setup (smithy-abcd.1)`.
  Checkboxes do not each need a bead. Record group dependencies with `bd dep add <later> <earlier>`.
- Claim work before starting. Verify before checking off tasks; close a group bead only when all its tasks
  are complete, recording actual checks and any commit range. Report blockers in beads and leave tasks open.
- After archive, relink the epic and all group beads to the archived path. Close the epic when all groups
  are closed and the change is complete. Run `bd sync` at session end. These steps do not authorize a source
  commit, push, merge or release.

The generated `openspec-*` skills are installed for Codex and other `.agents` readers, Claude Code, Copilot,
Cursor, Gemini CLI and OpenCode. Do not hand-edit them. Change the schema/config for project overrides;
use the pinned CLI and `openspec update` to regenerate skills. Agents without skill discovery can read
`.agents/skills/openspec-<workflow>/SKILL.md` directly after this file. See `openspec/README.md` for setup.

## Syntax module

`pkgs/smithy-syntax` is the IDL syntax layer. Its design is
`pkgs/smithy-syntax/DESIGN.md`; keep it current when
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

## JSON-RPC generators

`pkgs/smithy-codegen-moonbit`, `pkgs/smithy-codegen-python` and `pkgs/smithy-codegen-go`
generate JSON-RPC peers. Their plugins are `moonbit-jsonrpc-codegen`,
`python-jsonrpc-codegen` and `go-jsonrpc-codegen`. They read the prepared contracts
of `pkgs/smithy-codegen-jsonrpc`; they do not read the RPC traits a second time.

- The runtimes are real code in `runtimes/moonbit`, `runtimes/python` and `runtimes/go`,
  with their own tests. Use `mise run test:runtime:moonbit`, `mise run test:runtime:python`
  and `mise run test:jsonrpc:go` for the language gates.
- After a MoonBit or Python runtime change, run `mise run runtime:embed`. After a Go
  runtime change, run `mise run jsonrpc:go:runtime`. `mise run validate` fails when an
  embedded copy differs.
- `examples/payment-terminal/generated/` holds golden output. Regenerate MoonBit and
  Python with `mise run codegen:payment-terminal`, and Go with `mise run codegen:go`.
  Read each diff. CI checks both tasks with `-- --check`.
- Python uses the uv version in mise and locked dependencies. Go uses pinned `go.mod`
  and `go.sum` files. Do not add unpinned generated dependencies.
- The manual `jsonrpc-matrix.yml` workflow checks all 27 language and transport pairs.
  Each pair runs all four scenarios and checks its logs. Its Windows job checks the
  MoonBit and Python runtimes and peers, and the 12 MoonBit and Python pairs. See
  `examples/payment-terminal/INTEROPERABILITY.md` for commands and build provenance.

## Tour

Every lesson claim is a checked case. A difference from the Java reference is on the allow list with an issue
and is told in the lesson. Run `mise run tour:check` after a change to a lesson or to the playground core. The
format and the rules are in `site/tour/README.md`.

A lesson never holds a hand-copied CLI or API block. It includes a marked region (`<!-- tour:start NAME -->` ...
`<!-- tour:end NAME -->`) of a tested source: an `mbt check` block of a `.mbt.md` file, or a `console` or
`LANG file=NAME` fence of `apps/smithy/README.md`. `mise run test:cli` runs each `console` fence and writes each
`file=` fixture of that README. `console status=N` runs each command and requires exit status N; the text after a
command is its stdout, then its stderr. Do not remove a tour marker that a lesson uses: `mise run tour:check` and
`mise run site:check` then fail.

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
    section with its highlights. It fails when the section is missing or has the placeholder. It also writes
    `validate`, `build` and `record`, which select the jobs of the run (see below).
  - `validate` runs `mise run check`, `mise run test:scripts` and the version check.
  - `build` calls `.github/workflows/release-build.yml`. Its independent Windows job builds `smithy.exe`
    natively and runs the Windows acquisition and CLI checks. Its Ubuntu job cross-builds four native
    binaries with Zig and the two Wasm files, then stages only those six outputs. The package job waits
    for both producers, downloads their same-run artifacts and packs `dist/` without recompiling.
    A cross-built Windows binary reads arguments wrongly because MoonBit resolves core platform settings
    from the host OS. `mise run build:windows` remains the local Windows build command.
  - `smoke` (`.github/workflows/smoke.yml`, shared with CI) runs `smithy version` from each archive on a runner
    of its own OS. A release always smokes the bytes that it publishes.
  - `publish` (`release:credentials`, `release:publish`) publishes the modules in `scripts/publish.mbtx`:
    `pkgs/artifact-resources`, `pkgs/jmespath`, `pkgs/smithy-syntax`, `pkgs/smithy`, `pkgs/smithy-validation`, `pkgs/smithy-ion-validation`, `pkgs/smithy-codec`, `pkgs/smithy-build`, `pkgs/smithy-codegen`, `pkgs/smithy-codegen-jsonrpc`, `pkgs/smithy-codegen-moonbit`, `pkgs/smithy-codegen-python`, `pkgs/smithy-codegen-go`, `pkgs/smithy-diff`, `pkgs/smithy-jsonschema`, `pkgs/smithy-openapi`, `pkgs/smithy-openrpc`
    and `apps/smithy`. It needs the `MOONCAKES_USER_TOKEN` org secret. It runs after
    `smoke`, because a mooncakes.io version is permanent.
  - `release` (`release:notes`, `release:github`) creates the tag and the GitHub release with the 8 assets.
- Runs that do not release never publish and never create a release:
  - CI owns all PR validation and release artifacts. A PR touching a release file selected by
    `scripts/ci-plan.mbtx` also smokes that same-run `dist` when no trusted evidence exists. PRs never
    start a second Release build, record trusted evidence or file smoke-breach issues. The CI aggregate
    requires every core category and all selected smoke tests to succeed; only unselected smoke may skip.
  - The nightly schedule does the same on main, and records the evidence.
  - A manual run with `dry_run` is a full rehearsal: `validate`, the shared `build` and `smoke`. Use it to
    smoke again on demand.
- **Smoke evidence.** `mise run smoke:fingerprint` hashes the `git ls-tree` entries of the smoke inputs at HEAD:
  `apps/smithy` and `pkgs` without test files and Markdown, `moon.mod`, `moon.work`, the toolchain pins, the
  build, dist, zig-cross and smoke scripts, the CI, Release, shared release-build and Smoke workflows, the CI planner and the setup action
  (`mise run smoke:inputs` lists them). After all smoke platforms pass, a trusted run (a push to main, the
  schedule, a release or a manual run) saves `evidence.json` in the GitHub Actions cache under
  `smoke-evidence-<fingerprint>`. A pull request run is not trusted and records nothing. CI smokes after each
  push to main, on the `dist` artifact of the shared builder, only when the fingerprint has no evidence. A change
  outside the inputs, such as docs or tests, carries the evidence forward. The evidence never replaces the smoke
  of a release: the builds are not proven reproducible. GitHub removes a cache entry after 7 days without
  access; the next run then smokes again.
- **Smoke breach issues.** When smoke fails in a trusted run on main or on a release tag, the `report` job of
  `smoke.yml` (`mise run smoke:report`, `scripts/smoke-breach.mbtx`) files one GitHub issue with the label
  `smoke-breach`. A hidden marker in the body holds the signature of the breach: the fingerprint and the result
  of each failed platform, not the run. The same breach again changes nothing. A changed breach edits the open
  issue and adds a comment. A breach that comes back reopens its closed issue. When smoke passes in a trusted
  run, `record` closes the open issue (`mise run smoke:resolve`). Pull requests never file an issue.
- **Re-run failed jobs.** After a transient failure, use "Re-run failed jobs" on the run (or
  `gh run rerun <run-id> --failed`). GitHub runs the failed job again, and the jobs after it. The jobs that passed
  keep their outputs and the producer artifacts and `dist` artifact (30 days), so the retry ships the bytes that `smoke` checked.
  `publish` skips a version that is already published. `release` uploads only the missing assets. A retry after a
  partial run therefore continues where it stopped. Network calls also retry 3 times (waits of 5, 20 and 60 s).
  They do not retry after a 401, 403 or 409. For any other failure, run `mise run release:status` first.
- The zig cross-build uses the published `moonrockz/zig-cross` tool, maintained in
  [moonrockz/moonx-tools](https://github.com/moonrockz/moonx-tools/tree/main/apps/zig-cross).
  `scripts/zig-cross.mbtx` owns the exact package pin, independently of Smithy's release version.
  `mise run build:cross` builds some targets, and `mise run test:native-zig` runs the native tests with zig.
  The wrappers add `-D_CRT_RAND_S` and drop host-only simdutf and libbacktrace objects for named targets.
  Fix and release tool changes in moonx-tools, verify the published version, then update the launcher pin here.
  Smithy publishes only its own modules. Release status reads each tag's original publication list, including
  zig-cross for older releases that published it.
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

## Shared OpenSpec configuration

Use the shared `html-design` schema for new changes. Read `openspec/README.md`
and `openspec/config.yaml`; repository-local tracking and approval rules still apply.
The files under `openspec/schemas/html-design/` and `scripts/openspec-ext.mbtx`
are managed by Mission Control's openspec-ext bundle. Change the shared source
and reinstall instead of editing these snapshots. Run `mise run openspec:check`
and `mise exec -- openspec validate --all --strict` after configuration changes.
OpenSpec artifacts are committed project documentation; existing scratch-document
rules continue to apply to local notes. Existing changes retain their own schema.
