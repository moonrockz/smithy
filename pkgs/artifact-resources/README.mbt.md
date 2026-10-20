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
Remote repositories, caching and credential support are later
slices. This module joins the repository's next normal shared release.

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
