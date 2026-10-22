# Smithy to OpenRPC

`moonrockz/smithy-openrpc` converts an assembled JSON-RPC 2.0 service to an
OpenRPC 1.3.2 document using JSON Schema draft-07. These are three separate
versions. The service's own `version` becomes `info.version`.

Load models with `moonrockz/smithy-validation/rpc.loader()` to opt into the
`smithy.rpc` traits. Select a validated `ServiceId`, construct `Config`, and
call `convert_result(model, config)`. The result contains the document and
structured, shape-linked warnings. `convert` returns the document directly.

Methods reuse the prepared runtime contract, including explicit positional
order, named parameter policy, direct result selectors and application errors.
The converter never fetches references or executes model-controlled code.
The library has no Ion, WIT, WAC or wasm-devkit dependency.

The document itself is built with the published
[`moonrockz/openrpc`](https://mooncakes.io/docs/moonrockz/openrpc) library at
`0.2.0`. Its checked constructors build the typed OpenRPC model. Its draft-07
model holds every generated schema, and its exact JSON keeps numeric tokens.
Before returning, the converter validates the document with the
`MetaschemaCompatibility` profile against the model, schema-document, reference,
OpenRPC 1.3.2 normative and official-metaschema checks. That profile reports
only an optional parameter before a required one as a warning, because Smithy
keeps the explicit positional order. Any other finding fails conversion with the
operation of the affected method, or the service, as its shape. Smithy-specific
mapping, extension loss policies and warnings stay in this package.

`Conversion.document` is the library's JSON for that document. Object members
follow the library's field order, not the order of earlier releases; values are
unchanged. The library checks each schema graph within fixed bounds
(moonrockz/moon-lander#56). When a very large component graph exceeds them, the
unchecked part does not fail conversion.

```mbt check
///|
test {
  let loaded = @rpc.loader()
    .add_idl(
      "api.smithy",
      (
        #|$version: "2"
        #|namespace example
        #|use smithy.rpc#jsonRpc
        #|use smithy.rpc#method
        #|@jsonRpc(versions: ["2.0"])
        #|service Api { version: "1", operations: [Ping] }
        #|@method(name: "ping", params: "named", nullResult: true)
        #|operation Ping {}
      ),
    )
    .assemble()
  let config = @openrpc.Config::new(
    @openrpc.ServiceId::parse("example#Api").unwrap(),
  )
  let result = @openrpc.convert_result(loaded.model.unwrap(), config)
  assert_true(result.document is { "openrpc": String("1.3.2"), .. })
}
```

The complete [standalone library example](../../examples/openrpc/main.mbtx)
uses pinned imports. In a source checkout, `mise run test:openrpc` packages the
working modules and runs that example in an isolated registry on all four
targets. Its dependency audit checks the full resolved module graph.

For the built CLI, [the calculator model](../../examples/openrpc/model.smithy)
and [build configuration](../../examples/openrpc/smithy-build.json) provide a
working conversion:

```sh
moon run apps/smithy -- build --config examples/openrpc/smithy-build.json
```

The default artifact is `build/smithy/source/openrpc/openrpc.json` relative to
the build configuration. Plugin aliases and projections follow Smithy build
rules, for example `openrpc::description` writes under `description/`.

Build settings are `service`, `version`, `protocolVersion`, `useJsonName`,
`timestampFormat`, `extensions`, `title` and `apiVersion`. Unknown keys fail.
`version` accepts only `1.3.2`; `protocolVersion` accepts only `2.0`.
`apiVersion` overrides `info.version`, independently of both. `useJsonName`
defaults to false. Timestamp defaults to epoch-seconds, matching the runtime
validator; date-time is an explicit alternative. `Config::new` uses typed
versions, naming, timestamp and extension policies.

Methods sort by wire name. Named-only descriptors sort by wire member name;
positional and either descriptors follow the complete explicit `positional`
member list. Optional parameters retain `required:false`, even before required
ones. Interior omissions require an explicit valid positional value. Either-mode
examples that omit an interior position carry `x-smithy-param-structure:by-name`.
Results are always present in a successful JSON-RPC response, even when the
selected output member is optional in the enclosing Smithy structure.

The default extension policy preserves error-data schemas on methods in
`x-smithy-error-data`. OpenRPC error objects' `data` is a value, not a schema.
Root `x-smithy-protocol` records notification, batch and exchange boundaries.
An explicit null result describes a successful payload, not a notification-only
operation. Method value schemas do not establish envelope or exchange validity.
`x-smithy-error-examples` carries examples of application errors because
standard example pairings describe successful results. Modeled examples are
checked against the same prepared runtime contract before emission. Invalid
examples fail conversion with the operation's semantic shape ID. Ordinary
success examples use standard OpenRPC example pairings.
`extensions=omit` reports structured losses; `extensions=fail` rejects mappings
that need extensions. JSON-RPC 1.0 is supported by the separate runtime validator
and cannot be exported as standard OpenRPC.

The converter preserves exact numeric tokens and does not insert defaults.
Downstream validators that round numbers through binary floating point cannot
prove the runtime engine's exact decimal/large-integer semantics. Draft-07
formats and content encodings can be annotations in downstream tools; timestamp
and decoded blob-length checks need their documented runtime policies.

`mise run test:openrpc` checks the pinned official metaschema digest, standard
document conformance, embedded draft-07 schemas, every component reference,
determinism, aliases, failing build status, and representative parameter/result/
error-data agreement with the actual RPC CLI. It also runs the isolated library
consumer across native, wasm, JS and wasm-gc. Tool installation for these tests
uses the network; library/build conversion uses no network or model execution.
