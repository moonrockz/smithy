<p align="center">
  <a href="https://moonrockz.github.io/smithy/"><img src="docs/assets/smithy-badge.png" width="320"
    alt="smithy.mbt: the pink moonrockz bunny forges hot metal on an anvil on the moon"></a>
</p>

# smithy

A [Smithy](https://smithy.io/) implementation for the MoonBit ecosystem, organized as a monorepo.

The docs site is at <https://moonrockz.github.io/smithy/>. Its source is in [`site/`](site/README.md).
The playground at <https://moonrockz.github.io/smithy/playground/> validates models, converts them and checks JSON-RPC transcripts in your browser. It sends nothing to a server.

## Status

The Smithy IDL 2.0 syntax layer (scanner, AST, CST, parser with recovery, diagnostics)
and the typed JSON AST codec are implemented in `pkgs/smithy-syntax` and checked
against the Java reference's loader corpus. `pkgs/smithy` assembles IDL and JSON
files into a semantic model with the prelude, reference resolution, mixins,
trait applications and metadata merging. It includes the `smithy.contracts#conditions`
schema and validates its targets, names and required fields. `pkgs/jmespath`
provides a standalone JMESPath parser and evaluator. Smithy checks contract
expression syntax, member references, function arguments and boolean result
types during assembly. Smithy selectors can query the assembled model. The CLI assembles, validates, selects, formats,
converts and builds IDL and JSON models. It also compares model snapshots with
`smithy diff --old previous/ --new current/`. See [CLI usage](apps/smithy/README.md)
and the [model diff API](pkgs/smithy-diff/README.mbt.md).
The build plugins convert assembled models to JSON Schema and services to OpenAPI
3.0.2 or 3.1.0. See [OpenAPI usage](pkgs/smithy-openapi/README.mbt.md).
The `openrpc` plugin exports JSON-RPC 2.0 services as OpenRPC 1.3.2 with
draft-07 value schemas. See [OpenRPC usage](pkgs/smithy-openrpc/README.mbt.md).

`moonrockz/smithy-validation` checks application JSON directly against selected Smithy data shapes,
with exact numbers and structured findings. The CLI exposes it through `smithy validate value`.
See [value validation](pkgs/smithy-validation/README.mbt.md).
Its [RPC package](pkgs/smithy-validation/rpc/README.mbt.md) checks JSON-RPC 1.0 and 2.0 requests,
notifications and contextual responses against modeled service methods through `smithy validate rpc`.
Explicit JSON-RPC 2.0 batch checks preserve element paths and associate unordered replies by exact IDs.
`smithy validate rpc transcript` checks two-peer exchanges in JSON or Markdown transcripts and JSONL logs.

The `go-jsonrpc-codegen` plugin generates typed Go JSON-RPC peers for stdio,
HTTP and WebSocket. See the [Go generator API](pkgs/smithy-codegen-go/README.mbt.md)
and the [manual interoperability matrix](examples/payment-terminal/INTEROPERABILITY.md).

`moonrockz/smithy-ion-validation` validates immutable Ion values directly with a documented
native type profile. See [Ion validation](pkgs/smithy-ion-validation/README.mbt.md) and the
[standalone consumer](examples/ion-validation-consumer/main.mbtx).

`moonrockz/smithy-codec` checks, decodes and writes application JSON through serialization profiles
that the model declares: tagged unions in object and array layouts, tuples, dictionaries, compact
forms, host scalar adapters and versioned document bundles. `smithy validate value --profile` and
`smithy codec canonicalize` select a profile from the command line. Morphir IR v3 and v4 are the first
conformance target. See [JSON codecs](pkgs/smithy-codec/README.mbt.md) and
[Morphir codecs](examples/morphir-codecs/README.md).

The [protocol test suite API](pkgs/smithy/protocoltests/README.mbt.md) loads standard
HTTP request/response test cases and compares messages produced by supplied
protocol implementations. Validate case definitions with
`smithy validate --protocol-tests model.smithy`.

## Packages

| Path | Module | Purpose |
|------|--------|---------|
| `pkgs/artifact-resources` | `moonrockz/artifact-resources` | Portable entry trees, resource loading, public HTTP/GitHub/npm/Maven acquisition, verified cache, supplied credentials and provider registry |
| `pkgs/jmespath` | `moonrockz/jmespath` | JMESPath parser, inspectable AST and JSON evaluator |
| `pkgs/smithy` | `moonrockz/smithy` | Semantic model and multi-file IDL/JSON loader |
| `pkgs/smithy-validation` | `moonrockz/smithy-validation` | Validate application JSON values directly against Smithy data shapes |
| `pkgs/smithy-ion-validation` | `moonrockz/smithy-ion-validation` | Validate native Ion values directly against Smithy data shapes |
| `pkgs/smithy-codec` | `moonrockz/smithy-codec` | Check, decode and write application JSON through declared serialization profiles |
| `pkgs/smithy-diff` | `moonrockz/smithy-diff` | Compare models and report compatibility changes |
| `pkgs/smithy-build` | `moonrockz/smithy-build` | Build configuration, projections and plugins |
| `pkgs/smithy-codegen` | `moonrockz/smithy-codegen` | Language-neutral core for code generators: symbols, code writer, delegator and director |
| `pkgs/smithy-codegen-jsonrpc` | `moonrockz/smithy-codegen-jsonrpc` | Language-neutral JSON-RPC methods, peers and session contracts for code generators |
| `pkgs/smithy-codegen-moonbit` | `moonrockz/smithy-codegen-moonbit` | MoonBit JSON-RPC peers on moonbitlang/async (plugin `moonbit-jsonrpc-codegen`) |
| `pkgs/smithy-codegen-python` | `moonrockz/smithy-codegen-python` | Python JSON-RPC peers with Pydantic v2, asyncio and FastAPI (plugin `python-jsonrpc-codegen`) |
| `pkgs/smithy-codegen-go` | `moonrockz/smithy-codegen-go` | Generate typed Go JSON-RPC peers with a vendored runtime |
| `pkgs/smithy-jsonschema` | `moonrockz/smithy-jsonschema` | Convert assembled value shapes to JSON Schema |
| `pkgs/smithy-openapi` | `moonrockz/smithy-openapi` | Convert services to OpenAPI with REST JSON and RPC v2 JSON protocols |
| `pkgs/smithy-openrpc` | `moonrockz/smithy-openrpc` | Export JSON-RPC 2.0 services as OpenRPC 1.3.2 |
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

- Both wasm files import WASI `fd_write`, `path_open` and `fd_close` for record-oriented
  output, and export `memory` and `_start`. `smithy.wasm` also imports `fd_read` and `proc_exit`.
- `smithy-gc.wasm` needs a runtime with WebAssembly GC. It also imports
  `spectest.print_char`, a test host function.

`wasmtime` cannot run them alone. We ran both files with wasmtime. Each stops at instantiation with
`unknown import: __moonbit_fs_unstable::args_get has not been defined` (`smithy.wasm`) and
`unknown import: __moonbit_fs_unstable::begin_read_string_array has not been defined` (`smithy-gc.wasm`).
A host that supplies the MoonBit imports and WASI I/O is needed. The pinned
`moonrun` host runs both files in the CLI qualification suite, including JSONL
pipe delivery, diagnostics and file output. See [CLI usage](apps/smithy/README.md#jsonl-diff-output)
for the Wasm output directory boundary.

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

For spec-driven work with coding agents, see [OpenSpec setup and workflow](openspec/README.md).
The shared schema uses standalone HTML designs and links changes and task groups to Smithy's beads tracker.

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
mise run test:validation-consumer # isolated JSON/RPC consumers without Ion or WIT
mise run test:ion-consumer     # isolated native Ion consumer without WIT, all targets
mise run test:http             # controlled public archive transport and CLI fixtures
mise run test:bdd              # moonspec acceptance features (tests/bdd, js target)
mise run tck:vendor:json -- REF # refresh the vendored JSON AST reference corpus
mise run prelude:vendor -- REF # refresh the embedded prelude and contract traits
mise run jmespath:vendor -- REF # refresh the embedded JMESPath compliance suite
mise run build                 # all targets
mise run build:native          # native release build
mise run clean
mise run build:release         # 4 native binaries (zig), 2 wasm files, dist/ (needs the Windows exe: mise run build:windows)
mise run test:native-zig       # native tests with zig as the C compiler
mise run codegen:payment-terminal # regenerate the golden JSON-RPC peers (-- --check fails on drift)
mise run runtime:embed         # copy runtimes/ into the JSON-RPC generators (validate checks the copy)
mise run test:runtime:moonbit  # MoonBit JSON-RPC runtime, native
mise run test:runtime:python   # Python JSON-RPC runtime: ruff, pyright --strict, pytest (uv)
mise run test:generated:moonbit # check and test the generated MoonBit peers
mise run test:generated:python # ruff, pyright --strict and pytest on the generated Python peers
mise run test:payment-terminal # MoonBit POS to Python terminal over stdio, checked transcripts
mise run release:status        # main, tags, GitHub release and mooncakes.io agree
mise run smoke:fingerprint     # fingerprint of the smoke inputs (mise run smoke:inputs lists them)
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
├── .github/workflows/smoke.yml # smoke the release binaries, record evidence (CI and Release)
├── .claude/skills/release-manager/ # release skill and troubleshooting
├── lefthook.yml               # git hooks
├── apps/smithy/               # CLI (moonrockz/smithy-cli)
├── pkgs/smithy/               # library (moonrockz/smithy)
├── pkgs/smithy-validation/    # Direct application value validation and typed findings
├── pkgs/smithy-ion-validation/ # Optional native Ion validation adapter
├── pkgs/smithy-codec/         # Profile-aware JSON codecs, version dispatch and Morphir adapters
├── pkgs/smithy-build/         # build projections and plugins
├── pkgs/smithy-codegen/       # code generation core
├── pkgs/smithy-codegen-jsonrpc/ # JSON-RPC contracts and peer settings for generators
├── pkgs/smithy-codegen-moonbit/ # MoonBit JSON-RPC generator
├── pkgs/smithy-codegen-python/ # Python JSON-RPC generator
├── runtimes/                  # JSON-RPC runtimes that the generators copy (MoonBit, Python)
├── pkgs/smithy-diff/          # Model compatibility differences
├── pkgs/smithy-jsonschema/    # JSON Schema converter
├── pkgs/smithy-openapi/       # OpenAPI service converter and protocols
├── pkgs/smithy-openrpc/       # OpenRPC service converter
├── pkgs/artifact-resources/   # reusable local artifact/resource library
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
