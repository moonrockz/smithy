# Your own vocabulary

You can define your own traits ([lesson 14](../14-defining-traits/lesson.md)). A set of traits is a vocabulary, and Smithy checks each use of it. This lesson adds one for the Morphir SDK. The SDK gives the basic types and functions that each backend should support ([Morphir SDK](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/docs/concepts/morphir-sdk.md?plain=1#L8-L10)).

`dsl.smithy` defines four traits:

- `@sdkModule` marks a service as a module of an SDK package.
- `@sdkType` marks a simple shape that stands for an SDK type, such as `int`.
- `@function` marks an operation as an SDK function. `native: true` shows that the backend gives the implementation.
- `@typeVariable` marks a member whose type is a type variable, such as `number`.

The selector of a trait tells which shapes can have it ([trait definitions](https://smithy.io/2.0/spec/model.html#defining-traits)). The trait values use `Name` and `Path` from [lesson 35](../35-morphir-names/lesson.md). So Smithy also checks each name in a trait value.

`basics.smithy` describes three functions of the morphir-elm module `Basics`: [`add`](https://github.com/finos/morphir-elm/blob/89e2b5043a76f138dd4b5137bb4b29a4d7a94909/src/Morphir/IR/SDK/Basics.elm#L62), [`negate`](https://github.com/finos/morphir-elm/blob/89e2b5043a76f138dd4b5137bb4b29a4d7a94909/src/Morphir/IR/SDK/Basics.elm#L75) and [`and`](https://github.com/finos/morphir-elm/blob/89e2b5043a76f138dd4b5137bb4b29a4d7a94909/src/Morphir/IR/SDK/Basics.elm#L112). Each has a native implementation in morphir-elm ([native functions](https://github.com/finos/morphir-elm/blob/89e2b5043a76f138dd4b5137bb4b29a4d7a94909/src/Morphir/IR/SDK/Basics.elm#L130-L131)). In Morphir, `Int`, `Float` and `Bool` are opaque types ([`Int` and `Float`](https://github.com/finos/morphir-elm/blob/89e2b5043a76f138dd4b5137bb4b29a4d7a94909/src/Morphir/IR/SDK/Basics.elm#L44-L45), [`Bool`](https://github.com/finos/morphir-elm/blob/89e2b5043a76f138dd4b5137bb4b29a4d7a94909/src/Morphir/IR/SDK/Basics.elm#L56)). This tour uses `long`, `double` and `boolean` for them. [Lesson 37](../37-morphir-sdk/lesson.md) tells you how a function becomes an operation.

Make these changes in `basics.smithy` one at a time. Change the model back after each change.

- Change `name: "add"` to `name: "Add"`. You get a `TraitValue` error, because `Add` is not a valid name.
- Change the first `@typeVariable("number")` to `@typeVariable("Number")`. You get a `TraitValue` error on the member `a`. The trait has the pattern of a compact type variable in the schema ([schema, line 753](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L753)).
- On the service `Basics`, replace the `@sdkModule(...)` line with `@sdkType(name: "basics")`. You get a `TraitTarget` error, because `@sdkType` is only for simple shapes.
