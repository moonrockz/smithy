# Smithy build

Parses `smithy-build.json`, applies model projections and invokes registered
plugins. `BuildRunner::run` returns relative artifact paths and contents; the
CLI writes them to the configured output directory.

`run_result` also returns errors and keeps successful projection artifacts.
An invalid projected model writes build information, while plugins that require
a valid model are skipped. `run` raises when any projection fails.

Local and public URL sources and imports are loaded by the CLI. Maven dependencies are
reported as unsupported. The runner includes the `source` projection and the
model, sources and build-info plugins for each concrete projection.

`BuildConfig::parse` accepts an `environment` map for `${NAME}` substitutions
in string values and object keys. Undefined variables fail configuration
loading; `\${NAME}` keeps a literal placeholder. The CLI uses process variables
and sets `SMITHY_ROOT_DIR` to its current working directory.

Local JAR inputs load the IDL and JSON files listed in
`META-INF/smithy/manifest`. `archive_models` remains the compatible bytes-to-model
entry point. `declared_models(tree)` applies the same manifest rules to a
`moonrockz/artifact-resources` entry tree and returns logical resources with
physical origins. Generic ZIP, tar/gzip and filesystem access live in that independent
module. Stored and deflated entries are read without extracting files. Source artifacts retain their manifest paths under
the JAR filename without its extension.

Explicit resource objects are accepted in `sources`, global `imports` and
projection `imports`:

```json
{
  "version": "2.0",
  "sources": [{
    "path": "module.zip",
    "root": "models",
    "paths": [{"path": "service.smithy", "name": "public/service.smithy"}],
    "globs": ["shared/**/*.json"]
  }]
}
```

`path` is resolved relative to the configuration file. `root` is mandatory;
use `.` for the container root. Paths and globs are relative to it. The same
object works with a directory, ZIP/JAR, `.tar`, `.tar.gz` or npm `.tgz`, without a Smithy
manifest. Selected models must be `.smithy` or `.json`, and aliases must retain
the original format. Globs use case-sensitive `*`, `?` and whole-component `**`.
Every selector must match a file. Results sort lexically by logical name;
overlapping identical selections deduplicate and conflicting names fail.

Selected source artifacts use root-relative logical names or explicit aliases.
Imports contribute models without exporting source files. Projection imports
remain scoped to their projection. Diagnostics keep physical filenames,
including `archive.zip!/path/model.smithy`, independently of logical aliases.
Selecting one physical model under two aliases assembles it once and exports
both names. Source artifact collisions across input objects still fail.

String inputs retain directory/model discovery and JAR manifest behavior.
Ordinary ZIP and tar/gzip inputs require explicit selection. Nested ZIP and
tar/gzip archives are not opened by legacy directory discovery. Explicit selection does not execute included code
or recursively open archives. See the independent resource module for limits,
path rules and backend acquisition requirements.

For library callers, `BuildConfig.sources`, `BuildConfig.imports` and
`ProjectionConfig.imports` now contain `BuildInput` values. Use
`BuildInput::from_path(string)` for legacy discovery or
`Selected(RepositoryLocation, Selection)` for explicit resources. JSON string
configuration remains compatible. `selected_models(tree, selection)` exposes
the Smithy format checks over the generic resource API.

Public archive objects replace `path` with `url` and retain the same explicit
selection in sources, global imports and projection imports:

```json
{"url":"https://example.org/models.zip","format":"zip","root":"models","paths":["service.smithy"]}
```

`format` defaults to `zip`; `jar`, `tar`, `tgz` and `tar.gz` are also accepted.
The optional `digest` is `sha256:` plus 64 hexadecimal digits. It verifies the
whole downloaded archive before loading. URLs are never resolved as local paths,
and `url` and `path` cannot be combined. String inputs remain local discovery;
use an object for public acquisition. Remote JARs use explicit selection too.
Model diagnostics retain the requested and resolved URLs, digest and physical
archive entry. Selected source artifacts keep their logical names.

