# Checking IR values

This lesson checks the IR type in `type.json` against `morphir.ir.v4#Type`. The value is the type `deal` of the Morphir books-and-records example: a record with three fields ([source](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/ir/examples/v4/books-and-records-example.json#L83-L95)).

> **Our extension:** Smithy defines no validation of JSON values. This check is part of moonrockz/smithy-validation. [Lesson 26](../26-validating-values/lesson.md) shows the same check from the CLI and from MoonBit.

Every node of the value has the expanded spelling: a wrapper object with an object payload. The payload can start with `attributes`, and then has the members of the node ([decision 0005](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/kb/bundles/morphir/morphir-ir/decisions/0005-attributes-are-an-optional-first-member-of-every-node-payload.md?plain=1#L13-L16)). The value check reads this as a union of structures, so the value passes.

Make these changes in `type.json` one at a time:

- Change the field name `price` to `Price`. You get a `Pattern` error, because the model makes each field name a `Name`.
- Change the value to `{"Variable": {"name": "a"}, "Unit": {}}`. You get a `UnionMember` error. A node has exactly one member.
- Change the value to `{"Variable": {"attrs": {}, "name": "a"}}`. You get an `UnknownMember` error. Morphir readers accept the old name `attrs` for one release, with a warning ([decision 0006](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/kb/bundles/morphir/morphir-ir/decisions/0006-node-member-names-follow-the-schema-with-a-one-release-window.md?plain=1#L4), [kit case types-0009](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/spec/ir/mck/types.feature#L145-L147)).
- Change the value to `{"Variable": {"attributes": {"constraints": 5}, "name": "a"}}`. You get a `TypeMismatch` error. Morphir also rejects this value ([kit case types-0012](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/spec/ir/mck/types.feature#L176-L184)).

Also try `number -> number -> number`, the type of `add`. It is a `Function` whose `returnType` is a second `Function`. It passes. A function type in the IR has one parameter ([schema, line 950](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L950-L970)). So a function of two parameters is a function that returns a function ([version 3 schema](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v3.yaml#L376-L377)).

Morphir writers use the compact spelling, unless you select the expanded output ([JSON profile](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/docs/spec/ir/schemas/v4/json-profile.md?plain=1#L31)). [Lesson 39](../39-morphir-limits/lesson.md) checks the example in that spelling.
