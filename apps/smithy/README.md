# smithy CLI

Assemble, validate, select, diff, format, convert and build Smithy models.

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
smithy diff --old previous/ --new current/
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

`diff` assembles two local model snapshots independently and reports one
unsuppressed compatibility event per line. Inputs can be IDL files, JSON AST
files, directories or JARs with Smithy manifests. ERROR or DANGER differences and
invalid models exit with status 1. Compatible or unchanged models exit with status
0. `--output changes.txt` writes the events to a file. Message newlines are escaped
as `\n`. See the [model diff library](../../pkgs/smithy-diff/README.mbt.md) for the
comparison API, suppressions and preview-feature behavior. This command compares
explicit old/new snapshots; Git and project modes are not implemented.

### JSONL diff output

Use `--format jsonl` for automation. `--format=jsonl` also works. Text remains
the default, and `--format text` selects it explicitly. There is no separate
streaming flag.

```shell
smithy diff --old previous/ --new current/ --format jsonl
smithy diff --old previous/ --new current/ --format=jsonl --output changes.jsonl
```

Each unsuppressed event is one compact, newline-terminated UTF-8 JSON object,
in the same deterministic order as text output. The output has no array wrapper,
header, summary, progress text or blank records. For example:

```json
{"id":"ChangedMemberTarget","severity":"ERROR","shape":"example#Value$name","message":"The event message","source":{"file":"current/model.smithy","path":"","span":{"start":42,"length":12}}}
```

| Field | Value |
|-------|-------|
| `id` | Event identifier string |
| `severity` | `NOTE`, `WARNING`, `DANGER` or `ERROR` |
| `shape` | Absolute shape ID string, or `null` for a model-level event |
| `message` | Complete message string; JSON decoding restores newlines and other escaped characters |
| `source` | `null`, or an object containing `file`, `path` and `span` |
| `source.file` | Physical source identifier, including archive entry paths when present |
| `source.path` | JSON Pointer for JSON AST input, otherwise usually an empty string |
| `source.span` | `null`, or nonnegative integer `start` and `length` in zero-based UTF-16 code units |

Source locations retain the comparison engine's precision, usually a shape's
location. They do not promise exact trait locations or line/column coordinates.
Consumers should tolerate additional object fields.

Both models are assembled and compared before output begins. The CLI then
serializes one event at a time and flushes each complete stdout record through
its application buffers. It honors sink backpressure without collecting the
serialized output. Assembly and comparison still keep their models and results
in memory. A downstream tool may have its own buffers.

`--output FILE` uses the same records with ordinary file buffering, finishes
the write and close before returning, and leaves stdout empty. Wasm and Wasm GC
hosts must supply WASI `fd_write`, `path_open` and `fd_close`, including a working
directory preopen at descriptor 3. The pinned `moonrun` host provides these;
its WASI file paths must remain within that directory, including symlink targets.
Native and Node.js output paths use the host filesystem directly.

An unchanged comparison produces no records and creates an empty file when
`--output` is used. Invalid models produce no diff records and preserve an
existing output file. Diagnostics stay on stderr. Write, flush and close errors,
including a closed downstream pipe, stop delivery and return 1. A failed output
may contain only a prefix, including an incomplete final record; output is not
atomic and does not request filesystem durability for every record.

Exit statuses are the same in text and JSONL:

- `0`: compatible or unchanged models, with no processing error.
- `1`: an ERROR/DANGER difference, invalid models, or a processing/output failure.
- `2`: invalid command usage, including an unknown or missing format value.

A breaking diff writes all its events before returning 1 unless output fails.
Use stderr to distinguish processing failures from compatibility findings.
In Bash, enable `pipefail` so a successful `jq` does not hide Smithy's status:

```bash
set -o pipefail
smithy diff --old previous/ --new current/ --format jsonl |
  jq --unbuffered -c 'select(.severity == "ERROR" or .severity == "DANGER")'
```

With a successful `jq`, this pipeline returns Smithy's status. `--unbuffered`
asks `jq` to flush each result too.

`build` reads the configured local sources and imports, runs each concrete
projection, and writes model, sources and build-info artifacts under its output
directory. A `jsonSchema` plugin setting writes `schema.json` for each
projection. The `openapi` plugin writes `<ServiceName>.openapi.json` in OpenAPI
3.0.2 or 3.1.0; its `service` setting is required. See the
[OpenAPI library and plugin guide](../../pkgs/smithy-openapi/README.mbt.md) for
protocol selection, configuration and conversion boundaries. `clean` removes
that configured output directory.

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
On Wasm GC, diff diagnostics and top-level errors use WASI stderr. Other
commands' legacy print-based diagnostics may still share stdout through
`spectest.print_char`. JSONL diff records use WASI stdout and stay separate
from diagnostics. Wasm GC reads stdin through `/dev/stdin`; use the Wasm or
native build for portable stdin pipelines.

Run `mise run test:cli` to check the built CLI on every backend, or pass target
names to select backends. The root [README](../../README.md) lists release assets.

