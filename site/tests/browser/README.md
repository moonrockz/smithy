# Browser tests of the site

These tests load the built site in a headless browser. Playwright (pinned in `site/bun.lock`) drives
[Lightpanda](https://github.com/lightpanda-io/browser) 1.0.1 (pinned in `site/mise.toml`) through
`chromium.connectOverCDP`. A check that Lightpanda cannot run uses Playwright's own Chromium. The table below
lists each such check and why.

## Run the tests

```bash
mise run site:pages -- --out _site   # build both channels, as GitHub Pages serves them
cd site
mise trust && mise install           # once: bun and Lightpanda from site/mise.toml
bun install --frozen-lockfile
bunx playwright install chromium     # once, for the Chromium checks
bun run test:browser                 # or, from the repository root: mise run site:test:browser
```

`playwright.config.js` starts two servers: `moonx scripts/site-dev.mbtx --serve _site --base /smithy/`, which
serves `_site` under `/smithy/` as GitHub Pages does, and `lightpanda serve --load-resources worker` (in `site/`,
where the mise shim finds the Lightpanda of `site/mise.toml`). Lightpanda
does not run a Web Worker without `--load-resources worker`. Outside CI, a server that already runs on the same
port is used. The environment variables `SITE_DIR`, `SITE_PORT` and `LIGHTPANDA_CDP` change the defaults
(`_site`, 8091, `http://127.0.0.1:9222`).

A file `*.lightpanda.spec.js` runs in the project `lightpanda`, and a file `*.chromium.spec.js` runs in the
project `chromium`.

## What runs where

| Test | Browser |
|---|---|
| `probe`: a Web Worker runs the Smithy library; CodeMirror renders its DOM and reads a change of it; the clipboard API | Lightpanda |
| `smoke`: the default sample shows one error, the diagnostic moves the cursor, the fix gives the valid state (both channels) | Lightpanda |
| `half-typed`: an unbalanced brace, a deleted `$version`, an empty editor, a burst of edits (review focus 1) | Lightpanda |
| `worker`: a Worker that does not answer in 10 seconds is ended and a new one starts; a Worker that stops with an error is replaced at once, once | Lightpanda |
| `transform`: JSON AST of the valid sample (first line `{`, `"smithy": "2.0"`), a selector, the blocked copy for model errors, the reason of the library for another block, the OpenAPI note, OpenRPC | Lightpanda |
| `transcript`: the chat variant gives TypeMismatch, RequiredMember and MissingResponse under their entries; Step one entry at a time and Reset; the editor log with its version and preset (the summary of the README); the empty states for a model with errors and a model with no protocol; a change after the check | Lightpanda |
| `typing`: key input fixes the model; Ctrl-Shift-[ and ] fold and unfold; token colors | Chromium |
| `large`: a pasted 1 MB model, typing while the Worker runs, the stopped check (review focus 2); typing bursts on a 100 KB model end in its result | Chromium |
| `transform` (Chromium): Copy through the clipboard API, Download, OpenAPI for a model that Validate marks with warnings shown, an old output after a change, no page scroll at 360 and 1440 px with an output | Chromium |
| `transcript` (Chromium): a log of 20,000 lines with Run all while typing in the model editor (review focus 2: frame gaps, findings before the end, at most 200 rows, the page does not scroll); no page scroll at 360 and 1440 px with findings; a click on the line of an entry | Chromium |
| `share` (Lightpanda): a share round trip restores the model, the tab and every Transcript setting, and the Transform output and selector; a protocol that the model lacks is fitted; a corrupt, foreign-format, over-long and over-size link each show a message and the default example (review focus 5); a link from `/next/` opens on the root; the "Open in playground" link decodes to the model of the example. The clipboard is missing, so the page shows the link | Lightpanda |
| `share` (Chromium): Share link copies the URL through the clipboard API and sets the address; a pasted link loads; the box without a clipboard; Download of the model and the transcript; no page scroll at 360 px with a message, a box and the example button | Chromium |
| `layout`: no page scroll at 360 px, stacked and side-by-side panes, links into and out of the playground | Chromium |

Why some checks run on Chromium:

- **Key input.** Lightpanda 1.0.1 sends no key input to a `contenteditable` element: `keyboard.type`,
  `keyboard.insertText` and `press` do not change the CodeMirror document. The Lightpanda tests change the text
  in the DOM of the editor instead, as a native text input does, and CodeMirror reads the change back. That
  only reaches the lines that the editor shows. So the tests of typing, folding by key and a 1 MB paste run on
  Chromium.
- **Clipboard.** `navigator.clipboard` is undefined in Lightpanda 1.0.1. The `probe` test checks this, and it
  fails when Lightpanda gets the API, so that the clipboard checks can move there. The 1 MB paste uses the
  clipboard of Chromium.
- **Layout.** Lightpanda has no layout engine: widths, scroll widths and element boxes are not real. The
  360 px and 1440 px checks, and Playwright's `click` (which needs a box), run on Chromium. The Lightpanda tests
  click with `dispatchEvent("click")`.
- **Computed colors.** Lightpanda does not apply CodeMirror's style sheets to computed styles, so the token
  colors are checked on Chromium.

## A known Lightpanda quirk

Lightpanda fires `selectionchange` at once when CodeMirror sets the DOM selection inside its own update.
Browsers fire it later. CodeMirror then throws "Calls to EditorView.update are not allowed while an update is
in progress". It happens only while the editor has focus, and the change still applies. The Lightpanda tests
allow exactly this page error (`lightpandaQuirk` in `fixtures.js`); the Chromium tests allow no page error.
