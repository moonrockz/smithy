# Contracts

A [contract trait](https://smithy.io/2.0/additional-specs/contract-traits.html) adds a rule that valid values must obey. The trait [`smithy.contracts#conditions`](https://smithy.io/2.0/additional-specs/contract-traits.html#smithy-contracts-conditions-trait) is one. It is not in the prelude, so the model imports it with `use`.

The trait is a map from condition names to conditions. Each condition has an `expression` and `documentation`. The expression is a JMESPath expression that must give `true`. In the expression, a member name selects the value of that member, and `@` is the value itself. A timestamp is a number in the [JMESPath data model](https://smithy.io/2.0/additional-specs/waiters.html#jmespath-data-model), so `start < end` compares two times.

Smithy checks each expression before it uses it. Make these changes to `TimeRange`, one at a time:

- Change the expression to `start`. The result is a number, not a boolean. The Findings tab shows a DANGER.
- Change it to ``length(start) > `0` ``. The function [`length`](https://jmespath.org/specification.html#length) accepts a string, an array or an object, but `start` is a number. The Findings tab shows an error.
- Change it to `start <`. The expression does not parse, and the Findings tab shows an error.
- Change the name `StartBeforeEnd` to `startBeforeEnd`. A condition name must start with an upper-case letter, so the Findings tab shows an error.

Smithy also checks the values in the model against the conditions. Change the default value of `cityId` to `"new york"`. The Findings tab shows the error `DefaultTrait.NoSpaces` on `example#Search$cityId`.

The specification recommends that tools do not [enforce contract traits](https://smithy.io/2.0/additional-specs/contract-traits.html#contract-trait-enforcement) by default when they serialize or deserialize data.

## On your computer

The `smithy` CLI and the MoonBit library also check contract traits. The CLI tab validates the model and finds the shapes that have conditions. The MoonBit tab shows the DANGER of the expression `start`. The tests of this repository run both blocks.

```include
CLI: apps/smithy/README.md#contracts-cli
MoonBit: pkgs/smithy/README.mbt.md#contracts-api
```
