# Public archive URLs

Build the same models as `examples/local-resources` directly from a public ZIP
of this repository at commit `f66a4a77685902ffed964c63ecbabd0fd2465ab4`:

```shell
mise exec -- moon run apps/smithy --target js -- build --config examples/public-archive/smithy-build.json
mise exec -- moon run pkgs/artifact-resources/examples/public --target native
```

The first online run needs network access and curl with HTTPS support. Linux/macOS
use the trusted host PATH; Windows uses its OS-installed curl.
The build loads sources, global imports and projection imports from the same
pinned URL. The `extra` projection additionally contains
`example.resources#ProjectionOnly`. Output is under `.dev/out/public-archive`.
The library example prints each resource's requested URL, resolved URL,
verified SHA-256 and physical archive entry path.

The archive digest is
`sha256:7a191fd47666fd9cb0ef3b4e1cd4561e31d412fcb7205f1a0fb742b723d3faa2`.
Each acquisition verifies it before archive parsing or model loading. An upstream
change to the ZIP bytes fails integrity verification even at the same URL.
The build and library example reuse `.dev/cache/public-archive` on later runs.
Rebuild explicitly offline after the first successful run:

```shell
mise exec -- moon run apps/smithy --target js -- build --config examples/public-archive/smithy-build.json --offline
mise exec -- moon run pkgs/artifact-resources/examples/public --target native -- --offline
```

These runs read and verify cached bytes without invoking curl or making a network
request. Models, sources and acquisition provenance remain identical. The library
example accepts only the optional `--offline` argument. The build configuration
sets `cacheDirectory` relative to its own file; other builds default to
`.smithy/cache`. Override it with `--cache-dir PATH`, or set `"offline":true` in
JSON for offline operation by default. Missing entries produce `offline-miss`;
corrupt entries produce `cache-corrupt`; unexpected digests produce
`integrity-failure`. Remove the cache and rebuild online to recover corruption.
Cache entries have no expiry or automatic eviction. `smithy clean` retains them.

For tar/gzip archives, set `format` to `tar` or `tgz` and select the appropriate
root. The public URL
`https://registry.npmjs.org/@pontx/amazon-sqs/-/amazon-sqs-0.1.5.tgz`
has digest
`sha256:d3b921a9d9ddf20a28bb2cbe631e78df83ec646ecf79a0d3ecb606dcad393a08`.
Use root `package/contract` and path `smithy.json` to read its contract.
See the [local npm example](../npm-archive/README.md) for its license and
additional semantic assembly requirements.

Normal tests use a loopback HTTP server, not these public services:

```shell
mise run test:http
```
