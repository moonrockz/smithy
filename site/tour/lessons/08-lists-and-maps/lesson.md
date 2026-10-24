# Lists and maps

A list is an ordered collection of values of one type. A list has one member, with the name `member`. The target of this member is the type of the values. In this model, `Tags` is a list of strings.

A [map](https://smithy.io/2.0/spec/aggregate-types.html#map) maps string keys to values of one type. A map has two members, with the names `key` and `value`. The member `key` must target a string shape. In this model, `Stock` maps a string to an integer.

Lists and maps are dense by default. They cannot contain null values. The trait [`@sparse`](https://smithy.io/2.0/spec/type-refinement-traits.html#sparse-trait) lets a list or a map contain null values.

These members also have shape IDs: `example#Tags$member`, `example#Stock$key` and `example#Stock$value`.

The structure `Product` uses the two shapes. Look at the JSON Schema output:

- The list becomes `"type": "array"`. The schema in `items` comes from the list member.
- The map becomes `"type": "object"`. The schema in `propertyNames` comes from the key. The schema in `additionalProperties` comes from the value.

The schema of the list is in the property `tags`. The map has its own definition, and the property `stock` refers to it with `$ref`.

Now change `key: String` to `key: Integer`. The Findings tab shows an error with the event ID `Target` on the map `example#Stock`. A map key must be a string. Change it back.
