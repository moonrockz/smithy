# Smithy build

Parses `smithy-build.json`, applies model projections and invokes registered
plugins. `BuildRunner::run` returns relative artifact paths and contents; the
CLI writes them to the configured output directory.

`run_result` also returns errors and keeps successful projection artifacts.
An invalid projected model writes build information, while plugins that require
a valid model are skipped. `run` raises when any projection fails.

Local sources and imports are loaded by the CLI. Maven dependencies are
reported as unsupported. The runner includes the `source` projection and the
model, sources and build-info plugins for each concrete projection.

`BuildConfig::parse` accepts an `environment` map for `${NAME}` substitutions
in string values and object keys. Undefined variables fail configuration
loading; `\${NAME}` keeps a literal placeholder. The CLI uses process variables
and sets `SMITHY_ROOT_DIR` to its current working directory.

Local JAR inputs load the IDL and JSON files listed in
`META-INF/smithy/manifest`. `archive_models` decodes stored and deflated entries
without extracting files. Source artifacts retain their manifest paths under
the JAR filename without its extension.

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
