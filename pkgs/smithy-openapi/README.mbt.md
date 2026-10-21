# Smithy OpenAPI

Convert an assembled Smithy HTTP service to OpenAPI 3.0.2 or 3.1.0.
The converter reuses `moonrockz/smithy-jsonschema` for value schemas.

The reference corpus and its exact upstream revision live in
`tests/tck/openapi`. Conversion does not execute code, read files or make
network requests. The CLI owns build configuration and artifact writes.

## Library

```mbt check
///|
test {
  let loader = @smithy.Loader::new()
  for input in @openapi.protocol_definitions() {
    ignore(loader.add(input))
  }
  ignore(
    loader.add_idl(
      "api.smithy",
      (
        #|$version: "2"
        #|namespace example
        #|use aws.protocols#restJson1
        #|@restJson1
        #|service Api { version: "1", operations: [Ping] }
        #|@http(method: "GET", uri: "/ping")
        #|operation Ping {}
      ),
    ),
  )
  let model = loader.assemble().model.unwrap()
  let config = @openapi.Config::new(
    @openapi.ServiceId::parse("example#Api").unwrap(),
    version=@openapi.V3_1_0,
  )
  let result = @openapi.convert_result(model, config)
  assert_true(
    result.document is { "openapi": "3.1.0", "paths": { "/ping": _, .. }, .. },
  )
  assert_true(result.warnings.is_empty())
}
```

`convert(model, config)` returns the document alone. `convert_result` also
returns structured warnings with a classification and affected `ShapeId`.
Invalid settings, unresolved services/protocols and unsupported constructs raise
`OpenApiError`; `message()` provides a diagnostic suitable for a CLI.

The bundled protocols are `aws.protocols#restJson1` and
`smithy.protocols#rpcv2Json`. Apply the protocol trait to the service. A single
protocol is selected automatically; use `protocol=ProtocolId::parse(...).unwrap()`
when the service declares several. Selecting an unapplied or unimplemented
protocol fails.

`protocol_definitions()` supplies ordinary trait-provider inputs. When your
model dependencies already define these protocols, use those definitions instead.
Alternatively, assemble the bundled inputs separately and call
`loader.add_defaults(provider_model)`: explicit input definitions take precedence
regardless of insertion order. The CLI supplies these defaults for OpenAPI builds.

## Build plugin

Put this in `smithy-build.json`, then run `smithy build`:

```json
{
  "version": "1.0",
  "sources": ["model"],
  "plugins": {
    "openapi": {
      "service": "example#Api",
      "version": "3.1.0"
    }
  }
}
```

The artifact is `build/smithy/source/openapi/Api.openapi.json`. Projection plugins
use the projection name in place of `source`. Named instances such as
`openapi::public` use `public` as their output directory. Conversion warnings are
printed to stderr; failures make the build exit unsuccessfully.

| Setting | Default and behavior |
|---|---|
| `service` | Required absolute root shape ID |
| `version` | `3.0.2`; also `3.1.0` |
| `protocol` | Infer the single applied protocol |
| `onHttpPrefixHeaders` | `FAIL`; `WARN` omits the binding and reports a warning |
| `ignoreUnsupportedTraits` | `false`; `true` warns and omits unsupported traits |
| `forbidGreedyLabels` | `false`; `true` rejects greedy URI labels |
| `removeGreedyParameterSuffix` | `false`; `true` removes `+` from parameter names |
| `onErrorStatusConflict` | Unset; `oneOf` combines errors sharing a status code |
| `jsonContentType` | `application/json` for REST document bodies |
| `defaultBlobFormat` | `byte`; becomes `contentEncoding` in 3.1 |
| `disableIntegerFormat` | `false`; suppresses `int32`/`int64` formats |
| `useStringsForArbitraryPrecision` | `false`; RPC v2 JSON always uses strings |
| `alphanumericOnlyRefs` | `false`; strips punctuation from component names |
| `tags` | `false`; exports service/operation tags when enabled |
| `supportedTags` | All tags; restrict with an array of names |
| `externalDocs` | Ordered preferred documentation labels: Homepage, API Reference, User Guide, Developer Guide, Reference, Guide |
| `keepUnusedComponents` | `false`; remove components unreachable from paths/security |
| `substitutions` | `{}`; replace matching string values throughout the document |
| `jsonAdd` | `{}`; insert JSON values at JSON Pointer paths after substitutions |

The [JSON Schema settings](../smithy-jsonschema/README.mbt.md) for maps, unions,
enums, defaults, numeric types and reference descriptions also apply. Library
callers pass them through `schema=...`. OpenAPI fixes the definition pointer at
`#/components/schemas`; 3.1 schema objects follow draft 2020-12 and 3.0 adaptations
remove unsupported keywords. Reference descriptions require 3.1. REST JSON forces
JSON member names and epoch-second default document timestamps, as the reference
protocol does. Path/query timestamps default to date-time and header timestamps
to HTTP-date.

## Conversion boundaries

HTTP traits determine paths, methods, parameters, headers, document bodies and
payloads. Service/resource operations, contextual renames, examples, streaming
payloads and HTTP Basic/Bearer/Digest/API-key authentication are supported.
Resource identifiers/properties and custom traits are not exported as metadata.
Endpoint and host-label traits fail unless `ignoreUnsupportedTraits` is enabled.
Greedy labels retain the reference's OpenAPI representation by default.

Amazon API Gateway extensions and AWS authentication/service trait packages are
outside this module. Unsupported authentication schemes are omitted with a warning.
This is a lossy conversion; retain the Smithy model for Smithy-specific semantics.

The pinned Java plugin's serialized output is the compatibility contract,
including its `externalDocumentation` key at service level (`externalDocs` on
operations/schemas), omission of empty `paths`, and same-status error handling.

## Reference verification

Normal tests compare committed expectations without Java or network access.
`tests/tck/openapi/cases.json` assigns each upstream golden or records its explicit
scope exclusion. Local fixtures exercise core features that also appear in
excluded AWS/custom-extension cases.

To refresh from the pinned source snapshot, run `mise run tck:vendor:openapi`.
`mise run tck:reference:openapi` compiles hash-verified upstream Java sources with
a local JDK and runs the actual `openapi` build plugin. Add `--check` to verify
generated expectations without rewriting them. The scripts take an optional
upstream directory; their default is `.dev/reference/snapshot`. Java classes and
intermediate outputs remain under `.dev/`.
