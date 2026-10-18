# smithy

A [Smithy](https://smithy.io/) implementation for the MoonBit ecosystem, organized as a monorepo.

## Status

The Smithy IDL 2.0 syntax layer (scanner, AST, CST, parser with recovery, diagnostics)
and the typed JSON AST codec are implemented in `pkgs/smithy-syntax` and checked
against the Java reference's loader corpus. `pkgs/smithy` assembles IDL and JSON
files into a semantic model with the prelude, reference resolution, mixins,
trait applications and metadata merging. It includes the `smithy.contracts#conditions`
schema and validates its targets, names and required fields. `pkgs/jmespath`
provides a standalone JMESPath parser and evaluator. Smithy checks contract
expression syntax, member references, function arguments and boolean result
types during assembly. The CLI assembles, validates, formats and
converts IDL and JSON models. See [CLI usage](apps/smithy/README.md).

## Packages

| Path | Module | Purpose |
|------|--------|---------|
| `pkgs/jmespath` | `moonrockz/jmespath` | JMESPath parser, inspectable AST and JSON evaluator |
| `pkgs/smithy` | `moonrockz/smithy` | Semantic model and multi-file IDL/JSON loader |
| `pkgs/smithy-syntax` | `moonrockz/smithy-syntax` | Smithy IDL scanner, AST, CST, parser and diagnostics |
| `docs/cookbook` | `moonrockz/smithy_cookbook` | Tested cookbook articles for the syntax module |
| `tests` | `moonrockz/smithy_tests` | Compatibility kit (vendored reference corpus) and moonspec acceptance features; not published |
| `apps/smithy` | `moonrockz/smithy-cli` | Command-line application |

The workspace members are listed in `moon.work`.

## Install

Install the `smithy` command with [mise](https://mise.jdx.dev/):

```shell
mise use -g github:moonrockz/smithy
smithy version
```

Use the library in a MoonBit project:

```shell
moon add moonrockz/smithy-syntax
```

Each [GitHub release](https://github.com/moonrockz/smithy/releases) has 8 assets. The names have no version, so
`releases/latest/download/<name>` is a stable URL.

| Asset | Content |
|-------|---------|
| `smithy-linux-x64.tar.gz` | `smithy` for Linux x86-64 (static musl) |
| `smithy-linux-arm64.tar.gz` | `smithy` for Linux arm64 (static musl) |
| `smithy-darwin-arm64.tar.gz` | `smithy` for macOS on Apple silicon |
| `smithy-darwin-x64.tar.gz` | `smithy` for macOS on Intel |
| `smithy-windows-x64.zip` | `smithy.exe` for Windows x86-64 (built on Windows) |
| `smithy.wasm` | The CLI for the MoonBit `wasm` target |
| `smithy-gc.wasm` | The CLI for the MoonBit `wasm-gc` target |
| `checksums.txt` | SHA-256 of the other 7 assets |

Run the CLI module from mooncakes.io without installing a native binary:

```shell
moonx moonrockz/smithy-cli@latest --help
```

The binary is at the root of each archive. Check a download with `sha256sum -c checksums.txt`.

The two wasm files are not WASI programs. They import MoonBit host functions from the module
`__moonbit_fs_unstable` (`args_get`, `begin_read_string` and others). A runtime must provide these functions
to run the file.

- `smithy.wasm` also imports `wasi_snapshot_preview1.fd_write` and `fd_read`. It exports `memory` and `_start`.
- `smithy-gc.wasm` needs a runtime with WebAssembly GC. It also imports `spectest.print_char`, a test host
  function, and exports `_start`.

`wasmtime` cannot run them alone. We ran both files with wasmtime. Each stops at instantiation with
`unknown import: __moonbit_fs_unstable::args_get has not been defined` (`smithy.wasm`) and
`unknown import: __moonbit_fs_unstable::begin_read_string_array has not been defined` (`smithy-gc.wasm`).
A host that supplies `__moonbit_fs_unstable` is needed. We did not run the files in such a host.

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
mise run test:cli              # built CLI behavior on native, wasm, js and wasm-gc
mise run test:bdd              # moonspec acceptance features (tests/bdd, js target)
mise run tck:vendor:json -- REF # refresh the vendored JSON AST reference corpus
mise run prelude:vendor -- REF # refresh the embedded prelude and contract traits
mise run jmespath:vendor -- REF # refresh the embedded JMESPath compliance suite
mise run build                 # all targets
mise run build:native          # native release build
mise run clean
mise run build:release         # 4 native binaries (zig), 2 wasm files, dist/ (needs the Windows exe: mise run build:windows)
mise run test:native-zig       # native tests with zig as the C compiler
mise run release:status        # main, tags, GitHub release and mooncakes.io agree
mise run hooks:install         # git hooks (lefthook)
```

Without mise: `moonx scripts/<name>.mbtx [args]`.

The cookbook in `docs/cookbook` is a workspace member; `moon test` runs its articles.

Cross-builds and native tests with Zig use the published `moonrockz/zig-cross` tool from
[moonrockz/moonx-tools](https://github.com/moonrockz/moonx-tools/tree/main/apps/zig-cross).
The exact package version is pinned once in `scripts/zig-cross.mbtx` and is independent of Smithy's version.
The mise tasks run that launcher with `moonx`; a separate clone of the tool is unnecessary.
To cross-build selected targets, run `mise run build:cross -- linux-x64 darwin-arm64 -- apps/smithy`.
Windows release binaries are built natively on Windows because MoonBit resolves OS-specific code from the host.

## Layout

```
smithy/
├── .config/mise/config.toml   # tools and tasks
├── .github/workflows/ci.yml   # lint, build and test on every target
├── .github/workflows/release.yml # plan, validate, build, smoke, publish, release
├── .claude/skills/release-manager/ # release skill and troubleshooting
├── lefthook.yml               # git hooks
├── apps/smithy/               # CLI (moonrockz/smithy-cli)
├── pkgs/smithy/               # library (moonrockz/smithy)
├── pkgs/jmespath/             # JMESPath parser and evaluator (moonrockz/jmespath)
├── pkgs/smithy-syntax/        # IDL syntax (moonrockz/smithy-syntax)
├── docs/cookbook/             # tested cookbook articles (moonrockz/smithy_cookbook)
├── tests/                     # compatibility kit and acceptance features (moonrockz/smithy_tests)
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
