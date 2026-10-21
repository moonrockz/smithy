# Pinned public Maven JARs

Run from the repository root:

```shell
mise exec -- moon run apps/smithy --target js -- build --config examples/maven-repository/smithy-build.json
mise exec -- moon run apps/smithy --target js -- build --config examples/maven-repository/smithy-build.json --offline
mise exec -- moon run pkgs/artifact-resources/examples/maven --target native
mise exec -- moon run pkgs/artifact-resources/examples/maven --target native -- --offline
```

The build acquires the direct JAR
`software.amazon.smithy:smithy-aws-traits:1.72.0` from Maven Central, verifies the
pinned SHA-256 and discovers trait definitions through `META-INF/smithy/manifest`.
The local source uses `aws.api#service`. Output is under
`.dev/out/maven-repository`. The library consumer uses explicit resource selection
to print `META-INF/smithy/aws.api.smithy` and structured provenance. AWS Smithy
models are Apache-2.0 licensed.

Both consumers share `.dev/cache/maven-repository`. The first run requires
network access and curl. Offline runs verify cached content without invoking
transport. A caller-supplied SHA-256 takes precedence over sidecars; omit `digest`
to use the default `.jar.sha1`, or set `maven.checksum` to `sha256` for `.jar.sha256`.
Sidecars require a bare hexadecimal digest, with optional surrounding whitespace.
There is no algorithm or repository fallback. Optional `classifier` selects one
classified JAR. Add root/path/glob selection when a manifest is not appropriate.

This is direct artifact acquisition. No POMs, transitive graph, ranges, mutable
snapshots, plugins or bundled code run. Each configured input chooses its public
repository explicitly. Supplied credentials use [origin bindings](../../apps/smithy/README.md#repository-credentials). See the
[provider contract](../../pkgs/artifact-resources/README.mbt.md#pinned-maven-jars)
for coordinate validation, integrity, cache and host support.

`mise run test:http` compares controlled JARs with their local equivalents,
checks manifest exclusion and explicit selection through all build input
positions, and repeats builds offline without requests. Portable package tests
cover classifier paths, repository selection, checksum mismatch, missing artifacts
and authentication refusals. Normal tests do not depend on Maven Central.
