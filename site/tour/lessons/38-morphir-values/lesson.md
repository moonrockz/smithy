# Checking IR values

This lesson checks a type expression of IR version 4 in `type.json` against the shape `morphir.ir.v4#Type`. The value is the type `deal` of the Morphir books-and-records example: a record with three fields ([example](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/ir/examples/v4/books-and-records-example.json#L83-L95)).

> **Our extension:** Smithy defines no validation of JSON values. This check is part of moonrockz/smithy-validation. [Lesson 26](../26-validating-values/lesson.md) shows the same check from the CLI and from MoonBit.

Each node of this value has the expanded spelling. In this spelling, a node is a wrapper object with an object payload. The payload can start with `attributes`, and then it has the members of the node ([decision 0005](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/kb/bundles/morphir/morphir-ir/decisions/0005-attributes-are-an-optional-first-member-of-every-node-payload.md?plain=1#L13-L16)). The value check reads a union as an object with one member, and a structure as an object. So the value passes.

Make these changes in `type.json` one at a time:

- Change the field name `price` to `Price`. You get a `Pattern` error, because the model makes each field name a `Name`.
- Change the value to `{"Variable": {"name": "a"}, "Unit": {}}`. You get a `UnionMember` error. A node has exactly one member.
- Change the value to `{"Variable": {"attrs": {}, "name": "a"}}`. You get an `UnknownMember` error. Morphir readers accept the old name `attrs` for one release, with a warning ([decision 0006](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/kb/bundles/morphir/morphir-ir/decisions/0006-node-member-names-follow-the-schema-with-a-one-release-window.md?plain=1#L4), [kit case types-0009](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/spec/ir/mck/types.feature#L145-L147)).
- Change the value to `{"Variable": {"attributes": {"constraints": 5}, "name": "a"}}`. You get a `TypeMismatch` error. Morphir also rejects this value ([kit case types-0012](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/spec/ir/mck/types.feature#L176-L184)).

Also try the type of `add`, `number -> number -> number`: a `Function` whose `returnType` is a second `Function`. It passes. A function type in the IR has one parameter ([schema, line 950](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L950-L970)). A function with two parameters is a function that returns a function.

The Morphir example file does not use the expanded spelling. Morphir writers use the compact spelling, unless you select the expanded output ([JSON profile](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/docs/spec/ir/schemas/v4/json-profile.md?plain=1#L31)). [Lesson 39](../39-morphir-limits/lesson.md) checks the compact spelling.

The tour also checks this model against the name and type examples of the Morphir sources. Each expanded example passes, and each other example fails.
