# Reading the compact IR

[Lesson 39](../39-morphir-limits/lesson.md) showed that a plain value check cannot read the compact spellings of the Morphir IR. This lesson reads them with a serialization profile. `deal.json` holds the type `deal` as the [Morphir example](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/ir/examples/v4/books-and-records-example.json#L83-L95) writes it, and the check selects the profile `morphir-v4` of `type.smithy`.

> **Our extension:** Smithy defines no validation of JSON values and no serialization profiles. The `smithy.serialization` traits and the JSON codec are part of moonrockz/smithy-codec. The [Morphir codec example](../../../../examples/morphir-codecs/README.md) models all of version 3 and version 4 this way.

The value passes. The `Type` union in `type.smithy` declares compact forms with the `jsonEncoding` trait. A bare string that is a Morphir name is a `Variable`. A bare string that is an FQName, `package:module#name`, is a `Reference` ([schema, line 832](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L832-L843)). A name cannot contain `:` or `#`, so one string never has two meanings. The scalar adapters `morphir.v4.name` and `morphir.v4.fqname` check the two spellings. The model can name an adapter, but only the host can supply it.

Change the value to each of the spellings that lesson 39 refused. Each one now passes:

- `{"Reference": ["morphir/SDK:list#list", "a"]}`, a reference with arguments in the array form.
- `{"Reference": "morphir/SDK:basics#int"}`.
- `{"Variable": {"name": ["a"]}}`, a name in the legacy array form ([schema, line 59](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L59-L72)). The adapter reads the words as the name `a`.
- `{"Reference": {"fqname": "morphir/SDK:list#list", "args": [{"Variable": {"name": "a"}}]}}`, the expanded form. A profile adds spellings. It does not remove the normal layout of a structure.

The adapters still refuse a spelling that is not a Morphir name:

- Change the value to `"value-in-Usd"`. A segment of a name is all lowercase or all uppercase, so neither string form reads it. You get `KindMismatch`.
- Change the value to `{"Record": {"fields": {"Price": "a"}}}`. The field map uses the name adapter for its keys. You get `AdapterFailure` for the key `Price`.

A profile changes how the JSON spells a value, not what the value is. [Lesson 41](../41-morphir-version-3/lesson.md) reads the version 3 spelling.
