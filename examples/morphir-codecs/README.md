# Morphir codec conformance sources

This directory holds the Smithy models of the Morphir IR v3 and v4 JSON representations and the pinned
authorities that they are checked against, for the
[versioned JSON codecs change](../../openspec/changes/add-versioned-json-codecs/design.html) (decision CONF-1).
[COVERAGE.md](COVERAGE.md) lists the supported releases, what the bundles check, the case results and the
recorded gaps.

## Models

- `model/morphir-v3.smithy` (`morphir.ir.v3`): the v3.0 root `IRFile30`, the v3.1 root `IRFile31` (adds Specs),
  every v3 node family and the `morphir-v3` profile (tag-first arrays, entry-array dictionaries in Elm order).
- `model/morphir-v4.smithy` (`morphir.ir.v4`): the root `IRFile`, every v4 node family and the profiles
  `morphir-v4` (compact canonical writer) and `morphir-v4-expanded` (expanded writer).
- `model/morphir-bundle.smithy` (`morphir.ir`): the `morphir` jsonBundle with the releases
  `[3.0.0,3.1.0)`, `[3.1.0,3.2.0)` and `[4.0.0,4.1.0)`, and `SupportedFormatVersion`.

The models name the scalar adapters of the `moonrockz/smithy-codec/morphir` package; a host registers them with
`@morphir.registry()`. Load the models with `@contract.loader()` (it knows the `smithy.serialization` traits).

| Directory | Repository | Commit | Role |
| --- | --- | --- | --- |
| `upstream/finos-morphir/` | [finos/morphir](https://github.com/finos/morphir/tree/5c5307d89f34d876e8f1ebf561ec55efbadf9fa0) | `5c5307d89f34d876e8f1ebf561ec55efbadf9fa0` | Fixture and v4 specification authority; v3.1 `Specs` extension |
| `upstream/finos-morphir-elm/` | [finos/morphir-elm](https://github.com/finos/morphir-elm/tree/bc99af69a8b24d391311fae3822a87eafef3c334) | `bc99af69a8b24d391311fae3822a87eafef3c334` | Historical v3 codec authority (the Elm JSON codecs) |

This pin is independent of the tour corpus in `site/tour/morphir`, which uses an older finos/morphir commit.

## Contents

- `upstream/<repository>/` holds each file at its path in the upstream repository:
  - finos/morphir: the format-version contract and its corpus, the naming corpus, the v3.1 notes, the v4 JSON
    profile and semantic model, the Morphir Compatibility Kit (MCK) IR cases for names, types, values, patterns
    and literals, definitions, distributions and versions, the v3 and v4 example artifacts, one MCK v4 library
    artifact, and the generated v3 and v4 JSON Schemas.
  - finos/morphir-elm: the v3 codec modules (`src/Morphir/**/Codec.elm`) and `FormatVersion.elm`.
- `inventory.json` gives the repository, the commit and the Git blob SHA of each vendored file.
- `cases.json` gives the expected outcome of each conformance case: a stable case ID, the file, the location
  (fence line, or JSON pointer and `input` pointer), `valid`, `invalid` (with the upstream diagnostic) or
  `other-node`, the Smithy `root` and `profile` that check it, the expected canonical `output`, and the `gap` of
  a case that the bundles do not pass yet (see COVERAGE.md).
- `LICENSE` and `NOTICE` are copies of the finos/morphir files. The finos/morphir-elm files are in
  `upstream/finos-morphir-elm/`.

`cases.json` lists only JSON and text fences. YAML fences, document trees, support-table parsing and
filesystem-name cases are out of scope. A case that is not in the upstream corpus, such as a negative case for a
duplicate member below the root, is written separately and does not go in `upstream/`.

The only upstream JSON fixture with a duplicate object member is
`format-version/root/1`: a root with two `formatVersion` members. It is a JSON string inside the
format-version corpus, so its bytes stay as written.

## Conformance run

```sh
mise run test:bdd
```

runs every entry of `cases.json` (tests/bdd/morphir_codecs_world_wbtest.mbt) and the scenarios of
tests/features/morphir-codecs.feature. A case with a `gap` must still fail, so a fixed gap must also be removed
from `cases.json` and COVERAGE.md.

## Licence

Apache-2.0. See `LICENSE`, `NOTICE` and `upstream/finos-morphir-elm/NOTICE`.

## Do not edit

Do not edit the files in `upstream/`, `LICENSE`, `NOTICE` or `inventory.json`. The bytes, number lexemes and line
endings must stay as they are upstream (`.gitattributes` stops line-ending conversion). To check them without
network access:

```sh
mise run morphir:codecs:vendor -- --check
```

The check fails on a changed, missing or extra file, on another pin, and on a `cases.json` entry whose file,
fence line, heading, JSON pointer or number lexeme does not agree with the vendored file. Add `--remote` to also
compare `inventory.json` with the pinned trees on GitHub.

## Refresh

1. Change the commit of the source in `scripts/vendor-morphir-codecs.mbtx`. Edit its `files` when an upstream path
   moves. The script removes `upstream/` and writes it again, so a path that leaves `files` leaves no file.
2. Check out that commit in `.dev/out/morphir-codecs/finos-morphir` and
   `.dev/out/morphir-codecs/finos-morphir-elm`, or give other directories with `--morphir DIR` and
   `--morphir-elm DIR`.
3. Run `mise run morphir:codecs:vendor`. It verifies each file against the pinned tree, writes the files and
   `inventory.json`, and then runs the check.
4. Update `cases.json` for added, removed or moved cases until the check passes. Do not change an expected outcome
   to agree with an implementation. Record a disagreement between authorities in a bead.
5. Change the pins in `openspec/changes/add-versioned-json-codecs/design.html` to agree.
6. Ask the owner to review.
