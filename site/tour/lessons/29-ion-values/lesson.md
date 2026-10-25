# Ion values

> **Our extension:** Standard Smithy has no command that checks an Ion value against a shape. The check is part of [moonrockz/smithy-ion-validation](../../../../pkgs/smithy-ion-validation/README.mbt.md), an optional module. No Java reference exists for it.

[Ion](https://amazon-ion.github.io/ion-docs/) is a data format with native types, such as timestamps, decimals, blobs and symbols. A Smithy shape checks an Ion value as it checks a JSON value ([lesson 26](../26-validating-values/lesson.md)).

This lesson does not run in the browser. The blocks below show the CLI and the MoonBit library. The tests of this repository run them.

The shape `example#Reading` has the member `takenAt`, which targets `Timestamp`. The first reading has a native Ion timestamp, so it is valid. The second reading has a string in its place. Native values do not use the coercions of a JSON serialization. In Ion, a string cannot stand in for a timestamp. So the check reports `TypeMismatch`. Also, an integral decimal cannot stand in for an integer. A symbol cannot stand in for a string.

The finding has the same form as a finding of a JSON value. It has the file name, the JSON pointer `/takenAt`, the code and the member `example#Reading$takenAt`. The JSON diagnostics also give the Ion type of the value as `nativeKind`. The library gives it as `native_kind`, here the type `string`.

The option `--input-format ion-text` reads Ion text, and `--input-format ion-binary` reads binary Ion.

```include
CLI: apps/smithy/README.md#ion-value-cli
MoonBit: pkgs/smithy-ion-validation/README.mbt.md#ion-value-api
```
