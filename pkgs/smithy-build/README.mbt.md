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
runner directly. `add_source` marks files for source artifacts; its optional
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
