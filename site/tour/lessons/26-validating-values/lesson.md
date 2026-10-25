# Validating JSON values

> **Our extension:** Smithy defines no value validation. This check is part of [moonrockz/smithy-validation](../../../../pkgs/smithy-validation/README.mbt.md). No Java reference exists for it.

This check compares a JSON value with a shape of the model, as the command `smithy validate value` does. Here the shape is `example.orders#Order`, and the value is the file `order.json`.

The Value findings tab shows one line for each finding. A line starts with the file name and the JSON pointer of the value. Then it shows the severity, the code and the shape or the member. The start value has no findings.

Make these changes in `order.json` one at a time. Change the value back after each change.

- Change the quantity to `11`. The trait `@range` permits 1 to 10, so the tab shows `order.json/quantity: error[Range]` on the member `example.orders#Order$quantity`.
- Change `2` to `"2"`. The check does not change a string into a number, so the tab shows `TypeMismatch` at `/quantity`.
- Delete the line of `id`. The member is required, so the tab shows `RequiredMember` at `/id`.
- Change the note to `Leave the parcel at the back door`. The trait `@length` permits at most 20 characters, so the tab shows `Length` at `/note`.
- After the line of `id`, add the line `"colour": "red",`. The shape has no member `colour`, so the tab shows `UnknownMember` on `example.orders#Order`. The CLI option `--unknown-members ignore` permits unknown members.
- Delete the last brace. The text is not JSON, so the check stops with `order.json: error[InvalidJson]`.

## On your computer

The `smithy` CLI and the MoonBit library run the same check on this model. The command prints nothing for a valid value. For the second order, it prints a `Range` line and exits with the status 1. The tests of this repository run both blocks.

```include
CLI: apps/smithy/README.md#value-cli
MoonBit: pkgs/smithy-validation/README.mbt.md#value-api
```
