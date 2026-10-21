# Supplied repository credentials

Supply a valid npm read token in `NPM_TOKEN` through your shell or secret manager,
then run from the repository root:

```shell
mise exec -- moon run apps/smithy --target js -- build --config examples/authenticated-repositories/smithy-build.json
mise exec -- moon run apps/smithy --target js -- build --config examples/authenticated-repositories/smithy-build.json --offline
```

This uses the same pinned public SQS package and explicit Maven trait imports as
[the npm example](../npm-registry/README.md), with a Bearer binding for the npm
registry. A public package keeps the artifact reproducible; the request still
carries your supplied token. No secret is stored in configuration. Native is
also supported via `--target native`. The first run requires HTTPS and curl.

For private packages, change the exact package/version and explicit model paths.
For another registry, update both `npm.registry` and the credential `origin`.
A binding covers the exact scheme/host/port, across all paths. If the tarball is
hosted at another authenticated origin, bind that origin separately. Redirects
do not forward tokens across origins.

Keep `NPM_TOKEN` supplied for offline runs. A different value or anonymous request
cannot reuse the authenticated mapping. Cache hits verify integrity without
checking server-side revocation; remove `.dev/cache/authenticated-repositories`
to require fresh authorization. Protect the cache as private artifact data.

Run a complete example without real credentials or external services:

```shell
mise run test:http
```

The fixture harness supplies private npm, Maven and GitHub repositories, uses
Bearer and Basic credentials, builds models in sources and both import scopes,
and compares results with local inputs. It exercises safe redirected private
GitHub assets, offline reuse, changed-identity misses and authentication failures
on native and Node. It also verifies unsupported default Wasm hosts explicitly.
See [credential configuration](../../apps/smithy/README.md#repository-credentials)
for GitHub and Maven bindings, and [the library contract](../../pkgs/artifact-resources/README.mbt.md#supplied-repository-credentials)
for authorization, cache and host requirements. Interactive login and enterprise
SSO are separate work.
