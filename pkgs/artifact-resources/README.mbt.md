# Artifact resources

`moonrockz/artifact-resources` loads declared binary or text resources from
entry trees. It has no Smithy dependency. The root package reads ZIP/JAR bytes
and host-supplied directory entries without filesystem or network access.
`moonrockz/artifact-resources/local` provides filesystem acquisition.

## Independent library use

```mbt check
///|
test {
  let tree = @resources.EntryTree::directory(
    ["messages/hello.txt"],
    _ => b"hello",
    "memory-directory",
  )
  let loaded = @resources.load_resources(tree, [
    { name: "greeting", path: "messages/hello.txt", },
  ])
  assert_eq(loaded[0].name, "greeting")
  assert_eq(loaded[0].text(), "hello")
}
```

Use `EntryTree::zip(bytes, origin)` for ZIP32/JAR input. It supports stored and
deflated entries, verifies CRC-32 and uncompressed size when reading, and
records `digest` as `sha256:<hex>` over the complete archive bytes. ZIP64,
encrypted and multi-disk archives are unsupported. `open_zip(path)` opens a
nested archive while retaining its parent's provenance.

`entries()` lists physical file paths in sorted order. `contains(path)` also
recognizes explicit ZIP directory entries, while reading requires a file.
`read(path)` returns
bytes, and `text(path)` additionally requires UTF-8. The directory constructor accepts an optional `entry_origin` callback so hosts
can retain native physical filenames while entry paths use logical slashes.
`Declaration` maps a
logical resource name to a physical entry path. `load_resources` preserves
declaration order and rejects repeated logical names. It never discovers or
executes code. Consumers own their discovery rules. Smithy retains its
`META-INF/smithy/manifest` discovery in `smithy-build::declared_models`.

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
relative paths. It opens directories, individual files and `.jar` archives.
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

It reads `examples/local/data/greeting.txt` inside this module through the
registered local provider. An optional argument selects another directory
containing `greeting.txt`.

## Limits and diagnostics

`Limits::new` defaults to 64 MiB archive bytes, 10,000 entries, 16 MiB per
entry and 256 MiB total expanded ZIP bytes or selected resource bytes.
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
| `invalid-archive` | Malformed or unsupported ZIP data |
| `integrity-failure` | Content size or CRC-32 mismatch |
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

## Backend support

| Package | wasm | wasm-gc | JS | native |
|---|---|---|---|---|
| Entry trees, ZIP reader, resources, provider registry | Yes | Yes | Yes | Yes |
| Local filesystem adapter | MoonBit filesystem host | MoonBit filesystem host | Node.js | Host OS |

The pure contracts run on all four targets. Filesystem acquisition requires
the corresponding host filesystem implementation. Raw Wasm files need the
MoonBit filesystem imports. Local loading makes no network requests.
Remote repositories, caching, tar/gzip and credential support are later
slices. Explicit selection configuration and glob discovery are also later
work. This module joins the repository's next normal shared release.
