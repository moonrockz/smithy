# smithy CLI

Assemble, validate, select, format, convert and build Smithy models.

## Run

Run the CLI module from mooncakes.io:

```shell
moonx moonrockz/smithy-cli@latest --help
moonx moonrockz/smithy-cli@latest version
```

Moonx runs the linear-memory `wasm` backend. The module declares that preferred
backend, and the release workflow runs the published module with moonx after
publishing its dependencies.

For a native release binary, install with mise:

```shell
mise use -g github:moonrockz/smithy
smithy version
```

From a checkout, prefix the examples below with
`moon run apps/smithy --target wasm --` in place of `smithy`, or build natively:

```shell
moon build apps/smithy --target native --release
_build/native/release/build/moonrockz/smithy-cli/smithy-cli.exe version
```

## Commands

Use `smithy --help` for the command list, and `smithy convert --help` or
`smithy help convert` for a command's options. Every command accepts `-h` and
`--help`. Options accept both `--to json` and `--to=json`; output also accepts
`-o model.json` and `-omodel.json`.

```shell
smithy ast model.smithy extra.json
smithy validate model.smithy extra.json
smithy build --config smithy-build.json
smithy clean --config smithy-build.json
smithy select --selector 'structure > member > string' model.smithy
smithy convert --to json model.smithy -o model.json
smithy convert --to idl model.json -o model.smithy
smithy convert --to idl one.json two.json --output-dir generated
smithy format model.smithy
smithy format --check model.smithy model.json
smithy format --write model.smithy model.json
```

`ast` and `convert --to json` assemble all inputs into a Smithy JSON AST and
omit built-in prelude and contract definitions. `validate` assembles the same model and prints
any diagnostics. Reference resolution, mixin expansion, trait application and
metadata merging follow the model library's rules.

`build` reads the configured local sources and imports, runs each concrete
projection, and writes model, sources and build-info artifacts under its output
directory. A `jsonSchema` plugin setting writes `schema.json` for each
projection. `clean` removes that configured output directory.

Build sources and imports also accept local JAR files with a
`META-INF/smithy/manifest`. Configuration strings and keys expand `${NAME}`
from environment variables; `\${NAME}` escapes a placeholder.
Directories, individual model files and JARs use the independent
[artifact resource library](../../pkgs/artifact-resources/README.mbt.md).
The same inputs work in `sources`, global `imports` and projection `imports`.
JARs load only manifest entries; repeated manifest lines are ignored and
unlisted models stay excluded. Nested JAR source artifacts retain paths such
as `nested/models.jar/models/a.smithy`. Loading errors include the physical
origin and resource diagnostic code; unsafe paths, duplicate ZIP entries,
corrupt content and resource limit failures stop the build.

For a working directory example with both import scopes, run from the root:

```shell
mise exec -- moon run apps/smithy --target js -- build --config examples/local-resources/smithy-build.json
```

The output is under `.dev/out/local-resources`. For the vendored real-JAR
example, set `sources` to `tests/tck/build/plugins/sources/jar-import.jar`
in a root-level build configuration. Local builds require no network.
The default resource limits are 64 MiB per archive, 10,000 entries,
16 MiB per entry and 256 MiB total expanded ZIP bytes. The library API
allows callers to configure these limits. Node.js, native hosts and MoonBit
Wasm filesystem hosts support local acquisition. Credentials and remote
repository acquisition are not part of local loading.

`${SMITHY_ROOT_DIR}` always expands to the CLI's working directory.

Use a dedicated output directory. Builds replace their previous artifacts,
including artifacts from projections that become abstract. An ownership file
ties the output to its configuration; an existing nonempty directory must
have that configuration's ownership marker. All files in an owned output
directory are replaced. Keep the output directory separate from source and
import directories; neither may contain the other.

The `smithy.contracts#conditions` trait is included. Validation checks its
targets, condition names and required string fields, then analyzes JMESPath
syntax, modeled member references, function arguments and boolean result types.
Diagnostics identify the condition and its expression-relative location.
Conversion preserves expressions and
documentation without evaluating contracts.

IDL output uses Smithy 2, absolute references and flattened inherited contents.
It preserves model semantics and exact numbers. Comments, import choices,
source layout, resource bindings and inline-operation syntax are not retained
by conversion. An IDL file has one namespace, so a model with multiple
namespaces requires `--output-dir`. The output names are `<namespace>.smithy`.
Metadata is emitted exactly once, in the first namespace. Empty models and
metadata-only models use `model.smithy`.

`format` checks syntax and normalizes indentation and spacing. IDL formatting
retains comments, existing line breaks, commas, literal spellings and the
contents of text blocks. JSON formatting uses the typed JSON AST codec. By
default, formatting prints one file to stdout. `--write` formats files in place;
all inputs must parse before any file changes. `--check` writes nothing and
returns status 1 when any file differs.

Input formats follow `.smithy` and `.json` extensions. Override with
`--from idl` or `--from json`. Use `-` once for stdin, with an explicit format:

```shell
cat model.smithy | smithy convert --from idl --to json -
```

Output goes to stdout unless `-o FILE` or `--output-dir DIR` is supplied. Existing
output files are replaced. Use `--` before input paths beginning with `-`.

Exit statuses are 0 for success, 1 for invalid models, I/O failures or formatting
differences, and 2 for command-line usage errors. Native, Wasm and Node.js
builds write diagnostics to stderr. Node.js builds use the Node 24 toolchain pinned by mise.
The `wasm-gc` artifact uses the host's `spectest.print_char` for both output
streams and reads stdin through `/dev/stdin`; use the Wasm or native build for
portable command-line pipelines.

Run `mise run test:cli` to check the built CLI on every backend, or pass target
names to select backends. The root [README](../../README.md) lists release assets.

### Explicit directory and ZIP resources

Build `sources`, `imports` and projection `imports` accept resource selection
objects as well as legacy strings. For example:

```json
{"path":"module.zip","root":"models","paths":["service.smithy"],"globs":["shared/**/*.json"]}
```

The path is relative to the build configuration. Use `root: "."` for the whole
container. Selectors are root-relative and must each match a file. Logical
names default to those relative paths; `{"path":"a.smithy","name":"public/a.smithy"}`
assigns an alias. Conflicting logical names fail. Plain ZIPs require an explicit
selection; legacy JAR strings retain Smithy manifest discovery.
See [build configuration](../../pkgs/smithy-build/README.mbt.md) for the full contract.
