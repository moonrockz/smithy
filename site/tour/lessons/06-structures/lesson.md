# Structures and members

A structure is a fixed set of named members. The members are not ordered. Each member can have a value of a different type.

Write a member as a name, a colon and a target. The target is the shape of the member value.

This model has two structures. In `Customer`, the members `name` and `email` target the prelude shape `String`. The member `address` targets the structure `Address`. In this way, a structure can contain other structures.

Each member has its own [shape ID](https://smithy.io/2.0/spec/aggregate-types.html#structure-member-shape-ids). It is the structure ID, a `$` character and the member name. The shape ID of the member `email` is `example#Customer$email`.

Look at the JSON Schema output. The converter puts a schema for each structure in `definitions`. The schema has `"type": "object"`. Each member becomes one entry in `properties`:

- A member that targets `String` gets `"type": "string"`.
- A member that targets a structure gets a `$ref` to the definition of that structure.

Now add a member to `Customer`. Put this line directly after the line `address: Address`:

```smithy
phone: String
```

The schema of `Customer` now has the property `phone`, with `"type": "string"`.

When you [add a member](https://smithy.io/2.0/spec/aggregate-types.html#adding-new-structure-members) to a structure that is in use, add it at the end. Some programming languages need a fixed layout of the data. A new member at the end keeps the old layout the same.
