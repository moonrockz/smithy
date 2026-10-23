# smithy site

The landing page and docs site at <https://moonrockz.github.io/smithy/>,
built with [rabbita](https://github.com/moonbit-community/rabbita).

The site is copied from the moonspec site (moonrockz/moonspec at commit
`9ea9a688c3a39d95c91a28b2a40bb5332e8786f5`).

## How the site uses the Smithy packages

`site/` is its own MoonBit module, `moonrockz/smithy-site`. It is not a member of the root `moon.work`,
it is not published, and `scripts/versions.mbtx` does not see it.

`site/moon.work` lists the site (`.`) and the Smithy packages it needs from the same checkout
(`../pkgs/smithy`, `../pkgs/smithy-validation`, the JSON Schema, OpenAPI and OpenRPC converters, and the packages that those import). `moon` finds this file first when you work inside
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
mise run site:test:browser           # browser tests against _site (tests/browser/README.md)
```

The site needs the npm packages of `package.json`, as `bun.lock` pins them: CodeMirror for the playground and
Playwright for the browser tests. `site:build` runs `bun install --frozen-lockfile` itself. Bun and Lightpanda
are pinned in `site/mise.toml`, which mise reads only in `site/`, so the other CI jobs do not install them. The
site scripts run bun and Lightpanda with `site/` as the working directory. Run `mise trust` and `mise install`
in `site/` once.

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

The version picker and the banner link to the same page in the other version. After hydration, the page asks the
other version for that URL with one `GET`. On a 404 the links go to the docs index (docs pages) or the home page. The
choice is made at run time, because the release can come from an older tag.

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
`scripts/site-*.mbtx`, `.github/workflows/site.yml`, the mise configuration, the setup action, or a Smithy package
that the site compiles (the members of `site/moon.work`). After the build, the workflow runs the browser tests.
`release.yml` calls `site.yml` after the `release` job
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

## Playground

`/playground/` runs Smithy in the browser. The page is pre-rendered with the site nav and an empty
workbench, and it is the only page that loads `playground/ui.js`. A link into or out of the playground loads
the new page, so that no other page runs the playground script.

| Part | Job |
|---|---|
| `playground/samples` | the example picker: titles and repository paths (`manifest`), and `chat-error.smithy` |
| `playground/workbench` | the state of the page (`Model`, `update`, which returns `Effect`s) and its view; the pre-render and `ui` share the view |
| `playground/ui` | js: mounts the workbench in `#pg-app`, runs the effects: the editor, the Worker and the timers |
| `playground/worker` | js: the Web Worker. It reads a `Request` as JSON, calls `core.handle` and posts the `Response` |
| `playground/core` | the Smithy calls, with no browser (see below) |
| `playground/editor` | JavaScript: CodeMirror 6, the Smithy stream language (the token kinds of `highlight`) and bracket folding |

`scripts/site-build.mbtx` builds the two bundles: `moon build --target js --release` compiles `ui` and
`worker`, then `bun build` writes `<out>/playground/ui.js` (from `playground/editor/main.js`, which imports the
editor and then the MoonBit script) and `<out>/playground/worker.js`. The pre-render reads the samples from
`--content` and puts them in the site data of the playground page.

The page sends Validate 250 ms after the last change. Only one request runs at a time: a change while one runs
waits, and the newest text goes when that request ends. Each request has a new `seq`. The page uses only the
answer to its newest request, and only while the text is the text that it checked; until then the previous
result stays, marked as checking, and its rows do not move the cursor. When the Worker gives no answer in 10
seconds, the page ends it, starts a new one and says so. When the Worker stops with an error, the page starts a
new one at once and says that the check failed. The Smithy library needs minutes for a model of 1 MB
(the time grows with the square of the shape count), so such a model stops at that limit.

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
| `playground/core` | pure MoonBit core of the playground: requests, responses, transcript stepping and share links (native and js tests) |
| `playground/examples_check` | native: tests of the playground core against `examples/json-rpc/`, including the comparison with `run_transcript`, and of the samples of the picker |
| `playground/samples`, `playground/workbench`, `playground/ui`, `playground/worker` | the playground page (see Playground) |
| `prerender` | native: renders every route, writes content copies and the search index |
| `linkcheck` | native: checks links, routes and the search index of a build |

## Build arguments are a contract

`scripts/site-pages.mbtx` on main builds the release channel by running the tag's own `scripts/site-build.mbtx`
in a worktree of that tag. A new main therefore calls an old `site-build`. Keep the arguments of `site-build`
backward-compatible: add optional flags, and never rename or remove one.
