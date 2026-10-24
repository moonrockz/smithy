# Constraint traits

A constraint trait limits the values of a shape. Constraint traits are for validation only. The specification recommends that they do not change the types in generated code. It also recommends that a server [enforce](https://smithy.io/2.0/spec/constraint-traits.html#constraint-trait-enforcement) them after it reads a request.

This model uses three constraint traits:

- [`@length`](https://smithy.io/2.0/spec/constraint-traits.html#length-trait) sets a minimum and a maximum length. For a string, the length is the number of Unicode scalar values. For a list, it is the number of values in the list.
- [`@pattern`](https://smithy.io/2.0/spec/constraint-traits.html#pattern-trait) gives a regular expression in the ECMA 262 dialect. Smithy does not add `^` and `$` to the expression. Without them, a match on part of the string is enough.
- [`@range`](https://smithy.io/2.0/spec/constraint-traits.html#range-trait) sets a minimum and a maximum value of a number.

The specification defines the limits of [`@length`](https://smithy.io/2.0/spec/constraint-traits.html#length-trait) and [`@range`](https://smithy.io/2.0/spec/constraint-traits.html#range-trait) as inclusive.

The structure `OrderLine` uses the three shapes. Look at the JSON Schema output. `@length` becomes `minLength` and `maxLength`. `@pattern` becomes `pattern`. `@range` becomes `minimum` and `maximum`.

Now change `max: 64` to `max: 32`. The property `name` now has `"maxLength": 32`.

Each trait has a selector. The selector tells which shapes can have the trait. The selector of `@range` accepts only numbers and members that target numbers. Put `@range(min: 1)` on the line directly before `string ProductName`. The Findings tab shows an error with the event ID `TraitTarget` on `example#ProductName`. Remove the line again.
