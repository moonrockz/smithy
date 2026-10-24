# Defining your own traits

You can [define a trait](https://smithy.io/2.0/spec/model.html#defining-traits) of your own. A trait is a shape with the trait `@trait`. The members of a structure trait are the values that a user of the trait gives. By convention, the name of a trait shape starts with a lower-case letter.

In this model, `event` is a trait. It has one required member, `name`. The structure `CityCreated` uses the trait with `@event(name: "city-created")`.

The `selector` of `@trait` is a [selector](https://smithy.io/2.0/spec/selectors.html) that tells which shapes can have the trait. The value `"structure"` accepts only structures.

Smithy checks each use of the trait. Make these changes one at a time. Change the model back after each change.

- Replace the full structure `CityCreated` with the line `string CityCreated`. A string is not a structure. The Findings tab shows an error with the event ID `TraitTarget` on `example#CityCreated`.
- Change the selector to `"structure[trait|error]"`. Now the trait can go only on a structure with the trait `@error`. `CityCreated` has no `@error`. The Findings tab shows an error with the event ID `TraitTarget` on `example#CityCreated`.
- Change `@event(name: "city-created")` to `@event`. The member `name` is required, but the value has no `name`. The Findings tab shows an error with the event ID `TraitValue` on `example#CityCreated`. The table of [trait node values](https://smithy.io/2.0/spec/model.html#trait-node-values) gives this rule.
- Delete the line `@trait(selector: "structure")`. Now `event` is a plain structure, not a trait. The Findings tab shows an error with the event ID `Model` on `example#event`. The error is on the shape that is not a trait, not on the shape that uses it.
