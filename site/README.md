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
| `playground/samples` | the example pickers: the models (`manifest`, with `chat-error.smithy`) and the transcripts (`transcript_manifest`, with `chat-findings.md`, the chat with the three findings of the mockup), and the typed transcript format and log preset |
| `playground/workbench` | the state of the page (`Model`, `update`, which returns `Effect`s) and its view; the pre-render and `ui` share the view |
| `playground/ui` | js: mounts the workbench in `#pg-app`, runs the effects: the editor, the Worker and the timers |
| `playground/worker` | js: the Web Worker. It reads a `Request` as JSON, calls `core.handle` and posts the `Response` |
| `playground/core` | the Smithy calls, with no browser (see below) |
| `playground/editor` | JavaScript: CodeMirror 6, the Smithy stream language (the token kinds of `highlight`) and bracket folding |

The Validate list shows at most 200 rows (`MAX_LISTED`). With "Group repeats" (`#pg-group`, on by default; the
browser keeps the choice in `localStorage` under `smithy-playground-group-repeats`), the diagnostics with the same
severity and code at the same place are one row, with their count and the other messages behind a disclosure
(`group_diagnostics`). The text of a row can be selected and copied: a click on a row moves the cursor unless it
ends a text selection, and its Go button does the same from the keyboard. The list shows the names between
backticks and the absolute shape IDs of a message as code (`message_parts`).

The Transform and Transcript tabs have a fold button (`#pg-fold`) at the end of the tab row. It folds their
controls away, so that their code view starts on the same pixel row as the model editor: the model header and the
tab row have one height (`--pg-head`). While a tab is folded, the tab row keeps Run (`#pg-run-folded`), or Step
and Run all (`#pg-step-folded`, `#pg-runall-folded`). A notice that the reader must see (a refused, stopped or
failed request, or a model that a transcript check cannot use) opens the controls when it appears; the reader
can fold them again. The browser keeps the folds in `localStorage` under `smithy-playground-folded`. The results
have a status bar (`.pg-rstatus`) that mirrors the one of the model editor, with a summary of the shown tab. When the
shown output or transcript check is older than the editors, it says so (`.pg-stale-tag`), because folded controls
hide the notice. In the Validate list, Go always moves the cursor; a click on the text does not when it ends a
text selection.

The Worker runs one request at a time (a Validate, a Transform or a transcript request). A change or a button
while a request runs waits for it. When it ends, a Run of the Transform tab goes first, then a Step, Run all or
Reset of the Transcript tab, then the newest text, then the next group of a Run all. So a long Run all does not
stop the Validate tab. The Transform tab keeps its output editor in the page at all times (`#pg-output`), and the
page text of the files stays in `ui`, not in the workbench model.
A `Blocked` response has a `kind` (`ModelErrors` or `Other`), so that the tab shows its own copy only for model
errors. `Transformed` has the converter `warnings`, each as the CLI prints it.

The Transcript tab lists the `@jsonRpcProtocol` structures that `Diagnostics` gives (a model with errors keeps
the list of the last model that assembled). Step sends `TranscriptStart`, then `TranscriptStep` of one entry; Run
all sends `TranscriptStep` in groups of 250 entries (`RUN_GROUP`), so the list fills as the findings come. Each
`TranscriptProgress` gives only what is new: every entry at the start, then the new findings and the number of
checked entries, and the workbench appends them. A JSONL log needs a version (the CLI `--version`) and a log
preset (`LogPreset`: `DirMessage` with a `dir` value for each peer, or `Raw` with a sender, the CLI
`--log-preset`, `--direction` and `--sender`). A change of the model, the transcript or a setting after the
start makes the check old, and the next Step or Run all starts again. A list of more than 200 entries shows the
150 entries near the last checked entry and the first 50 entries with findings, so a log of 20,000 lines does not
stop the page. The workbench compares a `Log` of entries by its revision only.

`scripts/site-build.mbtx` builds the two bundles: `moon build --target js --release` compiles `ui` and
`worker`, then `bun build` writes `<out>/playground/ui.js` (from `playground/editor/main.js`, which imports the
editor and then the MoonBit script) and `<out>/playground/worker.js`. The pre-render reads the samples from
`--content` and puts them in the site data of the playground page: the models and the transcripts of the pickers.

The page sends Validate 250 ms after the last change. Only one request runs at a time: a change while one runs
waits, and the newest text goes when that request ends. Each request has a new `seq`. The page uses only the
answer to its newest request, and only while the text is the text that it checked; until then the previous
result stays, marked as checking, and its rows do not move the cursor. While a request runs, the status bar shows
a turning ring, what the Worker does and the seconds (`Ticked` each second), and from 5 seconds on the limit
(`· 6 s of 10 s`); the Transform tab shows the same next to its notice. The ring is CSS only, has no text and fades
instead of turning when the reader asks for reduced motion. When the Worker gives no answer in 10
seconds, the page ends it, starts a new one and says so. When the Worker stops with an error, the page starts a
new one at once and says that the check failed. The page loads `ui.js` and the Worker with the git ref of the build as the query
(`?v=<ref>`, `SiteConfig::versioned`): Pages caches each file for 600 seconds, and a new page must not run an old
Worker. A Worker that cannot read a request answers `Blocked` with `seq` -1; that answer, or an answer that the
page cannot read, shows at once "The page and its checker do not match. Reload the page." (`#pg-mismatch`), and no
new Worker starts. The time of a check grows linearly with the shape count: a model of 1 MB takes about 3 seconds
on a laptop, so the limit stops only a model of several MB.

