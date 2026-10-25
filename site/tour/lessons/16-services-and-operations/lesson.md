# Services and operations

A [service](https://smithy.io/2.0/spec/service-types.html#service) is the entry point of an API. In this model, the service `Weather` has a `version` and a list of `operations`. The list binds the [operation](https://smithy.io/2.0/spec/service-types.html#operation) `GetForecast` to the service.

An operation has an input and an output. Each one targets a structure. This model defines them [inline](https://smithy.io/2.0/spec/idl.html#idl-inline-input-output) with `:=`. Smithy gives the inline structures the names `GetForecastInput` and `GetForecastOutput`.

The trait `@rpcv2Json` is a protocol trait. [Protocols](../21-protocols/lesson.md) gives more information about protocols. The OpenAPI converter needs a protocol to make a document. With this protocol, each operation is a `POST` request to `/service/Weather/operation/` and the name of the operation.

Look at the OpenAPI output. It has `"openapi": "3.0.2"` and the path `/service/Weather/operation/GetForecast` with `"post"`. The request body refers to the schema `GetForecastRequestContent`. The response refers to `GetForecastResponseContent`. The documentation comment of `GetForecast` becomes the `description` of the operation.

Make these changes one at a time. Change the model back after each change.

- Change the list to `operations: [GetForecast, GetCity]`. Then add this operation at the end:

  ```smithy
  /// Gives the name of a city.
  operation GetCity {
      input := {
          @required
          cityId: String
      }

      output := {
          @required
          name: String
      }
  }
  ```

  The output now also has the path `/service/Weather/operation/GetCity`.
- Replace the full block `input := { … }` with the line `input: String`. The input must target a structure. The Findings tab shows an error with the event ID `Target` on `example#GetForecast`.
- Delete the line `@rpcv2Json`. The model has no error and no warning, but now it has no protocol. The output tab says: there is no service with a protocol trait.