Library configurations use `Remote(PublicArchive, Selection)`. Existing exhaustive
`BuildInput` matches need this new case. `with_location` now raises `BuildError`
when a replacement location is not a valid URL for a remote input. The build
library does not initiate I/O. Use `register_public_http` and a transport to
obtain a tree, then `selected_models` and the usual loader/runner methods.
See the [acquisition limits and host matrix](../artifact-resources/README.mbt.md#public-http-archives)
and [runnable example](../../examples/public-archive/README.md).

Call `add_projection_import` to supply inputs for a projection when using the
runner directly. A projection with imports loads its model again from the JSON
AST, which omits built-in definitions. `BuildRunner::new(config, loader=...)`
takes the function that creates the loader for that step; the default is
`@smithy.Loader::new`. Pass a loader that adds the same built-in sources as the
loader of the build model, for example `loader=() => @rpc.loader()`. The
`smithy` CLI builds with the `smithy.rpc` traits as built-in definitions, so the
build-info `traitDefinitions` of every CLI build lists them, as it lists the
prelude traits.

`add_source` marks files for source artifacts; its optional
`source_file` argument identifies the original model filename when the artifact
uses a relative name. Projected sources contain source shapes and metadata,
including newly created shapes, and omit imported definitions.

`apply_transform` applies a single built-in transform without running validation
or plugins.

Use `plugin::artifactName` to run a plugin with separate settings and an output
directory of its own. Artifact names must be unique within a projection,
including the default `model`, `sources` and `build-info` artifacts. Registered
plugins return relative filenames; absolute paths and parent traversal are
rejected.


## Projections

`BuildRunner::run` gives each artifact by its path. A projection model is a JSON AST that you can load again.

<!-- tour:start build-projection-api -->
```mbt check
///|
test {
  let model = @smithy.Loader::new()
  .add_idl(
    "forecast.smithy",
    (
      #|$version: "2"
      #|
      #|namespace example
      #|
      #|service Weather {
      #|    version: "2024-01-01"
      #|    operations: [GetForecast, GetDebugInfo]
      #|}
      #|
      #|@readonly
      #|operation GetForecast {}
      #|
      #|@internal
      #|@readonly
      #|operation GetDebugInfo {}
    ),
  )
  .assemble().model.unwrap()
  let config = @build.BuildConfig::parse(
    (
      #|{
      #|    "version": "1.0",
      #|    "projections": {
      #|        "public": {
      #|            "transforms": [
      #|                {"name": "excludeShapesByTrait", "args": {"traits": ["internal"]}}
      #|            ]
      #|        }
      #|    }
      #|}
    ),
  )
  let artifacts = @build.BuildRunner::new(config).run(model)
  let public = @smithy.Loader::new()
  .add_json("public.json", artifacts["public/model/model.json"])
  .assemble().model.unwrap()
  assert_eq(@smithy.Selector::parse("operation").select_ids(public), [
    "example#GetForecast",
  ])
}
```
<!-- tour:end build-projection-api -->

## Acquisition settings

`BuildConfig::parse` accepts top-level `cacheDirectory`, a portable filesystem
directory path defaulting to `.smithy/cache`, and `offline`, a boolean defaulting
to false. The CLI resolves cache paths relative to the configuration file and
shares the cache across sources, imports and projection imports. Library consumers
receive these settings in `cache_directory: CacheDirectory` and `offline` and supply acquisition
through `artifact-resources`; parsing configuration performs no I/O.
See [CLI cache behavior](../../apps/smithy/README.md) and the
[cache contract](../artifact-resources/README.mbt.md#verified-cache-and-offline-acquisition).

Code constructing `BuildConfig` directly must initialize the new
`cache_directory` and `offline` fields. `BuildConfig::parse` supplies their defaults.

`cacheDirectory` rejects invalid filesystem syntax such as `cache:*` and reserved
Windows device components such as `NUL`, including when parsed on another host.


## GitHub release inputs

A selected input can use `github` instead of `path` or `url` in sources, global
imports and projection imports:

```json
{
  "github": {
    "repository": "owner/models",
    "tag": "v1.2.3",
    "asset": "models.tar.gz"
  },
  "format": "tgz",
  "root": "package/models",
  "globs": ["**/*.smithy"]
}
```

An exact tag and exact asset name are required. `format` defaults to `zip` and
accepts `zip`, `jar`, `tar`, `tgz` or `tar.gz`; add `digest` with an expected
`sha256:` value to pin the bytes. An optional `github.api` selects a compatible
public API base, defaulting to `https://api.github.com`. Source fields are
exclusive and unknown fields fail validation. Resource roots, path/glob
selection and logical name validation are unchanged.

The library case is `GitHub(GitHubArchive, Selection, HttpUrl)`, where the URL is
the API base. Exhaustive `BuildInput` matches must handle it. `location()` returns
the repository coordinate; `with_location()` validates and replaces that
coordinate. `to_json()` preserves all reference, API, format, digest and selection
settings. The CLI handles acquisition before calling the common model selector.
The same cache/offline settings apply to metadata and archive bytes.
See the [provider contract](../artifact-resources/README.mbt.md#pinned-github-release-assets)
and [runnable example](../../examples/github-release/README.md).


## Public npm and Maven inputs

Sources, global imports and projection imports accept exact npm package inputs:

```json
{
  "npm": { "package": "@scope/models", "version": "1.2.3" },
  "root": "package/models",
  "globs": ["**/*.smithy"]
}
```

`npm.registry` defaults to `https://registry.npmjs.org`; an explicit public base
URL can replace it. Selection is required and the archive format is always tgz.
Scoped/unscoped names, strict exact SemVer, registry integrity checks and optional
top-level SHA-256 `digest` are supported. npm is never installed or invoked.

An exact Maven JAR defaults to Smithy manifest discovery:

```json
{
  "maven": {
    "repository": "https://repo.maven.apache.org/maven2",
    "group": "software.amazon.smithy",
    "artifact": "smithy-aws-traits",
    "version": "1.72.0",
    "checksum": "sha1"
  }
}
```

`repository` defaults to Maven Central. Optional `classifier` selects a classified
JAR; `checksum` selects `sha1` or `sha256` sidecars and defaults to `sha1`. A
top-level `digest` supplies the expected SHA-256 and takes precedence over sidecars.
Add `root` and `paths`/`globs` for explicit selection instead of manifest discovery.
The same acquired tree and model-selection path serve every build position.

Only one of `path`, `url`, `github`, `npm` or `maven` may select an input. Unknown
coordinate fields, input-level credentials, explicit format overrides, dependency ranges,
mutable snapshots and transitive resolution settings are rejected. The legacy
root-level `maven.dependencies` configuration remains unsupported; these selected
inputs acquire direct artifacts and do not resolve a dependency graph.

Library callers construct `BuildInput::Npm(NpmArchive, Selection)` or
`BuildInput::Maven(MavenArchive, Selection?)`. `None` selects manifest discovery
for Maven. Exhaustive matches must handle both variants. `location()` returns the
registry/repository base; `with_location()` validates a replacement base and
`to_json()` preserves coordinates, checksum policy, digest and selection.

See the [provider contracts](../artifact-resources/README.mbt.md#public-npm-packages),
[npm example](../../examples/npm-registry/README.md) and
[Maven example](../../examples/maven-repository/README.md). All remote inputs share
`cacheDirectory`, `offline` and the CLI cache flags.

## Credential bindings

Root-level `credentials` is an array of `CredentialBinding` values. Each binding
has an exact `HttpOrigin` and a `CredentialSource`: `BearerEnvironment` or
`BasicEnvironment`, using validated `CredentialVariable` names. JSON uses
`origin` plus `bearerTokenEnv`, or `origin` plus `usernameEnv` and `passwordEnv`.
Literal secrets, mixed methods, duplicate origins and insecure remote HTTP
origins are rejected. Credentials are parsed before general environment expansion;
this section never expands `${NAME}` placeholders.

`BuildConfig::resolve_credentials(environment)` resolves supplied values into the
resource library's redacted `Credentials`. The configuration itself retains only
references. The CLI resolves them once per build and passes them through every
provider in sources and both import scopes. The library does not read ambient
environment variables or initiate I/O. Missing/empty values and malformed
credentials report generic errors without echoing secrets. See the
[CLI setup](../../apps/smithy/README.md#repository-credentials) and
[cache/redirect policy](../artifact-resources/README.mbt.md#supplied-repository-credentials).
