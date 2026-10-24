# Shape IDs, use and the prelude

This model has two files, and the editor has a tab for each file. An IDL file has one namespace at most. The file `common.smithy` defines the shape `CityName` in the namespace `example.common`. The file `model.smithy` defines the structure `Forecast` in the namespace `example.weather`.

Each shape has a shape ID. An absolute shape ID has the namespace, a `#` character and the shape name, for example `example.common#CityName`. The ID of a member adds a `$` character and the member name, for example `example.weather#Forecast$city`. A relative shape ID has no namespace, for example `CityName`.

In an IDL file, you can write a relative shape ID. Smithy resolves it with these [rules](https://smithy.io/2.0/spec/idl.html#relative-shape-id-resolution), in this order:

1. A `use` statement imports a shape with the same name.
2. The current namespace has a shape with the same name.
3. The prelude has a shape with the same name. The namespace of the prelude is `smithy.api`.

The member `city` targets `CityName`. That shape is in a different namespace, so the statement `use example.common#CityName` imports it. The member `summary` targets `String`. No `use` statement imports `String`, and `example.weather` has no shape with that name. Thus `String` resolves to the prelude shape `smithy.api#String`. Every model includes the [prelude](https://smithy.io/2.0/spec/model.html#prelude). It defines simple shapes, such as `String` and `Integer`, and the traits of the core specification.

Now delete the `use` line in `model.smithy`. The Findings tab shows the error `Target.UnresolvedShape` on the member `city`. No rule finds `CityName`, so the ID gets the current namespace: `example.weather#CityName`. No shape has that ID.

Now change `city: CityName` to `city: example.common#CityName`. Smithy does not resolve an absolute shape ID, so it needs no `use` statement. The error goes away.
