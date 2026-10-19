# Smithy build

Parses `smithy-build.json`, applies model projections and invokes registered
plugins. `BuildRunner::run` returns relative artifact paths and contents; the
CLI writes them to the configured output directory.

Local sources and imports are loaded by the CLI. Maven dependencies are
reported as unsupported. The runner includes the `source` projection and the
model, sources and build-info plugins for each concrete projection.
