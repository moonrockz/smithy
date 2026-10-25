# Names as constrained strings

IR version 4 writes a name as one string. A name has one or more segments, joined by `-`. A segment is all lowercase (a word) or all uppercase (an initialism), and it can contain digits. For example, `value-in-USD` is a name. A segment with mixed case, such as `Usd`, is not valid ([schema, line 49](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L49-L57)).

A path is one or more names joined by `/`, such as `morphir/SDK` ([schema, line 74](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L74-L80)). A fully qualified name (FQName) identifies a type or a value in all of the IR. Its form is `package:module#name`, for example `morphir/SDK:list#map`. The package and the module are paths ([schema, line 108](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L108-L114)).

In `names.smithy`, `Name`, `Path` and `FQName` are strings with a `@pattern` trait ([lesson 11](../11-constraints/lesson.md)). Each pattern is the pattern of the schema, character for character. A `@pattern` value is one full regular expression, and it cannot refer to a different pattern. For this reason, the pattern of `FQName` repeats the pattern of a name five times.

This lesson checks the value in `fqname.json` against the shape `morphir.ir.v4#FQName`.

> **Our extension:** Smithy defines no validation of JSON values. This check is part of moonrockz/smithy-validation. [Lesson 26](../26-validating-values/lesson.md) shows the same check from the CLI and from MoonBit.

Make these changes in `fqname.json` one at a time:

- Change the value to `"morphir/SDK:list#Map"`. The Value findings tab shows a `Pattern` error, because `Map` is a segment with mixed case.
- Change the value to `"morphir/sdk:list#map"`. You get no finding. The pattern checks the spelling, not the meaning. This FQName is valid, but its package is not the SDK. The SDK package is `morphir/SDK` ([decision 0011](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/kb/bundles/morphir/morphir-ir/decisions/0011-the-sdk-package-is-named-morphir-slash-sdk-uppercase.md?plain=1#L13-L19), [kit case names-0006](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/spec/ir/mck/names.feature#L72-L84)).
- Change the value to `[[["morphir"], ["s", "d", "k"]], [["list"]], ["map"]]`. This is the legacy array form of the same FQName ([v4 overview](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/docs/spec/ir/schemas/v4/index.md?plain=1#L84-L88)). The tab shows a `TypeMismatch` error, because `FQName` is a string.
- Change the value to `"my-org/finance-and-risk/regulatory-reporting:liquidity/coverage-ratio#calculate-net-cash-outflows"`. A long FQName also gives no finding.
