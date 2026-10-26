# Manual interoperability matrix

The manual workflow checks each caller and receiver language over each
transport. Three caller languages, three receiver languages, and three
transports give 27 combinations. Each combination runs `payment`,
`cancellation`, `errors`, and `refusals`. The full run checks 108 logs.

Use the **JSON-RPC interoperability matrix** workflow to check generator,
runtime, or transport changes across all three languages. It runs only through
`workflow_dispatch`. It does not change release or release smoke rules.
Normal CI checks generated golden files and the MoonBit POS to Python terminal
stdio path. Go compiler gates run in the manual workflow.

Before merging a JSON-RPC generator, runtime, or transport change, the maintainer
must get a passing full matrix result for that source. A local run with sealed
commands or this workflow can supply the result. A missing, failed, or stale
result blocks that change. The maintainer who requests the run owns failure
review and fixes.

## Run the workflow

Select a source branch in the GitHub Actions page, or run:

```shell
gh workflow run jsonrpc-matrix.yml --ref main
```

The workflow checks embedding and golden files, runs the language quality
gates, and builds each sample once. A Linux runner then executes all 27 combinations.
An independent Windows runner checks the MoonBit runtime and generated peers,
builds the MoonBit sample natively, and runs all four scenarios over stdio, HTTP
and WebSocket. These three Windows combinations add 12 checked logs. A Windows
binary must be built on Windows because a cross-built binary reads its arguments
wrongly. Windows uses the same pinned setup as the release build and calls the
MoonBit task scripts directly, without installing the other language toolchains.
The job fails if a scenario, receiver process, or transcript check fails.
Each checked log must meet the minimum message count for its fixed scenario.
Skipped and non-JSON log rows fail the run.
It also fails if any required build or language gate fails.

The job summary has one row per language and transport combination. The
`jsonrpc-matrix-<commit>` artifact has logs, checker results, command provenance,
and the pass/fail table. The Windows artifact is `jsonrpc-matrix-windows-<commit>`.
GitHub retains both artifacts for 14 days. A maintainer
must inspect a failed cell and its logs before using the result as evidence.
Both jobs must pass on the selected source before the result can support a
Windows compatibility claim. The manual workflow keeps these checks outside
normal PR CI. A failed runtime gate remains a job failure even when the generated
peer and scenario steps can still run to collect more evidence.

## Run locally

Run from the repository root after the language quality gates pass:

```shell
mise run jsonrpc:go:runtime -- --check
mise run codegen:go -- --check
mise run runtime:embed:check
mise run codegen:payment-terminal -- --check
mise run sample:build:moonbit
mise run sample:build:python
mise run sample:build:go
mise run test:jsonrpc:matrix
```

To run a subset, select a caller, receiver, or transport:

```shell
mise run test:jsonrpc:matrix -- --caller go --receiver python --transport http
```

Build commands write absolute command arrays to
`.dev/out/payment-terminal/commands/<language>.json`. They also seal the command
arguments, executable bytes, source fingerprint, and compiler version. Python
manifests name the installed package artifacts as well as the interpreter.
The seal excludes Python bytecode caches. The runner rejects a changed source,
command, or artifact. Build the selected languages again after a source change.
A local run with source changes names its base commit and marks the working
tree as changed. A clean workflow run names the checked source commit.

Each run replaces `.dev/out/jsonrpc-matrix/`. It writes `summary.md`,
`results.json`, and a directory for each selected combination. Each scenario
has a POS JSONL log, process output, and a checker result. A setup failure cannot
reuse a previous pass table. For network transports, a receiver can stop with status 0 after the caller
finishes. The runner stops a receiver that is still running. A crash or forced
kill fails the cell.

## Shared wire contract

HTTP uses `POST /rpc` and the `Smithy-Session-Id` header. A request gets a JSON
response or an SSE stream. SSE messages carry progress, callbacks, and the
final response. The caller sends a callback reply in a new POST. Notifications
and callback replies get HTTP 202. An unknown session gets HTTP 404.

WebSocket uses `/ws` and one message per text frame. Stdio uses
`Content-Length` framing. Peers ignore unknown stdio headers. Logs go to stderr
or a file. Each runtime uses the `dir-message` JSONL preset.

The runner checks the POS log with `send=pos` and `recv=terminal`. It uses the
shared scenario expectation files. Payment, cancellation, and error logs need
no findings. The refusal log must have the three declared findings and no
other errors. Exact decimal text and large integer IDs stay exact in the log
and the checker. Each scenario must end with no outstanding calls.
