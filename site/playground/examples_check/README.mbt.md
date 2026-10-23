# Playground examples check

Native-only tests of `playground/core` against the files of `examples/json-rpc/`.
The tests run in `site/`, so the paths start with `../examples/`.

The differential tests compare the core with the library, as the CLI uses it: `run_transcript` for a document
(with and without a version that equals the document's), and the reader and checker loop of
`apps/smithy/transcript_log_cli.mbt` for a JSONL log, for Run all and for steps of 250 and of 1 entry. The
sample tests check every transcript of the Transcript tab picker against `examples/json-rpc/peers.smithy`.
