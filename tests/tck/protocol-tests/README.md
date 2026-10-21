# Protocol test reference corpus

`REFERENCE_SHA` pins smithy-lang/smithy at `30bdab593f0c2cdf96036782cc3ce15c43a711ef`.
`inventory.json` records every copied file's Git blob, verified by
`mise run tck:vendor:protocols -- PATH_TO_UPSTREAM_SNAPSHOT`. Files are unmodified;
the Apache-2.0 license is included.

`http_protocol_tests_test.mbt` checks ordinary request/response feature models,
tags and appliesTo examples, invalid params, duplicate IDs, error targets,
timestamps, vendor params and JSON body syntax against the Java `.errors` event ID, severity,
owner and multiplicity. Missing vendor targets have a separate rejection test:
existing assembly emits one `Model` error rather than Java's
`SyntacticShapeIdTarget` plus `Model` pair.

Remaining vendored files record boundaries: malformed-request and event-stream
fixtures belong to later capabilities; XML body-syntax validation is outside
this slice. Runner tests and BDD cover actual HTTP comparisons, including no
assertion for an omitted body.
