# Artifact resources

`moonrockz/artifact-resources` loads declared binary or text resources from
entry trees. It has no Smithy dependency. The root package reads ZIP/JAR and
tar/gzip bytes and host-supplied directory entries without filesystem or network access.
`moonrockz/artifact-resources/local` provides filesystem acquisition.

## Independent library use

```mbt check
///|
test {
  let tree = @resources.EntryTree::directory(
    [@resources.EntryPath::parse("messages/hello.txt").unwrap()],
    _ => b"hello",
    @resources.Location::parse("memory-directory").unwrap(),
  )
  let loaded = @resources.load_resources(tree, [
    {
      name: @resources.ResourceName::parse("greeting").unwrap(),
      path: @resources.EntryPath::parse("messages/hello.txt").unwrap(),
    },
  ])
  assert_eq(loaded[0].name.to_string(), "greeting")
  assert_eq(loaded[0].text(), "hello")
}
```

Use `EntryTree::zip(bytes, origin)` for ZIP32/JAR input. It supports stored and
deflated entries, verifies CRC-32 and uncompressed size when reading, and
records `digest` as `sha256:<hex>` over the complete archive bytes. ZIP64,
encrypted and multi-disk archives are unsupported. `open_zip(path)` opens a
nested archive while retaining its parent's provenance.

`entries()` lists physical file paths in lexical order. `contains(path)` checks
exact safe entry names, while reading requires a file. ZIP directory markers
are retained for root checks and manifest discovery.
`read(path)` returns
bytes, and `text(path)` additionally requires UTF-8. The directory constructor accepts `style=Slash` or `style=Backslash` to retain
native physical filenames while entry paths use portable slashes.
`Declaration` maps a
logical resource name to a physical entry path. `load_resources` preserves
declaration order and rejects repeated logical names. It never discovers or
executes code. Consumers own their discovery rules. Smithy retains its
`META-INF/smithy/manifest` discovery in `smithy-build::declared_models`.

## Explicit selection

`Selection::new(root, selectors)` requires 1 through 256 selectors. Choose
`ResourceRoot::ContainerRoot` for the whole tree or `Subtree(EntryPath)` for a
subdirectory. `ResourceRoot::parse(".")` chooses the container root.
`Exact(path)` selects one root-relative file. `Named(path, name)` assigns an
explicit logical name. `Matching(GlobPattern)` selects matching files.
`select_resources(tree, selection)` returns resources in lexical logical-name
order. `tree.select(selection)` returns declarations without reading content.

Glob matching is case sensitive. `*` matches zero or more characters and `?`
one character within a component. A whole-component `**` matches zero or more
directories. For example `**/*.txt` includes both `hello.txt` and
`nested/hello.txt`. Embedded `**`, escaping, character classes and brace
expansion are rejected. Patterns are limited to 1024 UTF-16 code units.
Matching shares the tree's configurable `max_match_steps` budget.

Each selector must match at least one file. Missing roots and unmatched
selectors have distinct errors. A directory is never a selected file.
Overlapping selectors deduplicate identical logical/physical pairs. One logical
name selecting different files fails. Explicit aliases may export one file
under different names. Default names are relative to the chosen root, and
physical locations retain the complete path. Selection never follows or executes
bundled source code, scripts or nested archives.

## Domain values

| Value | Meaning |
|---|---|
| `RepositoryId`, `ProviderId` | Distinct configured repository and registered provider identifiers |
| `ArtifactKey`, `ArtifactIdentity` | Requested key and provider-resolved exact identity |
| `RepositoryLocation` | Provider-interpreted source address |
| `EntryPath` | Portable path inside a container |
| `ResourceName` | Consumer-facing logical name, independent of the physical path |
| `Location` | Source address with structured directory or archive entry relationships |
| `Provenance` | Physical location and typed acquisition history |
| `ContentDigest` | SHA-256 content identity, independent of repository keys |

String constructors return `None` for invalid values. Identifiers, identities
and addresses must be nonempty, contain a non-space character and contain no
control characters. Entry paths and resource names enforce the portable path
rules below. `ContentDigest::parse` checks the algorithm and 32-byte hex value.
`ResourceCode` is an enum with stable text from `to_string()`.

