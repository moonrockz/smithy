# OpenSpec

OpenSpec holds reviewed change proposals and behavior contracts. Smithy uses a project-local
[`html-design` schema](schemas/html-design/schema.yaml), adapted from
[`finos/morphir-moonbit`](https://github.com/finos/morphir-moonbit/tree/bd3adc52e6b8f6368fdaee50f76535799732f8d6/openspec).
Designs are standalone HTML; proposals, task checklists and spec deltas stay Markdown for the CLI.
The schema and [`config.yaml`](config.yaml) carry the same project rules to every coding agent.

## Setup

Install the version that generated the checked-in skills:

```shell
mise use -g npm:@fission-ai/openspec@1.14.3
openspec --version
openspec schema validate html-design
```

As in Morphir, OpenSpec is a developer tool installed globally with an exact version. It is deliberately
outside the repository's mise tools so CI jobs do not install it when running unrelated tasks.
Beads setup and the repository's working rules are in [AGENTS.md](../AGENTS.md#work-tracking).

The checked-in integrations need no initialization after cloning. Restart your agent to refresh discovery.
They provide `openspec-explore`, `openspec-propose`, `openspec-apply-change`, `openspec-update-change`,
`openspec-sync-specs` and `openspec-archive-change`.

| Agent | Skill directory | Instruction entry point |
|---|---|---|
| Codex and other Agent Skills clients | `.agents/skills/` | `AGENTS.md` |
| Claude Code | `.claude/skills/` | `CLAUDE.md` points to `AGENTS.md` |
| GitHub Copilot | `.github/skills/` | `.github/copilot-instructions.md` points to `AGENTS.md` |
| Cursor | `.cursor/skills/` | `.cursor/rules/repository.mdc` points to `AGENTS.md` |
| Gemini CLI | `.gemini/skills/` | `GEMINI.md` points to `AGENTS.md` |
| OpenCode | `.opencode/skills/` | `AGENTS.md` |

Use `$openspec-propose "change idea"` in Codex or select the skill in its UI. Other clients may expose
`/openspec-propose` or a skill picker. For any agent without discovery, use this portable instruction:

```text
Read AGENTS.md, then .agents/skills/openspec-propose/SKILL.md and follow it for this change.
```

Clients need shell access to `openspec` and `bd`, plus access to Smithy's beads database. Generated skills
are regular files, so discovery does not depend on symlink support. Copilot cloud setup is disabled;
hosted environments must provision the CLI and tracker access separately.

## Change workflow

1. Search existing specs with `openspec list --specs` and existing work with `bd search "<words>"`.
   Reuse an owning epic or create one under the relevant Smithy epic, defaulting to `smithy-2qe`.
2. Propose a change. Its epic's spec ID is `openspec/changes/<name>`; put that bead in the proposal's
   `## Beads` section. Record related beads and their relationships.
3. Write spec deltas and `design.html` using the schema's template. Keep HTML self-contained with inline
   CSS for light/dark mode and inline SVG where useful. Designs need no asset-path rewrite on archive.
   For changes with no behavior contract, set `skip_specs: true` in the change's `.openspec.yaml`.
4. Create one child task bead per numbered group in `tasks.md`, with the ID in the group heading.
   Each checkbox includes its verification. Add dependency edges between dependent groups.
5. Apply the change. Claim each group before starting, verify each task before checking its box,
   and close the group bead when every checkbox is complete. Record actual check results.
6. Validate with `openspec validate <name> --strict --no-interactive`. Follow the archive skill when
   archive is requested. It merges spec deltas and moves the change under `changes/archive/`.
   Relink the epic and all group beads to the archived path, and close the epic once all groups are done.
7. Run `bd sync` at session end. Source commits, pushes, merges and releases follow the active user's
   authorization and repository rules.

OpenSpec artifacts are committed. Superpowers documents and scratch output remain local in `.dev/`.
Beads is the record of ownership, status and dependencies; `tasks.md` is the implementation checklist.
Agents must keep them consistent. The OpenSpec CLI supplies instructions; it does not run beads commands
or validate tracker state automatically.

## Regenerate integrations

The CLI-generated `openspec-*` skill files record `generatedBy: 1.14.3`. Do not edit those files to add
project rules. Edit the schema, templates, config and root `AGENTS.md` instead.

To recreate the current integration set, use the pinned CLI. With global delivery set to `skills`:

```shell
openspec init --tools agents,claude,codex,github-copilot,cursor,gemini,opencode --profile core --no-copilot-cloud
```

Global delivery can be inspected with `openspec config get delivery`. Other delivery settings can also
generate tool-specific command files; do not change a developer's global settings as part of repository setup.
To upgrade, install the chosen exact version, run `openspec update`, review all generated diffs and update
the version above. Keep the independent Claude release-manager skill.

Check schema resolution and templates after any workflow change:

```shell
openspec schema which html-design
openspec schema validate html-design
openspec list --json
```

## Shared OpenSpec bundle

`html-design` comes from Mission Control's `moonrockz/openspec-ext` bundle.
The schema, templates, licenses and verification script are generated snapshots;
keep repository overrides in `openspec/config.yaml` and `AGENTS.md`.

- Run `mise run openspec:check` to verify the committed file hashes and default schema.
- Run `mise run openspec:setup` to regenerate the six core agent skills with isolated global preferences.
- Run `mise exec -- openspec schema validate html-design` and
  `mise exec -- openspec validate --all --strict` before review.
- New designs are offline `design.html` with inline CSS. Existing changes keep
  their schema metadata and original designs, including Markdown designs.
- OpenSpec requirements and change artifacts are committed project documentation.
  Scratch documents remain local under the existing repository rules.

The extension module awaits publication. Until then, update snapshots from a
Mission Control source checkout with its pinned toolchain:

```shell
mise exec -- moon run apps/openspec-ext/cmd -- install /absolute/path/to/this-repo
```

Run that command from Mission Control, then run this repository's checks. After
release, use `moonx moonrockz/openspec-ext@<published-version>/cmd install .`
with an actual published version. Do not add an unpublished registry dependency.
See [the shared tool guide](https://github.com/moonrockz/mission-control/blob/main/apps/openspec-ext/README.md).
