# smithy site

The landing page and docs site at <https://moonrockz.github.io/smithy/>,
built with [rabbita](https://github.com/moonbit-community/rabbita).

The site is copied from the moonspec site (moonrockz/moonspec at commit
`9ea9a688c3a39d95c91a28b2a40bb5332e8786f5`).

## How the site uses the Smithy packages

`site/` is its own MoonBit module, `moonrockz/smithy-site`. It is not a member of the root `moon.work`,
it is not published, and `scripts/versions.mbtx` does not see it.

`site/moon.work` lists the site (`.`) and the Smithy packages it needs from the same checkout
(`../pkgs/smithy`, and the packages that one imports). `moon` finds this file first when you work inside
`site/`, so an import of `moonrockz/smithy` resolves to the checkout and never to mooncakes.io.
`site/moon.mod` imports `moonrockz/smithy@0.0.0`. A workspace member needs no real version, so a release
does not change this line. To import another Smithy package, add its directory to `site/moon.work` and
its name to `site/moon.mod`.
The footer shows `@smithy.version()`, which proves the mechanism.

## Commands

```bash
moon install moonbit-community/warren@0.4.5   # once
mise run site:dev     # build at base / and serve on http://localhost:8080
mise run site:check   # unit tests, build release + next, link check
```

`mise run site:build -- --content <repo dir> --channel release|next --site-root /smithy/ --release-version vX.Y.Z --ref <git ref> --out <dir>`
builds one version. The scripts are `scripts/site-*.mbtx`.

## Landing sample

`landing/sample/` holds the hero example: `order.smithy`, `order.json`, `command.txt` and `output.txt`. The page text
in `shell/landing_sample.mbt` must equal these files (a `prerender` test checks it), and
`scripts/test-cli.mbtx` runs the command with the built CLI and requires `output.txt`. When the CLI output
changes, update the four files and the constants together.

## Packages

| Package | Job |
|---|---|
| `route` | Route ADT, base paths |
| `content` | page manifest (publish allowlist, sidebar order) |
| `highlight` | code token scanner |
| `markdown` | cmark AST to document IR, heading ids, TOC, link rewriting |
| `search` | search entries, query, excerpts |
| `data` | site configuration and page data (JSON in `<meta name="smithy-data">`) |
| `shell` | the rabbita component: model, update, views |
| `app` | browser entry: hydrates the pre-rendered page |
| `prerender` | native: renders every route, writes content copies and the search index |
| `linkcheck` | native: checks links, routes and the search index of a build |
