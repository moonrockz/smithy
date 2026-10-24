# Resources and lifecycle

A [resource](https://smithy.io/2.0/spec/service-types.html#resource) is an entity with an identity and a set of operations. In this model, the service `Weather` binds the resource `City` in its list `resources`.

A resource can have [identifiers](https://smithy.io/2.0/spec/service-types.html#resource-identifiers) and properties. The identifier `cityId` targets the string `CityId`. The property `name` targets `String`. The [lifecycle operations](https://smithy.io/2.0/spec/service-types.html#resource-lifecycle-operations) of `City` are `create`, `read` and `list`. Each lifecycle operation must agree with the rules of its lifecycle.

`CreateCity` and `GetCity` use [target elision](https://smithy.io/2.0/spec/idl.html#idl-target-elision). The words `for City` refer to the resource. A member name with `$`, such as `$cityId`, gets its target from an identifier or a [property](https://smithy.io/2.0/spec/service-types.html#resource-properties) of `City`.

Look at the OpenAPI output. The protocol trait `@rpcv2Json` makes each operation a `POST` request to `/service/Weather/operation/` and the operation name. See [Protocols](../21-protocols/lesson.md). The output has a path for each operation, such as `/service/Weather/operation/GetCity`. The schema of `cityId` has `"pattern": "^[a-z0-9-]+$"`. This is the pattern of `CityId`.

Make these changes one at a time. Change the model back after each change.

- In the input of `GetCity`, change `$cityId` to `$name`. A [read operation](https://smithy.io/2.0/spec/service-types.html#read-lifecycle) must bind all identifiers of the resource in its input. Now the input does not bind `cityId`. The Findings tab shows an error with the event ID `ResourceIdentifierBinding` on `example#GetCity`.
- Delete the line `@readonly` above `operation GetCity`. A read operation must have the trait `@readonly`. The Findings tab shows an error with the event ID `ResourceLifecycle` on `example#City`.
- In the output of `GetCity`, change `$name` to `$population`. `City` has no identifier and no property with the name `population`. The Findings tab shows an error with the event ID `Model` on `example#GetCityOutput$population`. `GetCityOutput` is the name of the inline output structure.
