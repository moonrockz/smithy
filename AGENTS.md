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

## Work tracking

Issues live in [beads](https://github.com/steveyegge/beads) (`bd`), in a Dolt database that syncs through
`refs/dolt/data` on the GitHub origin, separate from the source branches. The config in `.beads/` is
committed; the database is not. On a fresh clone run `bd bootstrap`, or `bd init -p smithy --shared-server`
when the clone has no Dolt data yet.

- `bd prime` prints the workflow; `bd ready` lists unblocked work; `bd show <id>` gives the context.
- `bd update <id> --claim` before starting, `bd close <id> --reason "..."` when done.
- `bd sync` publishes issue changes. Run it at the end of a session; it needs no commit.
- The top epic is `smithy-2qe`, one child epic per sub-project.
