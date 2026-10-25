# Where Smithy stops

In Smithy, a union value is an object with exactly one member ([trait node values](https://smithy.io/2.0/spec/model.html#trait-node-values), [lesson 10](../10-unions/lesson.md)). The Morphir IR has more spellings than that. `deal.json` holds the type `deal` as the Morphir example file writes it ([example](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/ir/examples/v4/books-and-records-example.json#L83-L95)).

> **Our extension:** Smithy defines no validation of JSON values. This check is part of moonrockz/smithy-validation. [Lesson 26](../26-validating-values/lesson.md) shows the same check from the CLI and from MoonBit.

The value gives three `TypeMismatch` errors: `I expected a union value, but found string.` Each field type is a bare FQName string. This is the compact spelling of a reference with no arguments ([schema, line 832](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L832-L843)). A Morphir reader must accept it ([JSON profile](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/docs/spec/ir/schemas/v4/json-profile.md?plain=1#L31)), but a Smithy union cannot be a string. The value check does not read other spellings. That is a different project.

Change the value to each of these compact spellings:

- `{"Reference": ["morphir/SDK:list#list", "a"]}`, a reference with arguments: `I expected a structure value, but found array.`
- `{"Reference": "morphir/SDK:basics#int"}`: `I expected a structure value, but found string.`
- `{"Variable": {"name": ["a"]}}`, a name in the legacy array form ([schema, line 59](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L59-L72)): `I expected a string value, but found array.`
- The type of `append` from a version 3 example ([example](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/ir/examples/v3/greeting-example.json)). Version 3 writes each node as an array that starts with its kind, such as `["Function", {}, ...]` ([what is new in version 4](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/docs/spec/ir/schemas/v4/whats-new.md?plain=1#L496-L508)): `I expected a union value, but found array.`

Two more limits are in the model of the SDK ([lesson 37](../37-morphir-sdk/lesson.md)):

- A Smithy shape has no type parameters. A type variable such as `number` is a `Document` member with `@typeVariable`. Smithy checks the name, but it does not check the value.
- A Morphir function takes one parameter. A function of more parameters is a function that returns a function ([version 3 schema, line 377](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v3.yaml#L367-L378)). A Smithy operation has [one input structure](https://smithy.io/2.0/spec/service-types.html#operation). So an operation has no form for a function with only some of its arguments, such as `add 1`.
