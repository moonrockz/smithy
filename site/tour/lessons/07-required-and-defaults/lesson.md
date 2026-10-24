# Required, defaults and nullability

A structure member is optional by default. A value of the structure can leave out an optional member. Two traits make sure that a member always has a value.

The trait [`@required`](https://smithy.io/2.0/spec/type-refinement-traits.html#required-trait) means that the member must always have a value. In this model, `name` is required.

The trait [`@default`](https://smithy.io/2.0/spec/type-refinement-traits.html#default-trait) gives the member a default value. The IDL has a short form for this trait. The line `points: Integer = 0` is the same as `@default(0)` on the member `points`. When a value for `points` is missing, the member gets the default value.

The member `email` has no `@required` and no default value, so it is optional.

This is the same idea as nullability in a programming language. Code generators use these traits. The specification recommends an accessor that always returns a value for a required member. The traits `@clientOptional` and `@input` change the rules for clients. The [table of optionality rules](https://smithy.io/2.0/spec/aggregate-types.html#structure-member-optionality) gives all the cases.

Look at the JSON Schema output. The list `required` contains only `name`. The property `points` has `"default": 0`. It is not in `required`. A value can leave it out, and then the member gets the default value.

Now put `@required` on the line directly before `email: String`. The list `required` now contains `email` and `name`.

A default value must agree with the shape of the member. Change `= 0` to `= "zero"`. The Findings tab shows an error with the event ID `DefaultTrait`. The value `"zero"` is not an integer.
