# Validate JSON-RPC messages, batches and transcripts

This example checks JSON-RPC traffic against a Smithy model with `smithy validate rpc`.
It has three parts: single messages, batches and transcripts.

Run every command from the repository root. In this README, `smithy` stands for this prefix:

```shell
mise exec -- moon run apps/smithy --target native --
```

A check that passes prints nothing and exits with status 0. A check that finds an error exits with status 1.
A usage error exits with status 2.

## Single messages

`calculator.smithy` defines the service `example#Calculator` with `subtract` and `ping`.
`call.json` is a valid request. `invalid.json` passes a string where `subtrahend` needs an integer.

```shell
smithy validate rpc --version 2.0 --service example#Calculator --message examples/json-rpc/call.json examples/json-rpc/calculator.smithy
```

The command prints nothing and exits with status 0.

```shell
smithy validate rpc --version 2.0 --service example#Calculator --message examples/json-rpc/invalid.json examples/json-rpc/calculator.smithy
```

The command exits with status 1 and prints:

```text
examples/json-rpc/invalid.json/params/1: error[TypeMismatch] example#SubtractInput$subtrahend: I expected a integer value, but found string.
```

`responses.smithy` defines `example#Replies` for response checks. `reply.json` is a valid response to `subtract`:

```shell
smithy validate rpc --version 2.0 --service example#Replies --response examples/json-rpc/reply.json --method subtract examples/json-rpc/responses.smithy
```

The command prints nothing and exits with status 0.

## Batches

`batches.smithy` defines the service `batch#Api`. The files `batch-mixed.json`, `batch-replies.json` and
`batch-notifications.json` are the batch examples of the JSON-RPC 2.0 specification, section 7.

```shell
smithy validate rpc --version 2.0 --service batch#Api --batch --request examples/json-rpc/batch-mixed.json --response examples/json-rpc/batch-replies.json examples/json-rpc/batches.smithy
smithy validate rpc --version 2.0 --service batch#Api --batch --request examples/json-rpc/batch-notifications.json --no-response examples/json-rpc/batches.smithy
```

Both commands print nothing and exit with status 0. The second command checks that a batch of notifications has no response.

## Transcripts

A transcript is a conversation between the two peers of a protocol. The model names the peers with `@jsonRpcProtocol`.
`peers.smithy` defines the protocols `example.peers#EchoChat` (JSON-RPC 1.0) and `example.peers#Editor` (an LSP-like
protocol, JSON-RPC 2.0). `lifecycle.smithy` defines `example.lifecycle#Lifecycle`, a protocol with a session and states.

The folder `transcripts/` holds the transcripts as JSON, as Markdown (`echo.md`, `chat.md`, `editor.md`) and as JSONL logs.

```shell
smithy validate rpc transcript --protocol example.peers#EchoChat examples/json-rpc/peers.smithy examples/json-rpc/transcripts/echo.json
smithy validate rpc transcript --protocol example.peers#Editor examples/json-rpc/peers.smithy examples/json-rpc/transcripts/editor.json
smithy validate rpc transcript --protocol example.lifecycle#Lifecycle examples/json-rpc/lifecycle.smithy examples/json-rpc/transcripts/lifecycle-valid.json
```

These commands print nothing and exit with status 0.

Two transcripts have errors on purpose. Each has an `expect` list that names the findings. The command prints the
findings and exits with status 0, because the findings match the list. For example:

```shell
smithy validate rpc transcript --protocol example.lifecycle#Lifecycle examples/json-rpc/lifecycle.smithy examples/json-rpc/transcripts/lifecycle-violation.json
```

```text
examples/json-rpc/transcripts/lifecycle-violation.json:12:34: entry 0 host: error StateViolation: I expected method compile only in state ready; entry 0 from host sent it in state starting.
examples/json-rpc/transcripts/lifecycle-violation.json:15:39: entry 3 extension: error CapabilityNotAdvertised: I expected capability progress to be advertised before method progress; entry 3 from extension sent it, and no initialize result advertised it.
examples/json-rpc/transcripts/lifecycle-violation.json:17:34: entry 5 host: advisory CancelInactiveCall: I expected $/cancelRequest at entry 5 from host to name an active call from host; it names id 9, which is not active.
examples/json-rpc/transcripts/lifecycle-violation.json:18:39: entry 6 extension: error RefusalExpected: I expected an error reply to the refused call at entry 0; I found no integer error code.
examples/json-rpc/transcripts/lifecycle-violation.json:21:34: entry 9 host: error StateViolation: I expected method compile only in state ready; entry 9 from host sent it in state stopping.
```

`editor-negative.json` works the same way: it reports `UnsolicitedResponse` and two `MissingResponse` findings.
A transcript without an `expect` list exits with status 1 when it has an error finding.

### Logs

A JSONL log needs a preset that tells the command how to read each line. The log `editor.jsonl` has other lines
between the messages. The preset `dir-message` and the two `--direction` options map its direction values to the peers:

```shell
smithy validate rpc transcript --protocol example.peers#Editor --version 2.0 examples/json-rpc/peers.smithy examples/json-rpc/transcripts/editor.jsonl --log-preset dir-message --direction in=client --direction out=server
```

The command exits with status 0 and prints the summary:

```text
examples/json-rpc/transcripts/editor.jsonl: summary: valid:true complete:true entries:9 outstanding:0 correlation:true lines:19 not_json:8 skipped:2
```

`mcp-like.jsonl` and `mcp-like.mapping.json` show a log with its own line format. The mapping file names the fields
of each line.

`scripts/test-cli.mbtx` runs all these cases through the built CLI (`mise run test:cli`).
