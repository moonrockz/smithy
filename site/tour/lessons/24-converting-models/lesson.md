# Converting models

A Smithy model has two forms. People write the [Smithy IDL](https://smithy.io/2.0/spec/idl.html). The [JSON AST](https://smithy.io/2.0/spec/json-ast.html) is for tools that do not have an IDL parser. The two forms hold the same shapes and traits.

The output tab shows the JSON AST of the model. The key of each shape in `shapes` is its [absolute shape ID](https://smithy.io/2.0/spec/model.html#shape-id) such as `example#City`. The JSON AST uses only absolute shape IDs, so the target `String` becomes `smithy.api#String`.

Each trait is a key in `traits`, with its absolute shape ID. The `///` comment becomes the trait `smithy.api#documentation` ([lesson 03](../03-documentation/lesson.md)). The trait `@required` has no value, so it becomes `"smithy.api#required": {}`.

After `population: Integer`, add the member `country: CountryCode`. At the end, add `@length(min: 2, max: 2)` and `string CountryCode` on two lines. The output now has the shape `example#CountryCode` with the trait `smithy.api#length`, and `country` has the target `example#CountryCode`.

Undo these changes, and add `apply City$name @length(min: 1, max: 64)` at the end. The [`apply` statement](../13-applying-traits/lesson.md) puts the trait on the member `name`. In the output, `name` has both traits: `smithy.api#required` and `smithy.api#length`.

## On your computer

The `smithy` CLI and the MoonBit library also convert the IDL to the JSON AST. The tests of this repository run all the blocks of this section.

```include
CLI: apps/smithy/README.md#convert-json-cli
MoonBit: pkgs/smithy/README.mbt.md#convert-json-api
```

These tabs convert the JSON AST back to the IDL. This tool writes absolute shape IDs in the IDL, such as `smithy.api#String`.

```include
CLI: apps/smithy/README.md#convert-idl-cli
MoonBit: pkgs/smithy/README.mbt.md#convert-idl-api
```

## Projections

The command `smithy build` reads the [projections](https://smithy.io/2.0/guides/smithy-build-json.html#projections) of the file `smithy-build.json`. A projection is a copy of the model that its transforms change. The transform [`excludeShapesByTrait`](https://smithy.io/2.0/guides/smithy-build-json.html#excludeshapesbytrait) removes the shapes that have a given trait. The projection `source` is the model with no change. The tour does not run a build in the browser.

```include
CLI: apps/smithy/README.md#build-projection-cli
MoonBit: pkgs/smithy-build/README.mbt.md#build-projection-api
```
