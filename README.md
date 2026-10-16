# smithy

A [Smithy](https://smithy.io/) implementation for the MoonBit ecosystem, organized as a monorepo.

## Status

The Smithy IDL 2.0 syntax layer (scanner, AST, CST, parser with recovery, diagnostics) is implemented in `pkgs/smithy-syntax` and checked against the Java reference's loader corpus. The semantic model, loader, JSON AST and CLI commands are the next sub-projects.

## Packages

| Path | Module | Purpose |
|------|--------|---------|
| `pkgs/smithy` | `moonrockz/smithy` | Smithy model library |
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
| `smithy-windows-x64.zip` | `smithy.exe` for Windows x86-64 |
| `smithy.wasm` | The CLI for the MoonBit `wasm` target |
| `smithy-gc.wasm` | The CLI for the MoonBit `wasm-gc` target |
| `checksums.txt` | SHA-256 of the other 7 assets |

The binary is at the root of each archive. Check a download with `sha256sum -c checksums.txt`.

The two wasm files are not WASI programs. They import MoonBit host functions from the module
`__moonbit_fs_unstable` (`args_get`, `begin_read_string` and others). A runtime must provide these functions
to run the file.

- `smithy.wasm` also imports `wasi_snapshot_preview1.fd_write`. It exports `memory` and `_start`.
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
mise run test:bdd              # moonspec acceptance features (tests/bdd, js target)
mise run build                 # all targets
mise run build:native          # native release build
mise run clean
mise run build:release         # 5 native binaries (zig), 2 wasm files, dist/
mise run test:native-zig       # native tests with zig as the C compiler
mise run release:status        # main, tags, GitHub release and mooncakes.io agree
mise run hooks:install         # git hooks (lefthook)
```

Without mise: `moonx scripts/<name>.mbtx [args]`.

The cookbook in `docs/cookbook` is a workspace member; `moon test` runs its articles.

## Layout

```
smithy/
├── .config/mise/config.toml   # tools and tasks
├── .github/workflows/ci.yml   # lint, build and test on every target
├── .github/workflows/release.yml # plan, validate, build, smoke, publish, release
├── .claude/skills/release-manager/ # release skill and troubleshooting
├── apps/zig-cross/            # zig cross-build tool (moonrockz/zig-cross)
├── lefthook.yml               # git hooks
├── apps/smithy/               # CLI (moonrockz/smithy-cli)
├── pkgs/smithy/               # library (moonrockz/smithy)
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
