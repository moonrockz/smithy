# The Smithy language tour

The tour teaches the Smithy IDL in small lessons at `/tour/`. Each lesson has a model that the reader edits in
the browser. The Findings tab shows the validation events, and the output tab shows a conversion of the model.
Every claim of a lesson is a checked case.

## Layout

```
site/tour/lessons/NN-<slug>/
  lesson.json
  lesson.md
  files/                      the starting files (at least one)
  cases/start/expect.json     the case of the starting files (required)
  cases/<case>/expect.json    one more case
  cases/<case>/files/         the files of the case (optional)
```

- Lesson numbers start at 01 and have no gap. The folder name is `NN-<slug>`, and `<slug>` is the `slug` of
  `lesson.json`. Two lessons cannot have the same number or the same slug.
- `lesson.json` has the keys `slug`, `title`, `section`, `spec`, and optionally `output` and `selector`.
  Another key is an error. `section` groups consecutive lessons on the contents page. `spec` is the link to the
  smithy.io section that the lesson teaches. `output` is one of `JsonAst`, `Idl`, `Selector`, `JsonSchema`,
  `OpenApi30`, `OpenApi31` or `OpenRpc`. `selector` is the selector for the `Selector` output, and is an error
  with another output.
- `lesson.md` starts with the line `# <title>`, with the `title` of `lesson.json`.
- A case runs the starting files with its own `files/` on top. A case file replaces a starting file of the same
  name, or adds a new file.
- A lesson file is directly in `files/` or in `cases/<case>/files/`. A sub-folder there is an error. The name of
  a lesson file must end in `.smithy`, because the playground core reads every file as IDL. (Java picks the
  format by the extension. Remove this rule when the core does the same.)
- The loader skips every name that starts with `.`, such as `.DS_Store`.
- `expect.json` has `events` and, optionally, `output_contains` or `blocked`. Another key is an error.
  - `events` lists the expected findings, each as `id|SEVERITY|shape`. `SEVERITY` is `WARNING`, `DANGER` or
    `ERROR`. A finding with no shape has `-` in its place, for example `Model|ERROR|-`.
    The list is the complete list. An empty list says that the case has no finding of these severities.
    `ERROR` and `DANGER` stop the output (`Severity::blocks_output` in `tour/model`).
  - `output_contains` lists strings (needles). Each string must be a substring of the output text of the case.
    An empty string is an error, because it matches every output.
    A lesson that has an `output_contains` needs an `output`.
    Its `events` must have no `ERROR` and no `DANGER`, because the output does not run for a model with those
    events. When the output has more than one file, the check joins the text of the files with a newline.
  - `blocked` is a text that the reason of a blocked output must contain, for example
    `"blocked": "I found no service with a protocol trait"`. The check sends the transform and requires a blocked
    output whose reason is not the model errors. A lesson that has a `blocked` needs an `output`. The case cannot
    have `output_contains`, and its `events` must have no `ERROR` and no `DANGER`.

## The two checks

Run both with:

```bash
mise run tour:check
```

This runs the tests of `site/tour/check` with the native target. It needs no bun, no Java and no browser. CI runs
the same task in the job `tour`. The tests run with `site/` as the working directory.

**Level 1** (`lessons_test.mbt`). For each case, the check validates the files with the playground core
(`@core.handle`) and the request `@core.lesson_validate`. For a lesson with an OpenAPI output, the model loads with the
bundled OpenAPI protocol definitions, as the transform loads it, so `@restJson1` resolves. For another lesson, it loads
without them. The check keeps only the findings with the severity `WARNING`, `DANGER` or `ERROR`, sorts them, and
requires them to be equal to the sorted `events` of `expect.json`. Then, for a case whose output runs, it checks
each needle of `output_contains` against the converted output.

**Level 2** (`reference_test.mbt`). The Java reference of Smithy gives the same findings for the same files. The
results are committed in `site/tour/reference-events.json`, with the `reference_sha` of the `smithy-lang/smithy`
commit that made them. For each case, the check:

1. requires a fresh reference result. The digest in the file must match the case files. The result has a
   reference JSON Schema if and only if the lesson output is `JsonSchema` and the reference events have no
   `ERROR` and no `DANGER`;
2. requires the events of the playground core to be equal to the reference events (after the allow list);
3. for a lesson with the output `JsonSchema`, requires the JSON Schema of the playground core to be equal to the
   reference JSON Schema (after the allow list).

The check also fails for a reference result of a case that does not exist.

### Write the reference results

Run this after you add or change a case, or change the output of a lesson:

```bash
mise run reference:tour [-- <smithy checkout>] [--check]
```

