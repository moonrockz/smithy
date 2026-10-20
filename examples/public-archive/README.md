# Public archive URLs

Build the same models as `examples/local-resources` directly from a public ZIP
of this repository at commit `f66a4a77685902ffed964c63ecbabd0fd2465ab4`:

```shell
mise exec -- moon run apps/smithy --target js -- build --config examples/public-archive/smithy-build.json
mise exec -- moon run pkgs/artifact-resources/examples/public --target native
```

Both commands need network access and curl with HTTPS support. Linux/macOS
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
The next build downloads again. Caching and offline reuse are separate work.

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
