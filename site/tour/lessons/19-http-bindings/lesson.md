# HTTP bindings

The [HTTP binding traits](https://smithy.io/2.0/spec/http-bindings.html) tell how an operation uses an HTTP message. The trait [`@http`](https://smithy.io/2.0/spec/http-bindings.html#http-trait) gives the method and the URI of an operation. In this model, `GetForecast` is a `GET` request to `/cities/{cityId}/forecast`.

Other traits bind the members of the input and output:

- [`@httpLabel`](https://smithy.io/2.0/spec/http-bindings.html#httplabel-trait) puts a member in the URI label with the same name. `cityId` fills `{cityId}`.
- [`@httpQuery`](https://smithy.io/2.0/spec/http-bindings.html#httpquery-trait) puts a member in a query string parameter. `days` is the parameter `days`.
- [`@httpHeader`](https://smithy.io/2.0/spec/http-bindings.html#httpheader-trait) puts a member in an HTTP header, in the request or in the response. `language` is the request header `Accept-Language`. `cacheControl` is the response header `Cache-Control`.
- [`@httpPayload`](https://smithy.io/2.0/spec/http-bindings.html#httppayload-trait) puts one member in the full body of the message. In `PutPhoto`, `photo` is the body.

The service has the protocol trait `@restJson1`. This protocol uses the HTTP binding traits. [Protocols](../21-protocols/lesson.md) tells more about protocols.

Look at the OpenAPI output. The parameters of `/cities/{cityId}/forecast` have `"in": "path"`, `"in": "query"` and `"in": "header"`. The response has the header `Cache-Control`. The request body of `PutPhoto` has the media type `application/octet-stream`.

Make these changes one at a time. Change the model back after each change.

- Change the URI of `GetForecast` to `"/forecast"`. The member `cityId` has `@httpLabel`, but the URI has no label `{cityId}`. The Findings tab shows an error with the event ID `HttpLabelTrait` on `example#GetForecastInput$cityId`.
- Add the member `units: String` after `language`, with no trait. A member with no binding goes in the [body](https://smithy.io/2.0/spec/http-bindings.html#http-protocol-document-payloads) of the message. A `GET` request with a body member gives a `DANGER` event with the event ID `HttpMethodSemantics.UnexpectedPayload` on `example#GetForecast`.
- Add the member `caption: String` after `photo`. When the input has `@httpPayload`, every other member must have a binding, such as `@httpLabel` or `@httpHeader`. The Findings tab shows an error with the event ID `HttpPayload` on `example#PutPhotoInput`.
