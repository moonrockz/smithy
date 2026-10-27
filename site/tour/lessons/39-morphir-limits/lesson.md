# Where Smithy stops

In Smithy, a union value is an object with exactly one member ([trait node values](https://smithy.io/2.0/spec/model.html#trait-node-values), [lesson 10](../10-unions/lesson.md)). The Morphir IR has more spellings than that. `deal.json` holds the type `deal` as the [Morphir example](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/ir/examples/v4/books-and-records-example.json#L83-L95) writes it.

> **Our extension:** Smithy defines no validation of JSON values. This check is part of moonrockz/smithy-validation. [Lesson 26](../26-validating-values/lesson.md) shows the same check from the CLI and from MoonBit.

The value gives three `TypeMismatch` errors: `I expected a union value, but found string.` Each field type is a bare FQName string, the compact spelling of a reference with no arguments ([schema, line 832](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L832-L843)). A Morphir reader must accept it ([JSON profile](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/docs/spec/ir/schemas/v4/json-profile.md?plain=1#L31)), but a Smithy union cannot be a string. The value check does not read other spellings.

Change the value to each of these other spellings:

- `{"Reference": ["morphir/SDK:list#list", "a"]}`, a reference with arguments in the array form: `I expected a structure value, but found array.`
- `{"Reference": "morphir/SDK:basics#int"}`: `I expected a structure value, but found string.`
- `{"Variable": {"name": ["a"]}}`, a name in the legacy array form ([schema, line 59](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L59-L72)): `I expected a string value, but found array.`
- The type of `append` from a [version 3 example](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/ir/examples/v3/greeting-example.json). Version 3 writes each node as an array that starts with its kind ([version 4 changes](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/docs/spec/ir/schemas/v4/whats-new.md?plain=1#L496-L508)). You get `I expected a union value, but found array.`

The schema does not agree with itself on a reference with arguments. A comment at [line 735](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L735) gives the object form `{"Reference": {"fqname": "...", "args": [...]}}`. The description at [line 835](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L835) calls the array form above canonical. JSON Schema does not check a comment or a description against the definitions, so no schema check finds this difference. In a Smithy model, the shape is the one definition. This tour follows the object form, which is the `ReferenceType` structure in `type.smithy`. Change the value to `{"Reference": {"fqname": "morphir/SDK:list#list", "args": [{"Variable": {"name": "a"}}]}}`. You get no finding.

The SDK model has two more limits ([lesson 37](../37-morphir-sdk/lesson.md)):

- A type variable is a `Document` member. Smithy checks its name, but not its value.
- A Morphir function type has one parameter ([lesson 38](../38-morphir-values/lesson.md)). A Smithy operation takes [one input structure](https://smithy.io/2.0/spec/service-types.html#operation), so it cannot show a partly applied function, such as `add 1`.

[Lesson 40](../40-morphir-profiles/lesson.md) reads these spellings with a serialization profile, and [lesson 41](../41-morphir-version-3/lesson.md) reads version 3.
