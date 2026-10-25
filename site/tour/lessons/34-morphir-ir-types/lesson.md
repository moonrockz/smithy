# The IR as recursive tagged unions

[Morphir](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/README.md?plain=1#L11) is a library of tools that captures business logic as data. That data is the Morphir IR. This lesson and the next five lessons describe a part of the IR in Smithy. They use IR version 4, which is a [draft](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/docs/spec/ir/schemas/v4/index.md?plain=1#L8).

A type expression in the IR is one of seven kinds: `Variable`, `Reference`, `Tuple`, `Record`, `ExtensibleRecord`, `Function` and `Unit` ([schema, line 739](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L739-L747)). In `type.smithy`, the union `Type` has one member for each kind. Each member targets a structure with the data of that kind. A union value has exactly one member ([lesson 10](../10-unions/lesson.md)).

The kinds refer back to `Type`. For example, `FunctionType` has a `parameterType` and a `returnType`, and both are a `Type`. Smithy permits this [recursion](https://smithy.io/2.0/spec/aggregate-types.html#recursive-shape-definitions). A recursive union must also have a member that can end the recursion, such as `Unit`.

Look at the JSON Schema output. The union `Type` becomes a `oneOf` with one entry for each member. Each entry is an object that requires one property: the name of the kind. The IR uses the same form. A node is an object with one member, and the name of that member is the kind of the node ([decision 0005](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/kb/bundles/morphir/morphir-ir/decisions/0005-attributes-are-an-optional-first-member-of-every-node-payload.md?plain=1#L43-L44)).

Now write a recursion that Smithy does not permit. Add this structure at the end of `type.smithy`:

```smithy
structure Loop {
    @required
    next: Loop
}
```

The Findings tab shows an error with the event ID `ShapeRecursion` on `morphir.ir.v4#Loop`. A `Loop` value can never end, because each `Loop` must contain one more `Loop`. Now remove `@required`. The error goes away, and the schema gets a `Loop` definition.

Each kind has an optional member `attributes`. Its `TypeAttributes` hold data such as the source location of the type ([schema, line 154](https://github.com/finos/morphir/blob/ab8d5c9198c0f1ac8a3cabfd11b9ab59a468c409/website/static/schemas/morphir-ir-v4.yaml#L154-L167)). [Lesson 38](../38-morphir-values/lesson.md) checks IR values against this model.