### Share links, Download and "Open in playground"

Share link writes the state of the page in the URL fragment: `#v1.` and the base64url text of the deflated JSON of
a `ShareState` (`playground/samples`): the model and the transcript texts, the tab, the output and selector of the
Transform tab, and the Transcript settings (protocol, format, `--complete`, the log preset and the version). The
state is in the fragment, so no server sees it. The page copies the full URL with the clipboard API and sets the
address bar with `history.replaceState`. A browser without the clipboard API gets the URL in a box under the
toolbar (`#pg-share-url`). Download saves `model.smithy`, and `transcript.md`, `.json` or `.jsonl` on the
Transcript tab, as local files.

Opening a link (`opened_by` in `playground/ui`) restores the state, and the pickers show it as "Shared link".
Settings fit the model after the first check: a protocol that the model does not have gives the first protocol of
the model with its version and peers. A fragment that the page cannot read shows a message in
`#pg-share-status` and opens the default example. These fragments give that message:

| Fragment | Reason |
|---|---|
| a format other than `v1` (for example `v2.`, from a newer `/next/` build) | "it has the format v2, and I know only v1" |
| corrupt text, a character that is not base64url, a bad deflate stream, JSON that is no state | the reason of `decode_share` |
| more than 8,000 characters (`MAX_SHARE_LENGTH`) | the length, and the limit |
| a state that unpacks to more than 2,097,152 bytes (`MAX_STATE_BYTES`) | the limit; checked while the inflate runs |

A state too large for a link (`share_state_problem`, or a link over 8,000 characters) shows the same reason on the
Share link button and says to use Download. On the release channel, a build from before the playground has no
`/playground/` page: the link then gives the 404 page of the site. A build with the playground but with an older
format also shows the message of the table. A link pasted in the address bar of an open playground tab (a
`hashchange`) opens in place with no page load (`Model::reopen`). When an editor differs from the text that the page
loaded or shared last, a bar asks "Open the new link? You will lose your changes." (`Open`, `Keep my changes`). A link
that cannot be read keeps the page and shows the message. The fragment that the page wrote itself is ignored. The
inflate stops at `MAX_STATE_BYTES` (`bounded_inflate`, `Inflater::step` with a 64 KB buffer).

An example page (`/examples/<dir>`) shows "Open in playground" when `playground/samples` has a model under
`examples/<dir>/` (`example_state`). The pre-render computes the fragment of each example once
(`with_playground_links` in `prerender`) and puts all of them in the site data of every page: a click from
`/examples/` to an example page loads no new page, so the first page must have them. The button is a plain link:
`/playground/#v1...`. It needs no script. A fragment over the limit fails the build.

## Tour

`/tour/` is the Smithy language tour: lessons with a model that the reader edits. The lessons are in
`tour/lessons`, and `tour/README.md` explains the format of a lesson, the two checks and the allow list. The
pre-render reads the lessons from the `--content` directory and writes `/tour/` and `/tour/<slug>/`.

A lesson page loads `tour/ui.js` and uses the playground Worker (`playground/worker.js`) to validate and convert the
model. The tour glue is the MoonBit package `tour/ui` (js), with `tour/lesson` for the page state and view and
`tour/editor/main.js` as the entry. `scripts/site-build.mbtx` compiles `tour/ui` with the playground packages
(`moon build --target js --release`), and then `bun build tour/editor/main.js` writes `<out>/tour/ui.js`. The
playground and the tour share the editor code of `playground/editor`. The server serves `tour/ui.js` as a static
file, as it does `playground/ui.js`, and `?v=<ref>` keeps a new page from running an old script.

`mise run tour:check` checks every lesson case against the playground core and the committed Java reference
results. CI runs it as the job `tour`.

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
| `playground/core` | pure MoonBit core of the playground: requests, responses, transcript stepping and share links (`encode_share`, `decode_share`; native and js tests) |
| `playground/examples_check` | native: tests of the playground core against `examples/json-rpc/`, including the comparison with `run_transcript`, and of the samples of the picker |
| `playground/samples`, `playground/workbench`, `playground/ui`, `playground/worker` | the playground page (see Playground) |
| `tour/model`, `tour/source`, `tour/lesson`, `tour/ui`, `tour/check` | the language tour (see Tour) |
| `prerender` | native: renders every route, writes content copies and the search index |
| `linkcheck` | native: checks links, routes and the search index of a build |

## Build arguments are a contract

`scripts/site-pages.mbtx` on main builds the release channel by running the tag's own `scripts/site-build.mbtx`
in a worktree of that tag. A new main therefore calls an old `site-build`. Keep the arguments of `site-build`
backward-compatible: add optional flags, and never rename or remove one.
