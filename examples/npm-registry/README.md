# Exact public npm packages

Run from the repository root:

```shell
mise exec -- moon run apps/smithy --target js -- build --config examples/npm-registry/smithy-build.json
mise exec -- moon run apps/smithy --target js -- build --config examples/npm-registry/smithy-build.json --offline
mise exec -- moon run pkgs/artifact-resources/examples/npm-registry --target native
mise exec -- moon run pkgs/artifact-resources/examples/npm-registry --target native -- --offline
```

The build resolves `@pontx/amazon-sqs@0.1.5` directly from the public npm registry,
verifies its registry SHA-512 and pinned SHA-256, and selects
`package/contract/smithy.json`. It explicitly imports the `smithy-aws-traits` and
`smithy-rules-engine` JARs at `1.72.0` from Maven Central to supply AWS and rules
trait definitions. Those imports are listed in configuration; no package
transitive dependencies or POMs are resolved. The upstream contract emits enum
naming warnings but assembles successfully. Output is under
`.dev/out/npm-registry`.

The independent library consumer prints provenance and the contract's 138 shapes.
The package and AWS contract retain their MIT/Apache-2.0 licenses and notices;
see the [downloaded local fixture](../npm-archive/README.md). No package code or
hooks run and no archive files are extracted. Both consumers share
`.dev/cache/npm-registry`. The first run uses HTTPS and curl; later offline runs
verify cached metadata/content without invoking transport. Node.js is also
supported for the library example using `--target js`.

Configuration supports an explicit `npm.registry`, exact scoped/unscoped package
names and versions, resource roots/paths/globs and optional expected SHA-256.
Supported SRI algorithms, archive variants, host limits, stable diagnostics and
cache policy are documented in the [provider contract](../../pkgs/artifact-resources/README.mbt.md#public-npm-packages).
`mise run test:http` compares scoped and unscoped controlled fixtures to local tgz
builds through sources, global imports and projection imports, then rebuilds
offline with no requests. Normal tests do not depend on npm or Maven Central.