### Explicit directory, ZIP and tar/gzip resources

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

Local `.tar`, `.tar.gz` and npm `.tgz` inputs use the same selection objects in
`sources`, `imports` and projection `imports`:

```json
{"path":"downloaded-package.tgz","root":"package/models","globs":["**/*.smithy","**/*.json"]}
```

Each archive requires explicit selection. Physical source paths retain the npm
wrapper, for example `downloaded-package.tgz!/package/models/service.smithy`.
Run the checked-in [npm archive example](../../examples/npm-archive/README.md):

```shell
mise exec -- moon run apps/smithy --target js -- build --config examples/npm-archive/smithy-build.json
```

The readers accept V7, POSIX ustar and per-file pax tar with regular files and
directories. Links, special entries, GNU extensions and global pax headers fail.
Gzip checks header and payload integrity and bounds expanded output, including
headers and padding, to 256 MiB by default. Tar validates header checksums and
bounds payload sizes. See the [complete support policy](../../pkgs/artifact-resources/README.mbt.md#tar-and-gzip-support).
No registry access, installation, extraction or package-hook execution occurs.

### Public archive URLs

Use a `url` selection object in `sources`, global `imports` or projection
`imports` to download public ZIP/JAR, tar or tar/gzip archives:

```json
{"url":"https://example.org/models.zip","format":"zip","root":"models","globs":["**/*.smithy"]}
```

`format` defaults to `zip`; `jar`, `tar`, `tgz` and `tar.gz` are supported.
Add `"digest":"sha256:<64 hexadecimal digits>"` to verify expected content
before archive parsing or model loading. The actual digest is always computed
and retained with requested URL, resolved URL and physical entry provenance.
Source filenames exported by the sources plugin remain root-relative.

Native and Node.js 24+ builds require curl 7.61+ with HTTPS support. Linux
and macOS use the trusted host PATH; Windows uses the OS-installed
`System32/curl.exe` by absolute path, excluding checkout-local executables. TLS certificates are verified with the host trust store.
At most five redirects are followed; HTTPS cannot downgrade to HTTP.
Acquisition defaults to 64 MiB and a 30-second total transfer timeout.
Existing archive expansion and resource limits still apply. Missing assets,
authentication-required responses, transport errors and digest mismatches fail
with distinct stable resource codes. Supplied credentials are configured below.

Remote inputs share a verified cache across sources, global imports and projection
imports. By default it lives at `.smithy/cache` relative to the configuration file.
Set top-level `"cacheDirectory":"/path/to/cache"` or pass `--cache-dir PATH` to
choose another location. CLI paths are also relative to the configuration file;
the CLI setting overrides the JSON setting. Cache paths must use portable filesystem
syntax; reserved characters such as `*`, reserved device names such as `NUL`,
and trailing dots/spaces are rejected before acquisition. Build output and cache directories
must not overlap. `clean` removes build output and retains the cache.

Use `smithy build --offline --config smithy-build.json`, or top-level
`"offline":true`, to prohibit network calls. Either setting enables offline mode.
An online build downloads each exact URL once, then reuses verified content.
Every hit checks SHA-256 and the input's expected digest before archive parsing.
The cache records the original requested and resolved URLs, preserving source
provenance and identical generated artifacts during offline builds.

Missing offline references fail with `offline-miss`; damaged metadata, missing
content and corrupted bytes fail with `cache-corrupt`. Expected digest mismatches
fail with `integrity-failure`. Corruption fails without a network fallback in
both modes. Remove damaged entries or the cache directory and build online to
recover. URLs are treated as pinned references with no expiry; remove the reference
mapping or choose a fresh cache to refresh a mutable URL. Cache data has no
automatic eviction. Local-only builds do not read or create cache files.

Wasm and Wasm GC CLI builds reject URL acquisition with `unsupported-transport`.
Local inputs continue to work without curl or network access on all existing
filesystem hosts. See the [full library contract](../../pkgs/artifact-resources/README.mbt.md#public-http-archives).

Run the pinned [public archive example](../../examples/public-archive/README.md):

```shell
mise exec -- moon run apps/smithy --target js -- build --config examples/public-archive/smithy-build.json
```


## Public GitHub release assets

Use a selected GitHub input anywhere a build accepts sources or imports:

```json
{
  "version": "2.0",
  "sources": [{
    "github": {
      "repository": "owner/models",
      "tag": "v1.2.3",
      "asset": "models.zip"
    },
    "format": "zip",
    "root": "models",
    "globs": ["**/*.smithy"]
  }]
}
```

Replace the coordinate, tag, asset and resource selection with your public
release. Asset names match exactly. `github` cannot be combined with `path` or
`url`. ZIP/JAR, tar and tar/gzip use the same selectors; set `format` to `tgz` for
`.tar.gz`/`.tgz`. An optional `digest` pins SHA-256. `github.api` defaults to
`https://api.github.com`; a compatible public API base can be set explicitly.
Latest-release selection and inferred matches are unsupported. Supplied tokens use the credential bindings below.

The initial build caches release metadata, asset pages and verified content.
Run `smithy build --config smithy-build.json --offline` afterward to resolve the
same reference without network access. `--cache-dir` and JSON `cacheDirectory`
control the shared cache. Provenance reports the requested tag/name, resolved
release/asset IDs, download redirects and content digest. Failures use stable
codes such as `missing-release`, `missing-asset`, `ambiguous-asset`, `rate-limited`,
`authentication-required` and `integrity-failure`.

Native Linux/macOS/Windows and Node.js hosts use curl; Wasm and Wasm GC support
portable readers but require a custom library transport for acquisition. Local
builds remain usable offline. See the [provider contract](../../pkgs/artifact-resources/README.mbt.md#pinned-github-release-assets)
and [runnable release-resource example](../../examples/github-release/README.md).


## Public npm and Maven repositories

Build inputs can resolve exact public npm versions and Maven JARs. They work in
`sources`, global `imports` and projection `imports` alongside local, URL and
GitHub inputs:

```json
{
  "version": "2.0",
  "sources": [{
    "npm": { "package": "@scope/models", "version": "1.2.3" },
    "root": "package/models",
    "globs": ["**/*.smithy"]
  }],
  "imports": [{
    "maven": {
      "group": "org.example",
      "artifact": "model-traits",
      "version": "1.2.3"
    }
  }]
}
```

Replace these example coordinates with your artifacts. npm defaults to
`https://registry.npmjs.org`, overridden by `npm.registry`. Maven defaults to
`https://repo.maven.apache.org/maven2`, overridden by `maven.repository`.
npm requires explicit resource selection from its tgz. Maven uses
`META-INF/smithy/manifest` unless explicit `root` and `paths`/`globs` are supplied.
An optional `maven.classifier` selects a classified JAR.

A top-level input `digest` pins SHA-256. npm also verifies registry SRI metadata
or legacy shasum. Maven uses caller SHA-256 when supplied, otherwise the selected
`.sha1` sidecar by default or `.sha256` with `maven.checksum` set to `sha256`.
Missing or invalid integrity data fails explicitly. See the
[full integrity policy](../../pkgs/artifact-resources/README.mbt.md#public-npm-packages).

Use `--offline` after the first successful online build. Registry metadata,
repository sidecars and verified content use the same cache; every hit rechecks
integrity. `--cache-dir` or `cacheDirectory` selects a cache location. Local
builds continue to work without network access. npm dist-tags/ranges,
Maven snapshots, POM/transitive resolution and package lifecycle hooks are outside
this public acquisition slice. Root-level `maven.dependencies` remains rejected.

Runnable public examples:

```shell
mise exec -- moon run apps/smithy --target js -- build --config examples/npm-registry/smithy-build.json
mise exec -- moon run apps/smithy --target js -- build --config examples/maven-repository/smithy-build.json
```

Repeat either command with `--offline`. Native Linux/macOS/Windows and Node.js
hosts use curl. Wasm and Wasm GC retain portable archive/provider behavior with a
custom library transport/cache store. Normal tests use controlled HTTP fixtures,
not live registry availability.

## Repository credentials

Declare exact origin bindings at the root of `smithy-build.json`. Bindings contain
only environment variable names, never literal secret values:

```json
{
  "version": "2.0",
  "credentials": [
    { "origin": "https://api.github.com", "bearerTokenEnv": "GITHUB_TOKEN" },
    { "origin": "https://registry.npmjs.org", "bearerTokenEnv": "NPM_TOKEN" },
    { "origin": "https://maven.example.com", "usernameEnv": "MAVEN_USER", "passwordEnv": "MAVEN_PASSWORD" }
  ]
}
```

Combine these bindings with the existing `github`, `npm`, `maven` or URL inputs.
They apply consistently to sources, global imports and projection imports.
Configure only the origins you use. Each origin can have one Bearer or Basic
binding. Origins and environment variable names in this section are literal;
`${NAME}` expansion does not apply inside `credentials`. Values are resolved at
build invocation, and a configured missing, empty or malformed secret fails with
a redacted configuration error. `clean` does not resolve secrets.

A binding covers the origin's scheme, host, port and every path. HTTPS is required
except for loopback fixtures. Credentials are never sent to another redirect
origin, even when it has a binding of its own. A separately hosted authenticated
npm tarball needs an explicit origin binding for its direct request. Authenticated
GitHub assets use its asset API with octet-stream negotiation; use a read token
with access to the selected repository.

The cache isolates origins and credential identities from anonymous entries and
other credentials. Online hits and offline runs require the same supplied values
and verify content again. Cache hits do not check token revocation with the server;
remove the cache to require fresh authorization. Treat cache files as private
artifact data and protect the cache directory. Authentication errors identify the
resource and HTTP 401/403 status without printing the authorization value.

See the [runnable credential example](../../examples/authenticated-repositories/README.md)
and [library policy](../../pkgs/artifact-resources/README.mbt.md#supplied-repository-credentials).
Interactive login, enterprise SSO, `.npmrc` and Maven settings discovery are outside
this milestone.
