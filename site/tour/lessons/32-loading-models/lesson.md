# Loading models from npm, Maven and GitHub

> **Our extension:** In Smithy, the `sources` and `imports` of [smithy-build.json](https://smithy.io/2.0/guides/smithy-build-json.html#using-smithy-build-json) are paths. The npm, Maven and GitHub inputs are part of this project, in [moonrockz/smithy-build](../../../../pkgs/smithy-build/README.mbt.md).

In `smithy-build.json` (see [Converting models](../24-converting-models/lesson.md)), a source can be an object in place of a path. The object names an exact npm package version, a Maven JAR or a GitHub release asset. Its `root` and `globs` select the model files in the package. A Maven JAR without them uses its Smithy manifest.

The version must be exact. A range such as `^1.2.0` fails when the CLI reads the configuration, before it acquires anything. The CLI block shows this error.

The parsed input knows its kind and its location: the npm registry, the Maven repository or the GitHub repository. The default npm registry is `https://registry.npmjs.org`. The default Maven repository is Maven Central. The MoonBit block reads one input of each kind.

For the download cache and the option `--offline`, read [Verified cache and offline acquisition](../../../../pkgs/artifact-resources/README.mbt.md#verified-cache-and-offline-acquisition).

This project does not support the root-level `maven` key of Smithy, with its `dependencies`.

This lesson does not run in the browser, and its blocks do not use the network. The tests of this repository run them.

```include
CLI: apps/smithy/README.md#remote-inputs-cli
MoonBit: pkgs/smithy-build/README.mbt.md#remote-inputs-api
```