`Location::directory_entry` retains the host path style;
`archive_entry` retains archive nesting. `Provenance::steps()` returns typed
resolution, container and configuration steps. Its origin distinguishes physical locations
from provider registrations and repository references before acquisition.
`location()` returns an optional physical location. `through` composes history using structural
ancestry, even when unrelated locations have similar rendered text. The returned
step array is a copy. Use `to_string()` at diagnostics, filesystem and Smithy
filename boundaries.

This replaces the initial string metadata API. Parse boundary strings into the
appropriate types, use typed declarations and repository references, and render
only when presenting output. Provider errors use `ResourceCode::ProviderFailure`
with a structured `Provenance` and free-form detail.

## Repositories and providers

A `Repository` has a caller-chosen `id`, a registered `provider` name, and a
provider-specific `location`. An `ArtifactRef` names that repository and an
artifact `key`. Register provider callbacks with `Registry::register_provider`
and configure repositories with `add_repository`. `resolve` returns the input
reference, an exact provider-specific `identity` and an `EntryTree`.
Registration rejects duplicate names. A fixture provider can return an
in-memory tree using the same API as the local provider.

The local adapter's `register(registry, limits~)` installs provider `local`.
Its location is a filesystem root. Key `.` selects that root; other keys are
relative paths. It opens directories, individual files and `.jar` or `.zip` archives.
It also opens `.tar` with `EntryTree::tar` and `.tar.gz` or `.tgz` with
`EntryTree::tgz`. Archive constructors take bytes and a physical `Location`.
Directory enumeration uses an explicit stack. File contents are read lazily,
so directories have no immutable digest. A caller needing a snapshot must
supply a stable directory reader or retain the returned resource bytes.
The adapter uses the host filesystem's symlink behavior and access rights.
It does not establish a filesystem sandbox.

`Resource.origin` is the physical source filename, such as
`models.jar!/META-INF/smithy/a.smithy`. `Resource.provenance` and error origins
also include the repository reference and resolved identity. This keeps
Smithy source filenames compatible while preserving the acquisition chain
in loading diagnostics. Archive bytes have a content digest, independently
of repository keys and resource names.

Run the independent consumer from the repository root:

```shell
mise exec -- moon run pkgs/artifact-resources/examples/local --target js
```

It selects `examples/local/data/**/*.txt` from the module root through the
registered local provider. An optional argument selects another module source
directory or ZIP with that layout. Normal `moon package` inclusion keeps this
data in the published source archive; no additional resource manifest is needed.
The repository identity stays `moonrockz/artifact-resources`.

## Limits and diagnostics

`Limits::new` defaults to 64 MiB archive bytes, 10,000 entries, 16 MiB per
entry, 256 MiB total expanded ZIP bytes or selected resource bytes, and
16 million estimated glob matching steps. `max_expanded_bytes` separately limits
the complete tar envelope to 256 MiB, including metadata, headers and padding.
Negative limits fail. ZIP sizes and paths are checked before content decoding;
streaming inflation rejects content exceeding its declared size. Directory
readers check per-entry limits after the host returns bytes. Directory limits
do not bound host filesystem reads or establish a snapshot. Filesystem
adapters must enforce tighter allocation or access policies when needed.

Paths are relative and slash-separated. Absolute paths, empty components,
`.` and `..`, backslashes, drive separators, control characters and reserved
portable filename punctuation are rejected. Unlisted ZIP paths are validated
too. Duplicate physical entries are rejected before the ZIP decoder can
replace one silently. Generic resources may have spaces in their names;
Smithy's manifest consumer retains its stricter rules.

`ResourceError(code, origin, detail)` has stable codes:

| Code | Meaning |
|---|---|
| `invalid-archive` | Malformed or unsupported ZIP, tar or gzip data |
| `integrity-failure` | Content size, CRC or tar header checksum mismatch |
| `unsafe-path` | Unsafe physical path, logical name or local artifact key |
| `missing-resource` | A declared file is missing or is a directory |
| `duplicate-entry` | Repeated physical entry path |
| `duplicate-resource` | Repeated logical name |
| `resource-limit` | An entry, archive or total exceeds its limit |
| `invalid-limits` | A negative limit |
| `invalid-utf8` | Text requested for non-UTF-8 bytes |
| `local-io` | Host filesystem acquisition failed |
| `duplicate-provider`, `duplicate-repository` | Repeated registration |
| `unknown-provider`, `unknown-repository` | Missing registration |
| `invalid-resolution` | A provider returned a different reference |
| `missing-root`, `missing-selection` | Missing subtree or selector matching no files |
| `provider-failure` | Provider-specific acquisition failure |

