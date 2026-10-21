# Pinned GitHub release assets

Read bat's license directly from its public `bat-v0.25.0-x86_64-pc-windows-msvc.zip` release asset:

```shell
mise exec -- moon run pkgs/artifact-resources/examples/github --target native
mise exec -- moon run pkgs/artifact-resources/examples/github --target native -- --offline
```

The first command needs network access and curl. It resolves repository
`sharkdp/bat`, tag `v0.25.0` and exact asset `bat-v0.25.0-x86_64-pc-windows-msvc.zip`, verifies
`sha256:1d5ced071ba9c765e16f4065877c178cefcfd2fe9581e9ddc92af265b73991bd`,
and selects `bat-v0.25.0-x86_64-pc-windows-msvc/LICENSE-MIT` through the common ZIP resource reader.
The output includes the requested tag, resolved release and asset IDs, download
URLs, digest, physical entry path and license text. bat is never built or run.
The second command reads `.dev/cache/github-release` without invoking transport
and prints the same output. Node.js is also supported via `--target js`.

For a Smithy build, use the `github` object shown in the
[CLI documentation](../../apps/smithy/README.md#public-github-release-assets), set
its exact public repository/tag/asset and select model paths. ZIP, tar and gzip
assets work in sources, global imports and projection imports. A runnable build
fixture for all three positions is available without public-service access:

```shell
mise run test:http
```

It builds equivalent local and pinned GitHub ZIP/tar/gzip inputs, compares their
assembled models, disables network access and repeats the pinned builds offline.
The bat example demonstrates generic resource loading; bat's archive is not a
Smithy model package. Nothing is installed or extracted from either example.

GitHub.com is the supported service. Public compatible API endpoints can be
selected using `api` in the library or `github.api` in build configuration.
Supplied credentials use [origin bindings](../../apps/smithy/README.md#repository-credentials). Enterprise SSO, latest selection and asset patterns are outside this slice. See the [full contract](../../pkgs/artifact-resources/README.mbt.md#pinned-github-release-assets)
for bounds, host support, provenance and stable diagnostics.
