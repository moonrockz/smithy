# Errors

An error is a structure with the trait [`@error`](https://smithy.io/2.0/spec/type-refinement-traits.html#error-trait). Its value is `"client"` or `"server"`. The value tells if the client or the server is at fault.

An operation lists the errors that it can return in `errors`. In this model, `GetForecast` can return `CityNotFound`. A [service](https://smithy.io/2.0/spec/service-types.html#service) can also list errors. Every operation of the service can return these errors. Here, the service `Weather` lists `ServiceUnavailable`.

The trait [`@httpError`](https://smithy.io/2.0/spec/http-bindings.html#httperror-trait) sets the HTTP status code of an error. `CityNotFound` has the code 404.

Look at the OpenAPI output. The operation `GetForecast` has the response `"404"` with the schema `CityNotFoundErrorContent`. It also has the response `"500"` with `ServiceUnavailableErrorContent`, because the service lists this error. `ServiceUnavailable` has no `@httpError`. The output gives the code 500 to this server error.

The trait [`@retryable`](https://smithy.io/2.0/spec/behavior-traits.html#retryable-trait) tells a client that it can send the request again after this error.

Make these changes one at a time. Change the model back after each change.

- Delete the line `@httpError(404)`. Now `CityNotFound` has no status code. The output gives the code `"400"` to this client error.
- Delete the line `@error("client")`. Now `CityNotFound` is not an error, but `errors` accepts only errors. The Findings tab shows an error with the event ID `Target` on `example#GetForecast`.
- Change `@httpError(404)` to `@httpError(200)`. For a client error, the specification recommends a code from 400 to 499. The code 200 is not an error code. The Findings tab shows a `DANGER` event with the event ID `HttpResponseCodeSemantics` on `example#CityNotFound`.
