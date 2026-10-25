# Describing Basics and String

This lesson uses the vocabulary of [lesson 36](../36-morphir-vocabulary/lesson.md) for six functions of the Morphir SDK. An SDK module becomes a service, and a function becomes an [operation](https://smithy.io/2.0/spec/service-types.html#operation).

The functions and their types come from the SDK of morphir-elm ([Basics](https://github.com/finos/morphir-elm/blob/89e2b5043a76f138dd4b5137bb4b29a4d7a94909/src/Morphir/IR/SDK/Basics.elm#L62-L112), [String](https://github.com/finos/morphir-elm/blob/89e2b5043a76f138dd4b5137bb4b29a4d7a94909/src/Morphir/IR/SDK/String.elm#L50-L55)):

- `add : number -> number -> number`, `negate : number -> number` and `and : Bool -> Bool -> Bool` in `Basics`.
- `isEmpty : String -> Bool`, `length : String -> Int` and `append : String -> String -> String` in `String`.

The input members are the parameters, in the order and with the names of morphir-elm. The output member `result` is the return value. A value specification in IR version 4 also has named `inputs` and one `output` ([schema, line 2051](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L2051-L2075)). A version 4 name has no mixed-case segment, so `isEmpty` becomes `is-empty` ([schema, line 49](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L49-L57)).

`number` is a type variable. A Smithy shape has no type parameters. For this reason, each `number` member is a [`Document`](https://smithy.io/2.0/spec/simple-types.html#document) with `@typeVariable("number")`. Smithy checks the spelling of the variable name. A `Document` can hold any JSON-like value. So Smithy does not check that `a`, `b` and `result` have the same type.

The output tab runs this selector: `service[trait|morphir.dsl#sdkModule] ~> operation`. It finds each service with `@sdkModule`, and then each operation that the service connects to ([forward recursive neighbors](https://smithy.io/2.0/spec/selectors.html#forward-recursive-neighbors), [lesson 23](../23-selectors/lesson.md)). The output is the six functions.

Now add `reverse : String -> String` ([morphir-elm](https://github.com/finos/morphir-elm/blob/89e2b5043a76f138dd4b5137bb4b29a4d7a94909/src/Morphir/IR/SDK/String.elm#L52)). In `string.smithy`, add an operation `Reverse` with `@function(name: "reverse", native: true)`, the input member `s: String` and the output member `result: String`. Add `Reverse` to the `operations` of `StringModule`. The output then also shows `morphir.sdk.string#Reverse`.
