# smithy

A [Smithy](https://smithy.io/) implementation for the MoonBit ecosystem, organized as a monorepo.

## Packages

| Path | Module | Purpose |
|------|--------|---------|
| `pkgs/smithy` | `moonrockz/smithy` | Smithy model library |
| `pkgs/smithy-syntax` | `moonrockz/smithy-syntax` | Smithy IDL scanner, AST, CST, parser and diagnostics |
| `apps/smithy` | `moonrockz/smithy-cli` | Command-line application |

The workspace members are listed in `moon.work`.

## Prerequisites

- [mise](https://mise.jdx.dev/). It installs every other tool: the pinned MoonBit toolchain, Node.js and yamllint.

## Setup

```shell
git clone https://github.com/moonrockz/smithy.git
cd smithy
mise trust
mise install
```

The mise binary archive of MoonBit omits the core library and `moonx`. If `moon version --all` does not show `moonc`,
complete the toolchain into the mise install directory:

```shell
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | MOON_HOME="$(mise where http:moonbit)" bash -s -- "$(mise current http:moonbit)"
```

Then install the git hooks, which [lefthook](https://lefthook.dev/) manages from `lefthook.yml`:

```shell
mise run hooks:install
```

The pre-commit hook checks formatting and runs `moon check`. The pre-push hook runs lint, validate and test.

## Tasks

Every task is a MoonBit script in `scripts/*.mbtx`, run with `moonx`, so one script works on every platform.
Run `mise tasks` for the list.

```shell
mise run check                 # lint, validate, test, build
mise run lint                  # yamllint, moon fmt --check, moon check
mise run format                # moon fmt
mise run validate              # package structure against moon.work
mise run test                  # all targets; the tests module runs on js and native only
mise run test -- js native     # some targets
mise run test:bdd              # moonspec acceptance features (tests/bdd, js target)
mise run build                 # all targets
mise run build:native          # native release build
mise run clean
mise run hooks:install         # git hooks (lefthook)
```

Without mise: `moonx scripts/<name>.mbtx [args]`.

The cookbook in `docs/cookbook` is a workspace member; `moon test` runs its articles.

## Layout

```
smithy/
├── .config/mise/config.toml   # tools and tasks
├── .github/workflows/ci.yml   # lint, build and test on every target
├── lefthook.yml               # git hooks
├── apps/smithy/               # CLI (moonrockz/smithy-cli)
├── pkgs/smithy/               # library (moonrockz/smithy)
├── pkgs/smithy-syntax/        # IDL syntax (moonrockz/smithy-syntax)
├── scripts/*.mbtx             # task scripts, run with moonx
├── moon.mod                   # workspace root module
└── moon.work                  # workspace members
```

## Adding a package

1. Create `pkgs/<name>/moon.mod` (module `moonrockz/<name>`) and a `moon.pkg`.
2. Add `"./pkgs/<name>"` to `moon.work`.
3. Run `mise run validate`.

## License

Apache-2.0. See [LICENSE](LICENSE).
