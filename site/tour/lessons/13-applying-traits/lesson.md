# Applying traits

A trait adds information to a shape or a member. To [apply a trait](https://smithy.io/2.0/spec/model.html#applying-traits), write `@` and the trait name directly before the shape or the member. A shape can have only one instance of each trait.

This model uses four forms of trait value:

- `@required` has no value. The JSON AST shows an empty object: `"smithy.api#required": {}`.
- `@documentation("A city on the map.")` has a string.
- `@tags(["geo"])` has a list.
- `@length(min: 1, max: 64)` has named values. The JSON AST shows them as an object with `"max": 64`.

The value must agree with the shape of the trait. The table of [trait node values](https://smithy.io/2.0/spec/model.html#trait-node-values) gives the value form for each type of shape.

The [`apply` statement](https://smithy.io/2.0/spec/idl.html#apply-statement) puts a trait on a shape from outside the shape definition. Smithy [treats this trait](https://smithy.io/2.0/spec/model.html#applying-traits-externally) the same as a trait in the definition. In this model, `apply` gives the member `latitude` its documentation. Look at `latitude` in the JSON AST. It has `"smithy.api#documentation": "Degrees north of the equator."`.

The definition of each trait tells which shapes can have it. Change `@range(min: -90, max: 90)` to `@length(min: 1)`. `@length` cannot go on a member that targets `Float`. The Findings tab shows an error with the event ID `TraitTarget` on `example#City$latitude`. Change it back.

Now change `@tags` to `@tag`. The model has no trait with the name `tag`. The Findings tab shows an error with the event ID `Model.UnresolvedTrait` on `example#City`. Change it back.

Now add this line at the end of the model:

```smithy
apply City$name @length(min: 2)
```

The member `name` already has `@length` with other values. The two values conflict. The Findings tab shows an error with the event ID `Model` on `example#City$name`. [Trait conflict resolution](https://smithy.io/2.0/spec/model.html#trait-conflict-resolution) gives the rules for a trait that a shape gets two times.
