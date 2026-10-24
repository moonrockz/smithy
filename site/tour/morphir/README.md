# Morphir sources for the tour

These files are vendored from [finos/morphir](https://github.com/finos/morphir) at commit
`ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409`. The tour lessons on Morphir use them.

- `upstream/` holds the files at their paths in finos/morphir: the Morphir IR v4 JSON schema, the v4 and v3
  IR examples, the type and name features, and the naming conformance fixture.
- `inventory.json` lists each file with its Git blob SHA at the pinned commit.
- `LICENSE` and `NOTICE` are copies of the upstream files.

`upstream/website/static/schemas/morphir-ir-v4.json` is the generated twin of the YAML schema. The lesson texts
cite the YAML lines at the pinned commit.

## Licence

Apache-2.0. Copyright belongs to FINOS and the Morphir contributors. See `LICENSE` and `NOTICE`.

## Do not edit

Do not edit these files. `mise run tour:vendor:morphir` checks each file against the blob SHA of the pinned
tree and fails on any difference.

## Refresh

1. Change `morphir_sha` in `scripts/vendor-morphir.mbtx`.
2. Check out that commit in `.dev/out/finos-morphir`.
3. Run `mise run tour:vendor:morphir`.
4. Run `cd site && moon test --target native -p moonrockz/smithy-site/tour/check --update`.
5. Review the snapshot diff.
6. Run `mise run tour:check`.
7. Ask the owner to review.
