# Operation traits

[Behavior traits](https://smithy.io/2.0/spec/behavior-traits.html) tell how an operation behaves:

- The trait [`@readonly`](https://smithy.io/2.0/spec/behavior-traits.html#readonly-trait) tells that an operation is effectively read-only.
- The trait [`@idempotent`](https://smithy.io/2.0/spec/behavior-traits.html#idempotent-trait) tells that many identical requests have the same effect on the server as one request.

In this model, the `GET` operations have `@readonly`. The `PUT` and `DELETE` operations have `@idempotent`. The model has no warning. Smithy compares these traits with the method of the `@http` trait.

The trait [`@paginated`](https://smithy.io/2.0/spec/behavior-traits.html#paginated-trait) tells that an operation gives its results in pages. It names members of the input and the output of `ListCities`:

- `inputToken` and `outputToken` name `nextToken`. To get the next page, the client sends the `nextToken` of a response in the next request.
- `pageSize` names the input member `pageSize`. It limits the maximum number of results in a response.
- `items` names the output member `cities`. It holds the results.

Look at the OpenAPI output. The path `/cities` has `"get"`. The path `/cities/{name}` has `"get"`, `"put"` and `"delete"`. The input members of `ListCities` have `@httpQuery`, so the output has query parameters such as `"name": "nextToken"`.

Make these changes one at a time. Change the model back after each change.

- In `GetCity`, change `method: "GET"` to `method: "POST"`. Now a `POST` operation has `@readonly`. The Findings tab shows a `WARNING` with the event ID `HttpMethodSemantics.UnnecessaryReadonlyTrait` on `example#GetCity`. A warning does not stop the output. The path `/cities/{name}` now has `"post"`.
- Delete the line `@idempotent` above `operation DeleteCity`. Now a `DELETE` operation has no `@idempotent`. The Findings tab shows a `WARNING` with the event ID `HttpMethodSemantics.MissingIdempotentTrait` on `example#DeleteCity`.
- Change `items: "cities"` to `items: "towns"`. `items` must name an output member, and the output of `ListCities` has no member `towns`. The Findings tab shows an error with the event ID `PaginatedTrait` on `example#ListCities`.
