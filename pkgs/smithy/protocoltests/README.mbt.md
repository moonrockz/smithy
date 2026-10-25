# HTTP protocol test suites

`moonrockz/smithy/protocoltests` loads `smithy.test#httpRequestTests` and
`smithy.test#httpResponseTests` and compares HTTP messages produced by a supplied
protocol adapter. It implements no protocol and performs no network I/O.

Use `loader()` or `@smithy.Loader::new(protocol_tests=true)` to load the bundled
upstream traits. Ordinary loaders and selectors keep their existing contents.
Model validation checks trait fields and `appliesTo`, duplicate IDs across the
model, input/output/error params, and vendor params. Request and response IDs
have separate uniqueness scopes, independent of protocol. Native params use
plain-text blobs, epoch-second timestamps and optional nulls.

When `vendorParamsShape` is set, omitted or explicitly empty `vendorParams` emits
a warning, matching the pinned Java validator. Nonempty vendor params are checked
against that shape.

`Suite::from_model(model)` reassembles a snapshot with the standard trait contract
and refuses error or danger events. Each case retains a
validated `CaseId`, protocol `ShapeId` and `Subject` distinguishing operation
inputs, operation outputs and error structures. `params()` and `definition()`
return fresh snapshots. The definition includes auth schemes, vendor params,
host configuration, tags and documentation for adapters. Cases follow shape-ID
order and trait-list order.

Implement the open `Protocol` trait's `produce(case)` method, then call
`run(adapter, case, side=Client)` or `side=Server`. The adapter owns its model,
configuration, and serialization or deserialization used to produce an observed
HTTP message. An `appliesTo` mismatch returns `Skipped` without invoking it.
Adapter errors become an `Implementation` mismatch. `case.compare(message)`
performs the same assertions for adapters with their own execution loop.

`HttpMessage::Request` has `verb`, `uri`, raw `query`, resolved `host`, repeated
`headers` and byte `body`; `HttpMessage::Response` has `code`, `headers` and `body`.
`Outcome` is `Matched`, `Mismatched(Array[Mismatch])` or `Skipped`. Each mismatch
names its typed `Field` and renders expected and actual values.

Comparison rules:

- Methods, URI paths and expected `resolvedHost` compare exactly. Input `host`
  configures the adapter and makes no assertion about the resolved destination.
- Query order is irrelevant; wire spelling and duplicate counts are preserved.
  Values for expected query names must match. Extra names are allowed. Required
  and forbidden names are checked. `flag` differs from `flag=`.
- Header names ignore case. Repeated values combine with `, ` in received order.
  Extra headers are allowed; required and forbidden names are checked.
- Status codes compare numerically.
- An omitted expected body makes no body assertion. An explicitly empty body
  asserts empty content.
- JSON compares structurally with exact numbers, ignoring object order and
  insignificant whitespace. Text, XML and unspecified media types compare UTF-8
  bytes. Binary media types decode expected base64 before comparing bytes.
  Supply `body_matches=(expected, actual_bytes, media_type) => ...` to `run` or
  `compare` for XML semantic equivalence or another media-specific comparator.

The CLI validates modeled cases:

```sh
smithy validate --protocol-tests examples/protocol-tests/greeting.smithy
```

Events go to stderr; invalid cases exit 1. Execution is a library API whose host
supplies the protocol adapter.

This test loads the greeting model and lists its cases. A `params` value of the
wrong type gives an `HttpRequestTestsInput` error on the operation:

<!-- tour:start protocol-tests-api -->
```mbt check
///|
test "list the protocol test cases of a model" {
  let source =
    #|$version: "2"
    #|namespace example
    #|
    #|use smithy.test#httpRequestTests
    #|use smithy.test#httpResponseTests
    #|
    #|@trait
    #|@protocolDefinition
    #|structure fixtureProtocol {}
    #|
    #|@httpRequestTests([{
    #|    id: "GreetingRequest"
    #|    protocol: fixtureProtocol
    #|    method: "POST"
    #|    uri: "/greeting"
    #|    params: {name: "Ada"}
    #|    headers: {"Content-Type": "application/json"}
    #|    forbidHeaders: ["X-Secret"]
    #|    body: "{\"name\":\"Ada\"}"
    #|    bodyMediaType: "application/json"
    #|}])
    #|@httpResponseTests([{
    #|    id: "GreetingResponse"
    #|    protocol: fixtureProtocol
    #|    code: 200
    #|    params: {greeting: "Hello, Ada"}
    #|}])
    #|operation Greet { input: Input, output: Output }
    #|
    #|structure Input { @required name: String }
    #|structure Output { greeting: String }
  let loaded = @protocoltests.loader()
    .add_idl("greeting.smithy", source)
    .assemble()
  assert_eq(loaded.validation_events(), [])
  let suite = @protocoltests.Suite::from_model(loaded.model.unwrap())
  assert_eq(suite.cases().map(c => c.id().to_string()), [
    "GreetingRequest", "GreetingResponse",
  ])
  let bad = @protocoltests.loader()
    .add_idl(
      "greeting.smithy",
      source.replace(old="params: {name: \"Ada\"}", new="params: {name: 1}"),
    )
    .assemble()
  let keys = bad
    .validation_events()
    .map(e => {
      let shape = e.shape.map(id => id.to_string()).unwrap_or("-")
      e.id + "|" + e.severity + "|" + shape
    })
  assert_eq(keys, ["HttpRequestTestsInput|ERROR|example#Greet"])
}
```
<!-- tour:end protocol-tests-api -->

The exact pinned upstream schema includes later malformed-request and event-stream
definitions. This runner handles request and response cases only; it does not
claim malformed-request, event-stream, smoke-test or live-transport coverage.
Model validation checks JSON body syntax; XML body-syntax validation is outside
this slice. See [the pinned corpus scope](../../../tests/tck/protocol-tests/README.md).
