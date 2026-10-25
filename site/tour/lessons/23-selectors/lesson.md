# Selectors

A [selector](https://smithy.io/2.0/spec/selectors.html) matches shapes in a model. It can match shapes by type, by attribute and by relationship. Smithy uses selectors to build custom validators and to tell where a [trait](../14-defining-traits/lesson.md) can apply. A build projection can also use a selector to [keep shapes](https://smithy.io/2.0/guides/smithy-build-json.html#includeshapesbyselector).

The tab `query.selector` holds the selector. Edit it, and the output tab shows the shape ID of each match. It shows one ID on each line, in sorted order.

The selector `operation` matches each shape of [the type](https://smithy.io/2.0/spec/selectors.html#matching-shapes-by-type) `operation`. Write `operation`, and the output shows all four operations.

`[trait|readonly]` is an [attribute selector](https://smithy.io/2.0/spec/selectors.html#attribute-selectors). It keeps the shapes that have the [trait](https://smithy.io/2.0/spec/selectors.html#trait-attribute) `@readonly`. The start query gives three operations. `example#CreateCity` is not in the output, because it has no `@readonly`.

`-[read]->` is a [forward directed neighbor](https://smithy.io/2.0/spec/selectors.html#forward-directed-neighbors). The brackets name one or more [relationships](https://smithy.io/2.0/spec/selectors.html#relationships), and the selector follows only those from a shape. The query `resource -[read]-> operation` gives `example#GetCity`. A [forward undirected neighbor](https://smithy.io/2.0/spec/selectors.html#forward-undirected-neighbor) `>` gives every shape that the current shape refers to. The query `operation -[input]-> structure > member` gives the members of each input structure, such as `example#GetCityInput$cityId`.

The model also holds the shapes of the [prelude](https://smithy.io/2.0/spec/model.html#prelude). The query `string` gives `example#CityId`, `smithy.api#String` and the other string shapes of the prelude.

> **Reference difference:** This tool also loads the shapes of the JSON-RPC trait definitions in the namespace `smithy.rpc` ([lesson 22](../22-json-rpc/lesson.md)) into every model. A selector can match them: `string` also gives `smithy.rpc#MethodName`. Standard Smithy does not have these shapes.

The [`id` attribute](https://smithy.io/2.0/spec/selectors.html#id-attribute) keeps your own shapes. The query `string[id|namespace = example]` gives only `example#CityId`.

Now delete the last `]` of the start query. The selector does not parse. The output tab shows the reason: the tool expected an attribute comparator. The Findings tab stays empty, because the model is valid.

## On your computer

The `smithy` CLI and the MoonBit library also run a selector. Select a tab to see each one. The tests of this repository run both blocks.

```include
CLI: apps/smithy/README.md#select-cli
MoonBit: pkgs/smithy/README.mbt.md#select-api
```