## Backend support

| Package | wasm | wasm-gc | JS | native |
|---|---|---|---|---|
| Entry trees, ZIP/tar/gzip readers, resources, provider registry | Yes | Yes | Yes | Yes |
| Local filesystem adapter | MoonBit filesystem host | MoonBit filesystem host | Node.js | Host OS |

The pure contracts run on all four targets. Filesystem acquisition requires
the corresponding host filesystem implementation. Raw Wasm files need the
MoonBit filesystem imports. Local loading makes no network requests.
Public HTTP, GitHub, npm and Maven acquisition and supplied credentials are
implemented below. This module joins the repository's next normal shared release.

## Tar and gzip support

`EntryTree::tar(bytes, origin, limits~)` reads V7 and POSIX ustar archives.
`EntryTree::tgz` reads gzip-compressed tar, including npm `.tgz` packages.
Both retain physical entry paths and SHA-256 of the original input bytes.
Use the existing `Selection` API with `ResourceRoot::parse("package/models")`
to select models beneath npm's wrapper. No path prefix is stripped from origins.
The [npm example](../../examples/npm-archive/README.md) includes an unchanged
registry download and a runnable build with all three input positions.

Regular files with type NUL or `0`, directories with type `5`, ustar path
prefixes, UTF-8 names and per-file pax headers with type `x` are supported.
Pax `path` and decimal `size` override the following file or directory.
Recognized non-content metadata is ignored: `uid`, `gid`, `uname`, `gname`,
`mtime`, `atime`, `ctime`, `comment`. Other pax keywords fail explicitly.
Global pax headers, GNU long-name/long-link/sparse extensions, base-256 sizes,
links, devices, FIFOs and all other entry types are unsupported, even when
unselected. Only one pax header may precede a file or directory. Its placeholder
name is metadata, never an entry path; path validation applies to the effective
file or directory path that follows it.

Tar requires valid unsigned header checksums, octal sizes, complete entry data
and padding, two zero end blocks and only whole zero blocks after them.
Directories have zero size. Unsafe paths and duplicate effective paths,
including file/directory collisions, fail before selection. Tar has no file
content checksum; its header checksum cannot detect changed payload bytes.
Use a trusted archive digest when content authentication is needed.

