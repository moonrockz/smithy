# Mixins

A [mixin](https://smithy.io/2.0/spec/mixins.html) is a shape with the trait `@mixin`. When a shape uses a mixin, Smithy copies the members and the traits of the mixin into the shape. Write the mixins of a shape in square brackets after `with`.

In this model, `Audited` is a mixin with the members `createdAt` and `updatedAt`. The structure `City` uses it: `structure City with [Audited]`.

The output tab shows the model flattened. Each shape has the members that its mixins copy into it. Look at `City`. It has the members `createdAt`, `updatedAt` and `name`. The members from the mixin come first. `City` keeps its own documentation, because a trait on the shape [takes precedence](https://smithy.io/2.0/spec/mixins.html#traits-and-mixins) over the same trait of its mixin. The mixin `Audited` is still in the model, with `@smithy.api#mixin`.

The flattened view is a choice of this output. [Mixins are an implementation detail](https://smithy.io/2.0/spec/mixins.html#mixins-are-an-implementation-detail-of-the-model) of the model. The specification recommends that code generators and converters flatten the model.

Make these changes one at a time. Change the model back after each change.

- Add the line `apply City$createdAt @documentation("When the city was added.")` at the end of the model. The trait goes only on the copy of `createdAt` in `City`. Look at the output. `City$createdAt` has the documentation. The member `createdAt` of `Audited` does not change. The specification shows how to [add traits to copied members](https://smithy.io/2.0/spec/mixins.html#adding-and-replacing-traits-on-copied-members).
- Add the member `createdAt: String` to `City`, after `name`. A shape can [redefine a member](https://smithy.io/2.0/spec/mixins.html#mixin-members-must-not-conflict) of its mixin only with the same target. The mixin member targets `Timestamp`. The Findings tab shows an error with the event ID `Model` on `example#City$createdAt`.
- Delete the line `@mixin`. Now `Audited` is a plain structure, and `with` accepts only mixins. The Findings tab shows an error with the event ID `Target` on `example#City`.
- Add this structure at the end of the model:

  ```smithy
  structure Place {
      audit: Audited
  }
  ```

  A member [cannot target a mixin](https://smithy.io/2.0/spec/mixins.html#mixins-cannot-be-referenced-other-than-as-mixins-to-other-shapes). The Findings tab shows an error with the event ID `Target` on `example#Place$audit`.
