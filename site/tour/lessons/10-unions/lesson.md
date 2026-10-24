# Unions as tagged unions

A union is a tagged union. It has a fixed set of members, and exactly one member is present at a time. The name of the member is the tag. The target of the member is the value for that tag.

In this model, a `PaymentMethod` is a card or cash. A card payment holds a `Card` value. A cash payment holds no data, so the member `cash` targets [`Unit`](https://smithy.io/2.0/spec/aggregate-types.html#unit-types-in-unions). The shape `smithy.api#Unit` means "no value".

Look at the JSON Schema output. `PaymentMethod` becomes a `oneOf` with one schema for each member. Each schema is an object that requires one property: its tag. The tag `cash` refers to the definition `Unit`, an object schema that lists no properties.

A union must have one or more members. Now delete the two members of `PaymentMethod`. The Findings tab shows an error with the event ID `Union`. Put the members back.

Other languages have the same idea:

- In Rust, `PaymentMethod` is an `enum` with data in its variants: `enum PaymentMethod { Card(Card), Cash }`.
- In TypeScript, `PaymentMethod` is a discriminated union: `{ kind: "card"; card: Card } | { kind: "cash" }`. The field `kind` holds the tag. The field has one value, so an object has exactly one tag.
- In Elm, `PaymentMethod` is a custom type: `type PaymentMethod = CardPayment Card | Cash`.

A later version of the model can add members to a union. An old client can then receive a member that it does not know. For this case, the specification [recommends](https://smithy.io/2.0/spec/aggregate-types.html#client-error-correction) an "unknown" variant in generated code.