The task runs `scripts/reference-tour.mbtx`. It needs a JDK (`javac` and `java`) and `curl`. The checkout is a
checkout of `smithy-lang/smithy` at the commit `reference_sha`. The default is `.dev/out/reference-smithy`. The
script verifies every Java source file against the GitHub tree of that commit, compiles the sources with a small
harness, and writes `site/tour/reference-events.json`. Generated code and classes stay in
`.dev/out/reference-tour`. With `--check`, the script writes to a temporary file and fails when the committed file
is different. The script gives `reference_sha` to the harness as an argument, and the harness writes it into the
file. To change the commit, change `reference_sha` in `scripts/reference-tour.mbtx` and in
`site/tour/check/reference_test.mbt` together. A test requires it to be the commit in `pkgs/smithy/PRELUDE_SHA`,
the commit of the vendored prelude and of the other reference scripts.

## The allow list

`site/tour/reference-allow.json` lists the known differences between the playground core and the Java reference.
It is a JSON array. Each entry has:

- `case`: `<lesson folder>/<case>`
- `kind`: `event` or `json_schema`
- `reason`: why the two differ
- `issue`: a beads issue id, `smithy-` followed by lower-case letters, digits and dots (for example `smithy-2qe.4`)

A `kind` of `event` also has `event` (`id|SEVERITY|shape`) and `side`. `side` is `ours` or `reference`. The entry
removes one copy of the event from the named side before the comparison. Use `ours` when only our result has
the event, and `reference` when only the reference has it.

A `kind` of `json_schema` has `pointer` (a JSON pointer, RFC 6901) and no `side`. A `side` on this kind is an
error. The entry removes the value at the pointer from both JSON Schema documents. The entries of one case
apply in the order of the file, so a pointer sees the documents after the entries before it. For example, after
an entry removes `/a/0`, the item that was at `/a/1` is at `/a/0`.

Rules that the tests enforce:

- An entry that removes no difference fails the check (a stale entry). Delete it when the difference is fixed.
- An entry needs a valid issue and a reason that is not empty.
- The `lesson.md` of the entry's lesson must contain the text `> **Reference difference:**`. The test checks only
  that this text is present.

Writing rule: after that text, state the difference for the reader.

A difference from the Java reference is never hidden. Fix the playground core when it is wrong. Add an entry only
for a difference that is known and tracked.

## Write a lesson

Write `lesson.md` in ASD-STE100 Simplified Technical English:

- Use short sentences, the active voice, and one word for one thing.
- A lesson has about one screen of text.
- A lesson makes sense alone. Do not depend on the text of an earlier lesson.
- Link to the smithy.io section that the lesson teaches (`spec` in `lesson.json`).
- Link to another lesson by the path of its `lesson.md`, for example `../04-shape-ids/lesson.md`. The site
  opens the page of that lesson, and the link also works on GitHub. A test of `site/tour/check`
  (`links_test.mbt`) fails on a link into `site/tour/lessons` that does not open a lesson page.
- Every claim of the text is a case. When the text says that the Findings tab shows an error, add a case with
  that error in `events`. When the text says what the output contains, add a needle.
- Never change an expectation to make a check pass. When the playground core is wrong, fix the core or record
  the difference on the allow list.

To add a lesson, number it with the next free number, add the files above, run `mise run reference:tour`, and
then run `mise run tour:check`.

## How the site uses the tour

The pre-render reads `site/tour/lessons` from the `--content` directory of the build and writes `/tour/` (the
contents) and `/tour/<slug>/` (one page for each lesson). The lesson page runs in the browser through the
tour bundle; see `site/README.md`.

| Package | Job |
|---|---|
| `tour/model` | the lesson and tour types, the event key (`EventKey`, `Severity`), the case id (`CaseId`) and the digest |
| `tour/source` | reads the lessons folder and checks its rules |
| `tour/lesson` | the state of a lesson page (`Model`, `update`) and its view |
| `tour/ui` | js: mounts the lesson page, runs the editors, the Worker and the timers |
| `tour/editor` | JavaScript: the entry `main.js` of the bundle |
| `tour/check` | native: the tests of the two checks |

### The lesson page panes

The right-hand column of a lesson page has two panes: the editor above, and the output with the Findings tab
below. Each pane header has an expand button (class `tour-expand`, `aria-pressed`). "Expand the editor" or
"Expand the output" makes that pane fill the column. The name of a button never changes; `aria-pressed` is
`true` on the button of the expanded pane, its tooltip then reads "Show both panes", and a press gives the split
view back. The layout is the `Layout` value of the lesson model (`Split`, `EditorOnly`, `OutputOnly`). A pane
that is not shown stays in the DOM and has `display: none`, because the editors own their elements. Reset keeps
the layout. After a change of layout the page makes the editors measure their elements again (the `Remeasure`
effect). A page that adds panes, such as a Diff pane, keeps this control.
