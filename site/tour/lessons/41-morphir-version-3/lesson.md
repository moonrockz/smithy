# Reading version 3

`append.json` holds the type of `append` from a [version 3 example](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/ir/examples/v3/greeting-example.json). Version 3 writes each node as an array that starts with its kind ([version 4 changes](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/docs/spec/ir/schemas/v4/whats-new.md?plain=1#L496-L508)). [Lesson 39](../39-morphir-limits/lesson.md) refused this value. This lesson checks it against `morphir.ir.v3#Type` with the profile `morphir-v3`, and the value passes.

> **Our extension:** Smithy defines no validation of JSON values and no serialization profiles. The `smithy.serialization` traits and the JSON codec are part of moonrockz/smithy-codec. The [Morphir codec example](../../../../examples/morphir-codecs/README.md) models all of version 3 this way.

The profile `morphir-v3` makes each union of the model an array that starts with its tag (`defaults` in `jsonProfiles`). A `tuple` rule gives the array positions of each structure after the tag. So `["Function", {}, argument, result]` is a `FunctionType` with the members `attributes`, `argumentType` and `returnType`. A version 3 name is a list of words, such as `["s", "d", "k"]`. The adapter `morphir.v3.name` reads it.

Make these changes one at a time:

- Change the value to `["Unit", {}]`. It passes.
- Change the value to `["Unit", {}, {}]`. A Unit node has one position after its tag. You get `Arity`.
- Change the value to `["Variable", {}, ["A"]]`. A version 3 word is lowercase. You get `AdapterFailure`.
- Change the value to `"a"`, the compact version 4 spelling of a type variable. Version 3 has no compact spelling, so you get `KindMismatch`.

The two lessons use different models for the two versions. A version 3 value and a version 4 value of the same type are different JSON documents, and the profile does not convert one into the other.