Gzip uses DEFLATE with bounded streaming output. It accepts optional extra,
name and comment fields and verifies optional header CRC-16, payload CRC-32
and ISIZE. Concatenated gzip members join into one tar stream and share the
expanded-byte budget. Reserved flags, incomplete members and trailing bytes
fail. This follows the member layout in [RFC 1952](https://www.rfc-editor.org/rfc/rfc1952).

All tar headers, including directories and pax headers, count against
`max_entries`. Every payload, including pax metadata and unselected files,
counts against `max_entry_bytes` and `max_total_bytes`. Compressed input is
bounded by `max_archive_bytes`, and inflation stops at `max_expanded_bytes`
without trusting the trailer size. Readers work entirely in memory and never
extract files or execute package code. The local adapter reads archive bytes
through the host filesystem before checking their size; these limits do not
bound the host read allocation or establish a filesystem sandbox.

## Standalone script consumer

`examples/resource-consumer/main.mbtx` at the repository root pins this module's
shared release version and imports the same public API. After the next normal
release, run it with `moonx examples/resource-consumer/main.mbtx MODULE_DIRECTORY_OR_ZIP`.

Before publication, `mise run test:resources` packages the module with
`moon package`, seeds an isolated local index and archive cache with those exact
bytes and cached public dependencies, then runs the unchanged pinned script
against the unpacked module and ZIP. It leaves the user's registry untouched.
This verifies ordinary source inclusion and script imports without publishing
a special version. The task-script test suite runs this check in CI.

## Public HTTP archives

`PublicArchive` combines a validated `HttpUrl`, an explicit `ArchiveFormat`
and an optional expected `ContentDigest`. `PublicArchive::open(transport)`
acquires bytes, accepts only HTTP 200, computes SHA-256 and verifies any expected
digest before opening the archive. ZIP/JAR, tar and tar/gzip reuse the portable
readers and selectors. URLs require lowercase `http://` or `https://`, an
authority, printable ASCII, no user information and no fragment. Percent-encode
non-ASCII path and query characters.

`HttpTransport` is a synchronous callback from `HttpRequest` and `AcquisitionLimits`
to `HttpResponse`, with `resolved`, `status` and binary `body` fields. Hosts can
provide their own transport without changing discovery. Transport implementers
must enforce byte and total transfer time limits during I/O, follow at most five
redirects, reject URL user information and non-HTTP schemes, strip authorization
on origin changes, and verify TLS certificates.
HTTPS requests must not redirect to HTTP.

The `moonrockz/artifact-resources/http` package supplies `transport` using curl.
On Linux and macOS it uses the host's trusted PATH. On Windows it uses the
OS-installed `System32/curl.exe` through an absolute application path, so a
checkout-local `curl.exe` cannot take precedence. The Node.js Windows adapter
uses the trusted host `SystemRoot` environment variable to locate this copy. It invokes curl directly without a shell, disables curl configuration
files and URL globbing, and leaves certificate verification enabled. Authorization
headers travel through a private stdin pipe, never argv or temporary files.
The MoonBit adapter follows redirects explicitly and strips authorization before
contacting another origin. It never introduces that destination's configured
credential during a redirect. A monotonic deadline covers all hops. curl 7.61+
with HTTP/HTTPS support is required. It uses the host trust store and honors
curl's proxy and certificate environment settings. See curl's
[transport options](https://curl.se/docs/manpage.html).

| Backend / host | Archive reading | Default public acquisition |
|---|---|---|
| Native Linux, macOS | Yes | curl on trusted PATH |
| Native Windows | Yes | OS-installed curl |
| JS in Node.js 24+ | Yes | Host curl via Node child processes |
| Wasm / Wasm GC filesystem hosts | Yes | `unsupported-transport` |
| Browser JS | In-memory readers | Supply a host transport |

Local inputs never invoke the HTTP adapter. Reading and selecting existing
bytes remains portable and works offline. The synchronous default adapter is
for command-line hosts; it blocks the calling thread during acquisition.

`AcquisitionLimits::new()` defaults to 64 MiB and 30 seconds across all redirects.
The constructor returns `None` for nonpositive limits, bytes over 1 GiB or time
over 3600 seconds. `PublicArchive::open` uses the smaller acquisition/archive
byte budget. The curl adapter also bounds its captured output to that budget
plus 16 KiB of response metadata, including unknown-length responses on older
curl versions. Archive expansion, entry and selection limits apply independently.
No archive files are extracted and acquisition does not execute bundled code.

`register_public_http(registry, transport, format~, expected_digest~,
acquisition_limits~, limits~)` registers provider ID `public-http` in the common
registry. Each repository location is a complete public URL and its artifact
key is `.`. The returned identity is the resolved URL, `tree.digest` is the
acquired bytes' SHA-256, and `AcquisitionStep(Acquisition)` records requested URL,
resolved URL and digest in tree and per-resource provenance. Registry resolution
adds the original structured artifact reference. Physical entry origins use the
resolved URL followed by `!/entry/path`.

Stable acquisition codes are `unsupported-transport`, `transport-failure`,
`acquisition-timeout`, `resource-limit`, `authentication-required` for 401/403,
`missing-asset` for 404/410, `rate-limited` for 429, `http-status` for other non-200 responses, and
`integrity-failure` for a mismatched expected digest. HTTP failures stop before
archive discovery. Redirect exhaustion and invalid TLS certificates are
transport failures. Credentials are explicit, as described below; there are no automatic retries.

Run the [public URL example](../../examples/public-archive/README.md) for a
complete build and independent library consumer. `mise run test:http` exercises
the real adapters against loopback fixtures; portable policy and provenance
tests run in the normal four-backend package suite.


## Verified cache and offline acquisition

`acquire(url, transport, expected_digest~, limits~, cache~, mode~)` is the shared
byte acquisition boundary beneath archive parsing. It returns `AcquiredBytes`
with structured `Acquisition` metadata and verified bytes. `PublicArchive::open`
and `register_public_http` accept the same optional `cache` and `mode` settings.
The library defaults to `Online` without a cache. Set `mode=Offline` explicitly
to forbid transport calls, even when no cache was supplied.

Create a filesystem cache with `moonrockz/artifact-resources/cache::open(directory)`
using a validated `CacheDirectory::parse(path)` value
and pass `cache=Some(cache)`. This host adapter supports native Linux, macOS,
Windows and Node.js 24+. Wasm and Wasm GC return `unsupported-transport` when
filesystem cache I/O is requested. The core cache policy and archive readers run
on all four targets. Other hosts can supply a `CacheStore` to `VerifiedCache::new`.
A store must bound reads, return `None` only for absent keys and atomically publish
complete values. Failed storage operations raise `cache-io`.

The filesystem layout is versioned reference metadata in `ref-v1-<sha256>` and
content in `sha256-<hex>`. Reference keys hash a structured pair of provider ID
and exact reference, including URL query parameters. `CacheKey::reference` leaves
room for provider-specific pinned-reference mappings. `CacheKey::content` names
content independently, so distinct references may share identical bytes.
Metadata stores the requested URL, resolved URL and SHA-256. Local cache paths
never replace remote resource origins or acquisition history.

Every hit rehashes the full content and enforces the current expected digest and
byte limits before archive parsing. Online hits make no HTTP request. URLs are
treated as pinned references; there is no TTL or refresh request. Use expected
digests for reproducibility. To refresh a mutable URL, remove its reference file
or select a fresh cache directory. A changed expected digest fails rather than
silently replacing cached bytes.

`offline-miss` means no reference metadata exists. `cache-corrupt` means malformed
metadata, missing referenced content or a content digest mismatch. These fail in
both modes without a network fallback. `integrity-failure` identifies an expected
digest mismatch. Oversized cache values fail with `resource-limit`. Remove the
damaged entry or cache directory and run online again to recover.

Population verifies response status and expected digest first, publishes content,
then publishes reference metadata. The host writes to unique temporary files in
the destination filesystem and renames only after a complete write and close.
Concurrent readers see complete values; interrupted writes can leave unreferenced
content or temporary files, which lookups ignore. There is no automatic eviction
or temporary-file cleanup. This is a reusable local cache, not a power-loss-durable
artifact database or a substitute for an externally trusted expected digest.

The [public archive example](../../examples/public-archive/README.md) demonstrates
online reuse and explicit offline builds. Controlled fixtures assert request
counts, identical output, corruption failures and shared cache behavior across
sources, global imports and projection imports.


`CacheDirectory` is distinct from a provider's `RepositoryLocation`. Its boundary
constructor validates a portable filesystem-path subset before I/O. It accepts
relative paths, POSIX absolute paths, absolute Windows drive paths and UNC share
paths. Empty/control-containing paths, Windows reserved characters, drive-relative
paths, reserved device components and trailing dots/spaces are rejected on every
backend. Existence, permissions and filesystem-specific size limits remain host
I/O checks. Cache diagnostic locations retain the typed directory through
`Location::FilesystemDirectory`; paths render only for host I/O and diagnostics.

API migration: exhaustive `Location` matches must handle the new
`FilesystemDirectory(CacheDirectory)` case.


## Pinned GitHub release assets

`GitHubArchive` resolves a named archive from a public GitHub release. Supply a
validated `GitHubRepository` in `owner/name` form, a `GitHubAssetRef` with distinct
`GitHubTag` and `GitHubAssetName` values, an explicit `ArchiveFormat` and an optional
expected `ContentDigest`. Tags are URL-encoded as one path segment. Asset names
match exactly, including case. There is no latest-release lookup, wildcard asset
selection or dependency resolution. Supplied credentials use the common boundary below.

`GitHubArchive::open(transport, api~, acquisition_limits~, limits~, cache~, mode~)`
uses the [release-by-tag API](https://docs.github.com/en/rest/releases/releases#get-a-release-by-tag-name)
and the [paginated release-assets API](https://docs.github.com/en/rest/releases/assets#list-release-assets).
It validates the returned release ID, requested tag and published state, then
checks every asset page for one exact name. Asset metadata must contain a positive
ID, uploaded state and credential-free HTTP(S) browser download URL. IDs are
positive integers in JSON's exact range, up to 9007199254740991. Each metadata
response is bounded to the smaller of 1 MiB and the acquisition byte limit.
Enumeration is limited to ten pages of 100 assets and fails closed if the final
page is full. Transfer timeouts apply per request. Archive expansion and resource
selection retain the shared limits. Download redirects use the common transport.
No bundled code or package hooks run.

The default API base is `https://api.github.com`. `api` can select a compatible
public API endpoint, including a loopback fixture server. It must be a
credential-free HTTP(S) base without query or fragment. GitHub.com is the supported service, including private repositories with supplied
read tokens. Enterprise SSO and GitHub Enterprise Server compatibility have not
been qualified. The acquisition host matrix is the same as
public HTTP archives: native Linux/macOS/Windows and Node.js with curl; Wasm and
Wasm GC need a supplied transport. Archive reading, provider policy and in-memory
cache use work on all four targets. Local inputs need no network.

The provider verifies both an expected SHA-256 and GitHub's asset `digest` when
present. A conflicting expected/API digest fails before downloading. Older assets
with absent or null API digests still receive a computed SHA-256; pin an expected
digest for reproducibility. `GitHubStep(GitHubResolution)` records the repository,
requested tag/name, typed release/asset IDs and download URL. The shared
`AcquisitionStep` records requested/resolved download URLs and content digest.
Each selected resource retains this history and its physical archive entry path.
`GitHubRequestStep` retains the requested coordinate in resolution errors.

`register_github(registry, transport, api~, format~, expected_digest~,
acquisition_limits~, limits~, cache~, mode~)` registers provider ID `github`.
Repository locations are `owner/name`; use `GitHubAssetRef::key()` to obtain the
artifact key and `from_key()` to decode it. The key serializes tag and name as
separate JSON array elements. The registry identity renders the resolved release and
asset IDs, while provenance keeps them structured. Discovery and archive readers
contain no GitHub-specific logic.

Release metadata, every asset page and archive bytes use the verified HTTP cache.
An online cache hit makes no request; `Offline` resolves and opens only cached
metadata and bytes. Cache corruption, changed expected digests and missing entries
fail closed. GitHub tags and assets can change upstream, so caches have no TTL or
automatic refresh. Select a fresh cache directory to resolve them again.

Stable provider codes are `missing-release` for a release 404/410, `missing-asset`
for an absent name or download 404/410, `ambiguous-asset` for duplicate exact names,
`invalid-resolution` for malformed or mismatched metadata, `rate-limited` for 429
or a GitHub API 403 reporting a rate limit, and `authentication-required` for
other 401/403 responses. Private repositories can appear as `missing-release`
because GitHub conceals them. Transport, cache, archive, integrity and selection
errors retain their shared codes. Rate limits fail immediately with no automatic
retry or authenticated fallback.

Run the [GitHub release example](../../examples/github-release/README.md) online,
then offline. `mise run test:http` verifies selected ZIP and tar/gzip assets against
local equivalents in sources, global imports and projection imports using a
controlled server. Portable package tests cover pagination, ambiguity, missing
metadata, rate limits, authentication refusals, integrity and offline resolution.


## Public npm packages

`NpmArchive` resolves `NpmPackageRef`, an `NpmPackageName` plus an exact
`NpmVersion`, against a validated `RepositoryUrl`. Scoped and unscoped lowercase
ASCII names are supported, with letter/digit component starts and subsequent
letters, digits, hyphens, underscores or dots. Versions use strict three-component SemVer, including
prerelease and build identifiers. Ranges, `v` prefixes and dist-tags such as
`latest` are rejected. Names and versions are encoded as URL path segments.
The provider uses the [npm exact-version endpoint](https://github.com/npm/registry/blob/main/docs/REGISTRY-API.md#getpackageversion),
checks the returned name/version and follows its credential-free `dist.tarball`.
Package metadata is bounded to the smaller of 1 MiB and the acquisition byte
limit. Tarballs use the shared tar/gzip reader and its existing limits. Nothing
is installed, extracted or executed; package scripts and dependencies are data.

`dist.integrity` uses a documented subset of [npm SRI](https://github.com/npm/ssri):
SHA-512, SHA-256 and SHA-1, with canonical padded standard base64 and ASCII space,
tab, CR or LF separators. Integrity text is bounded to 8192 characters.
Only the strongest supported algorithm participates;
any matching digest at that strength succeeds. Unknown algorithms are ignored
when supported tokens exist. Malformed supported tokens, option suffixes or
unsupported-only sets fail with `unsupported-integrity`. If `integrity` is
absent, a 40-digit hexadecimal `dist.shasum` supplies legacy SHA-1 verification.
A present but invalid or unsupported integrity value never falls back to shasum.
An optional expected `ContentDigest` independently pins SHA-256 and must also
match. Verification runs before parsing or publishing archive content to cache,
and again on every cache hit.

`register_npm(registry, transport, expected_digest~, acquisition_limits~, limits~,
cache~, mode~)` registers provider ID `npm`. Repository locations are registry
base URLs. Obtain artifact keys from `NpmPackageRef::key()`. Both metadata and
verified content use the common cache; `Offline` forbids transport calls.
`NpmStep(NpmResolution)` retains registry, exact package/version, metadata
`Acquisition`, tarball URL and integrity requirements. The metadata acquisition
records the exact-version endpoint, its resolved URL after redirects and the
response SHA-256 that selected the tarball and integrity value. Acquisition history retains redirects and compressed
content SHA-256; resource origins retain the physical entry path. Resolution
failures retain `NpmRequestStep`.

The [npm registry example](../../examples/npm-registry/README.md) includes a
complete public model build and an independent library consumer. Default host
support matches public HTTP: native Linux/macOS/Windows and Node.js with curl.
Wasm and Wasm GC support the portable provider, integrity and archive code with a
supplied transport/cache store. Public compatible registries can be configured;
private registries use the explicit origin credentials described below.

## Pinned Maven JARs

`MavenArchive` acquires a direct JAR from a configured `RepositoryUrl` using
`MavenCoordinates`: distinct validated `MavenGroupId`, `MavenArtifactId`,
`MavenVersion` and optional `MavenClassifier` values. It follows the
[Maven repository layout](https://maven.apache.org/repositories/layout.html):
`group/segments/artifact/version/artifact-version[-classifier].jar`.
`MavenCoordinates::path()` returns a distinct `MavenArtifactPath`, separate from
entry paths inside the JAR. Coordinates use a bounded portable ASCII subset; traversal, URL metacharacters,
version ranges, `LATEST`, `RELEASE`, `SNAPSHOT` suffixes and timestamped snapshot
versions are rejected.
Only JAR artifacts are supported. POMs, transitive dependencies, version selection,
repository fallback and mutable snapshot metadata are outside this provider.
Each input explicitly selects one repository; repositories are not searched in
implicit order. The default configured repository is Maven Central at
`https://repo.maven.apache.org/maven2`.

A caller-supplied SHA-256 `expected_digest` takes precedence and avoids sidecar
requests. Otherwise `MavenChecksum::Sha1Sidecar` retrieves `.jar.sha1`, or
`Sha256Sidecar` retrieves `.jar.sha256`. The CLI defaults to SHA-1 sidecars for
legacy repository compatibility. These are repository integrity checks; an
independently supplied SHA-256 pins the expected content. See Maven's
[checksum strategies](https://maven.apache.org/resolver/expected-checksums.html).
Sidecars must contain only the bare hexadecimal digest, optionally surrounded by
whitespace, and are bounded to the smaller of 4 KiB and the acquisition byte
limit. There is no algorithm fallback, so the chosen sidecar URL and JAR can be
reused deterministically offline. Missing, malformed or mismatched checksums
fail before archive parsing. Mismatched JARs never enter the content cache.

`register_maven(registry, transport, checksum~, expected_digest~,
acquisition_limits~, limits~, cache~, mode~)` registers provider ID `maven`.
Repository locations are base URLs; keys come from `MavenCoordinates::key()`.
`MavenStep(MavenResolution)` retains repository, coordinates, JAR URL and a
structured `MavenVerification`: caller digest or sidecar acquisition plus checksum.
The common acquisition history records the JAR redirects and SHA-256.
`MavenRequestStep` retains the requested coordinates when resolution fails.
The library returns the common ZIP entry tree; Smithy manifest discovery remains
in the Smithy integration. Host support and cache/offline policy match npm and
public HTTP.

The [Maven example](../../examples/maven-repository/README.md) builds a model using
public AWS trait definitions and includes an independent resource consumer.

Stable repository diagnostics include `missing-package-version` for an npm
package/version 404/410, `missing-artifact` for a Maven JAR or sidecar 404/410,
`invalid-resolution` for mismatched or malformed metadata/coordinates,
`unsupported-integrity` for unsupported npm integrity metadata, and the shared
`authentication-required`, `rate-limited`, `integrity-failure`, cache, transport,
archive and selection codes. Credentials are supplied before the request; a failed
request does not trigger ambient lookup, login or a fallback identity. Private
repositories may conceal resources with 404 responses.

The generic `IntegrityVerifier` callback accepted by `acquire` and
`PublicArchive::open` runs after shared SHA-256 verification and before fresh
cache publication or archive parsing. Cached content is rehashed first, then the
callback runs. This lets providers add checksum policies without changing readers
or other providers. The default verifier performs no additional checks.

API migration: exhaustive `ProvenanceStep` matches must handle
`NpmRequestStep`, `NpmStep`, `MavenRequestStep` and `MavenStep`; `ResourceCode`
matches must handle `MissingPackageVersion`, `MissingArtifact` and
`UnsupportedIntegrity`.

## Supplied repository credentials

`HttpOrigin` validates an origin without path, query, fragment or URL user
information. It normalizes host case and default ports. `Authorization::bearer`
validates a token; `Authorization::basic` validates a username/password pair and
encodes the Basic header. Both reject control characters, and Debug/Show output
is redacted. `header_value()` is a host-adapter-only wire boundary and must never
be logged. Secrets stay in memory; there is no automatic `.npmrc`, Maven settings,
GitHub CLI, `.netrc`, interactive login or enterprise SSO discovery.

Construct `Credentials::new(entries=[(origin, authorization)])` with at most 32
unique origins. HTTPS is required except for `localhost`, `127.0.0.1` and `[::1]`
loopback fixtures. A binding covers every path on that exact scheme/host/port;
configure separate origins for separate trust domains. A separately hosted npm
tarball needs its own explicit binding if it requires authentication. Redirects
never introduce a destination credential or carry the original authorization to
another origin.

Pass `credentials~` to `acquire`, `PublicArchive::open`, `NpmArchive::open`,
`MavenArchive::open`, `GitHubArchive::open` or their `register_*` functions. The
default is anonymous. `HttpRequest` carries the URL, optional authorization and
an `HttpAccept` value. Custom transports must preserve the same bounds, TLS and
redirect rules. Migration from the former callback uses `request.url` where the
callback previously received a `HttpUrl`; direct host calls wrap public URLs in
`HttpRequest::anonymous(url)`.

GitHub uses Bearer authorization for release metadata. When its API origin has a
credential, the provider constructs `/repos/{owner}/{repo}/releases/assets/{id}`
and requests `application/octet-stream`, accepting a direct response or a safe
redirect. It does not send an API token to `browser_download_url`. Fine-grained
GitHub tokens need repository Contents read permission, as documented by the
[release asset API](https://docs.github.com/en/rest/releases/assets#get-a-release-asset).
npm normally uses Bearer tokens; Maven repositories commonly use Basic credentials
or a repository-issued Bearer token. The server decides the required permissions.

Authenticated reference and content keys are isolated by origin and a one-way
identity of the complete authorization value. Anonymous keys remain compatible.
Changing the token, username/password or origin cannot reuse the old authenticated
mapping. Raw authorization values are absent from keys, stored metadata,
provenance, diagnostics and generated build summaries. Cached artifact bodies
remain the exact downloaded bytes. This cache is private build data, not encrypted
storage; native and Node publish files with owner-only POSIX permissions.
Windows uses the host ACL policy. Protect the directory with host filesystem permissions.

Online hits and offline builds require the same supplied credential and recheck
content integrity. They do not contact the server to reauthorize, so server-side
revocation is not checked on cache hits. Remove the relevant cache when revocation
must take effect locally. `--offline` never performs a credential challenge or
network request. A changed/missing identity produces `offline-miss`; 401/403
produce `authentication-required` with the HTTP status, and concealed 404s retain
the provider's missing-resource code. Response bodies and secret values are not
included in authentication diagnostics.

`mise run test:http` runs controlled authenticated npm, Maven and GitHub builds on
native and Node, including all build input positions, same-origin and cross-origin
redirects, missing/invalid/insufficient credentials, redaction and offline cache
isolation. Portable policy tests run on all four backends. Wasm default acquisition
remains `unsupported-transport`; supplied transports can use the portable policy.
