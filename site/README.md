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
mise run site:check   # unit tests, build both channels as Pages does, link check
mise run site:pages -- --out _site   # only the two channel builds and their link checks
```

`mise run site:build -- --content <repo dir> --channel release|next --site-root /smithy/ --release-version vX.Y.Z --ref <git ref> --out <dir>`
builds one version. The scripts are `scripts/site-*.mbtx`.

## Channels and deploy

Each channel is a full build of its own checkout (`scripts/site-pages.mbtx`, `mise run site:pages`):

| URL | Build |
|---|---|
| `/smithy/` | The newest stable tag `vX.Y.Z`, when that tag contains `site/moon.mod`: the tag's own `site/`, built in a git worktree, channel release. |
| `/smithy/` (no such tag yet) | `main`, channel next, with the "unreleased" banner. |
| `/smithy/next/` | `main`, channel next. Always. |

No tag contains `site/` yet, so today both URLs show `main`. After the first release that contains `site/`, the
root shows that release. While no release has a site, both outputs are built with `--no-release`: the version
picker shows only "next", the banner says that no release has docs yet, and no page links to a release.

A missing fixed docs source (see `@content.fixed_sources()`) fails the build of either channel. The link check
runs on each output.

`.github/workflows/site.yml` runs the build and deploys. It is not part of `ci-ok`, so a failed deploy on `main`
shows on the commit and does not block a merge.

| Trigger | Build and link check | Deploy |
|---|---|---|
| `pull_request` that changes a site input | yes, on the merge commit | no |
| `push` to `main` that changes a site input | yes | yes |
| `workflow_dispatch` | yes | yes |
| `workflow_call` from `release.yml` (real release only) | yes | yes |

A site input is `site/**`, `docs/**`, `examples/**`, `apps/smithy/README.md`, `pkgs/**/README.mbt.md`,
`scripts/site-*.mbtx` or `.github/workflows/site.yml`. `release.yml` calls `site.yml` after the `release` job
and never on a dry run, a pull request or the nightly run. The tag that the release job creates comes from
`GITHUB_TOKEN`, which starts no workflow, so the call is how a release reaches Pages.

Maintainer step, once: in the repository, open Settings, then Pages, and set Source to "GitHub Actions". The
workflows never change repository settings. Until then the deploy job fails.

Maintainer step, once: open Settings, then Environments, then `github-pages`, and under "Deployment branches and
tags" add the tag rule `v*`. The release workflow can run on a tag ref, and the default `github-pages` environment
lets only the default branch deploy, so a run on a tag would be refused without the rule. To recover from a refused
deploy, run `gh workflow run site.yml --ref main`.

## Examples pages

`/examples/` lists the directories of `examples/` that have a `README.md`, as cards. `/examples/<dir>` shows that
README, then the other files of the directory with GitHub links at the build's ref. The prerender reads the
directories (`prerender/examples.mbt`), and `content/examples.mbt` keeps those with a README. One line for each
card is in the `summaries` table of `content/examples.mbt`: add a line when you add a README. A README link to
another example's README stays on the site.

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
