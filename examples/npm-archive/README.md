# Local npm archives

Run from the repository root. Neither command installs a package, extracts files,
contacts a registry or runs bundled code or lifecycle hooks.

```shell
mise exec -- moon run apps/smithy --target js -- build --config examples/npm-archive/smithy-build.json
mise exec -- moon run pkgs/artifact-resources/examples/npm --target js
```

The build selects `package/models/**/*.smithy` from
`smithy-local-models-1.0.0.tgz`, imports `package/imports/shared.smithy`, and adds
`package/projection-imports/extra.smithy` only to the `extra` projection. Output
is under `.dev/out/npm-archive`. Logical source names start at the configured
root. Diagnostics retain the full physical `archive.tgz!/package/...` path.
The fixture includes lifecycle hooks that throw if executed. Regenerate it with
`mise run fixtures:npm`, which uses the pinned toolchain's npm with
`pack --offline --ignore-scripts`. Sources come from `examples/local-resources`.

The library example selects `smithy.json` with root `package/contract` from the
unchanged downloaded `@pontx/amazon-sqs@0.1.5` tarball and reports its 138 shapes.
This real AWS contract references AWS and Smithy rules traits that are not in
Smithy's built-in prelude. Full semantic assembly of that contract additionally
requires their definitions. The example demonstrates local model acquisition.

Downloaded fixture:

- URL: <https://registry.npmjs.org/@pontx/amazon-sqs/-/amazon-sqs-0.1.5.tgz>
- SHA-256: `d3b921a9d9ddf20a28bb2cbe631e78df83ec646ecf79a0d3ecb606dcad393a08`
- npm SHA-512: `zW0qayeAdEKKjqmW6X9a6DYqd6AY/gZE491RNpLZBLjdA+IFOBRm1rri4vu6rsx4Lo7e7rU6BMNY8AmmECO+oA==`
- Package license: MIT. The AWS contract is Apache-2.0. Original notices and
  licenses remain in the tarball at `package/LICENSE`,
  `package/contract/LICENSE.aws-sdk-js-v3` and `package/THIRD_PARTY_NOTICES.md`.

Any downloaded `.tar`, `.tar.gz` or `.tgz` can use the same selection objects in
build sources, imports and projection imports. Use `root: "package"` for the
usual npm wrapper or a deeper root such as `package/contract`. Selection is
explicit; archives are never scanned for code or automatically installed.
See the [reader support policy](../../pkgs/artifact-resources/README.mbt.md#tar-and-gzip-support).
