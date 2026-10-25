# Protocols

A protocol is a named set of rules for how a client and a server communicate. A protocol trait is a trait with the meta-trait [`@protocolDefinition`](https://smithy.io/2.0/spec/protocol-traits.html#protocoldefinition-trait). A protocol trait applies to a service. The `traits` property of `@protocolDefinition` lists the traits that an implementation of the protocol must understand.

In this model, the service `Weather` has the protocol trait `@restJson1`. The [AWS restJson1 protocol](https://smithy.io/2.0/aws/protocols/aws-restjson1-protocol.html) uses the HTTP binding traits, such as `@http` and `@httpLabel`.

Look at the OpenAPI output. The path `/cities/{cityId}` has `"get"`, from the trait `@http` of `GetCity`.

This lesson shows OpenAPI 3.1, so the output has `"openapi": "3.1.0"`. The OpenAPI converter has a [`version` setting](https://smithy.io/2.0/guides/model-translations/converting-to-openapi.html#generate-openapi-setting-version) for this. Its default is 3.0.2. The blob `Photo` has the trait [`@mediaType`](https://smithy.io/2.0/spec/protocol-traits.html#mediatype-trait). In the 3.1 output, the member `photo` has `"contentMediaType": "image/png"` and `"contentEncoding": "byte"`.

Make these changes one at a time. Change the model back after each change.

- Change `use aws.protocols#restJson1` to `use smithy.protocols#rpcv2Json`. Change `@restJson1` to `@rpcv2Json`. Keep the trait `@http`. The [supported traits](https://smithy.io/2.0/additional-specs/protocols/smithy-rpc-v2-json.html#supported-traits) of Smithy RPC v2 JSON do not include `@http`. Every request is a `POST` to `/service/` and the names of the service and the operation. The output now has the path `/service/Weather/operation/GetCity` with `"post"`.
- Add the line `use smithy.protocols#rpcv2Json`. Add the line `@rpcv2Json` above `service`, and keep `@restJson1`. Now the service has two protocols, and the model has no error and no warning. When a service has more than one protocol, the OpenAPI converter needs the [`protocol` setting](https://smithy.io/2.0/guides/model-translations/converting-to-openapi.html#generate-openapi-setting-protocol). The tour does not set it. The output tab says that the service defines multiple protocols.
