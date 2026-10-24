# Enums

An enum is a fixed set of string values. Each member of the enum gives one value.

A member without a value gets its name as the value. In this model, the value of `PENDING` is `"PENDING"`. To give a different value, write `=` and a string, for example `SHIPPED = "shipped"`. This form is short for the trait [`@enumValue`](https://smithy.io/2.0/spec/type-refinement-traits.html#enumvalue-trait).

An [intEnum](https://smithy.io/2.0/spec/simple-types.html#intenum) is a fixed set of integer values. In this model, the value of `LOW` is `1`, and the value of `HIGH` is `2`.

The structure `Order` uses the two enums. Look at the JSON Schema output:

- `OrderState` becomes `"type": "string"`. Its `enum` list contains the three values `"PENDING"`, `"shipped"` and `"delivered"`.
- `Priority` becomes `"type": "number"`. Its `enum` list contains `1` and `2`.

Each member of an intEnum must have an integer value. Now remove `= 1` from `LOW`. The Findings tab shows an error with the event ID `EnumShape` on the member `example#Priority$LOW`. Put the value back.

Enums are open. A later version of the model can add members. A client must accept a value that it does not know. Add the member `CANCELLED` on a new line after `DELIVERED`. The `enum` list of `OrderState` now ends with `"CANCELLED"`. Remove the member again.

The values of an enum must be unique. Two members cannot have the same value. Now change the value of `DELIVERED` to `"shipped"`. The Findings tab shows an error with the event ID `EnumShape` on the member `example#OrderState$DELIVERED`. Change the value back.
