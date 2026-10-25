# Comparing models

A model changes over time, and some changes break the clients of the old model. The Smithy guide [Evolving Models](https://smithy.io/2.0/guides/evolving-models.html#updating-structures) lists the safe and the unsafe changes. The tool [Smithy Diff](https://smithy.io/2.0/guides/evolving-models.html#using-smithy-diff) compares two models.

Our command `smithy diff` and the library [moonrockz/smithy-diff](../../../../pkgs/smithy-diff/README.mbt.md) use the rules of the Java Smithy Diff. The tour check compares the events of each case with the Java tool.

The file tabs are in two groups, Old and New. The Diff tab shows each event as the CLI prints it. A line has the severity, the shape, the message and the event ID. The new model adds the optional member `humidity` to the output. So the Diff tab shows `AddedShape` with the severity NOTE, a compatible change.

Make these changes in the new model one at a time. Change the model back after each change.

- Delete the member `days` from the input. The Diff tab shows `RemovedShape` with the severity ERROR, a breaking change.
- After `days`, add the member `country: String` with the trait `@required`. The Diff tab shows the ERROR `AddedRequiredMember`. Its message names the traits `default` and `clientOptional`: without one of them, the change is not compatible.
- Delete the member `humidity`. The two models are now the same. The Diff tab shows "No differences."
- Change the target of `celsius` to `Celsius`. No shape `Celsius` exists, so the Findings tab shows the ERROR `Target.UnresolvedShape`. The new model has an error, so the tool does not compare the models.

## On your computer

The [CLI](../../../../apps/smithy/README.md) exits with the status 1 when an event has the severity ERROR or DANGER. The first command compares the old model with the start model and exits with 0. The second command compares it with a model without `days`. The tests of this repository run both blocks.

```include
CLI: apps/smithy/README.md#diff-cli
MoonBit: pkgs/smithy-diff/README.mbt.md#diff-api
```
