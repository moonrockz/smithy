# Mixins

A [mixin](https://smithy.io/2.0/spec/mixins.html) is a shape with the trait `@mixin`. When a shape uses a mixin, Smithy copies the members and the traits of the mixin into the shape. It does not copy `@mixin` or the [local traits](https://smithy.io/2.0/spec/mixins.html#mixin-local-traits) of the mixin. Write the mixins in square brackets after `with`.

In this model, `City` uses the mixin `Audited`. The output tab shows the model flattened. Look at `City`. It has the members `createdAt`, `updatedAt` and `name`. The members from the mixin [come first](https://smithy.io/2.0/spec/mixins.html#member-ordering). `City` keeps its own documentation, because a trait on the shape [takes precedence](https://smithy.io/2.0/spec/mixins.html#traits-and-mixins) over the trait of its mixin. `Audited` is still in the model, with `@smithy.api#mixin`.

This output flattens the model on purpose. The specification recommends the same for code generators, because [mixins are an implementation detail](https://smithy.io/2.0/spec/mixins.html#mixins-are-an-implementation-detail-of-the-model) of the model.

Make these changes one at a time. Change the model back after each change.

- Add the line `apply City$createdAt @documentation("When the city was added.")` at the end. In the output, only `City$createdAt` has the documentation. The member of `Audited` does not change. You can [add traits to copied members](https://smithy.io/2.0/spec/mixins.html#adding-and-replacing-traits-on-copied-members) in this way.
- Add the member `createdAt: String` to `City`, after `name`. A shape can [redefine a mixin member](https://smithy.io/2.0/spec/mixins.html#mixin-members-must-not-conflict) only with the same target, here `Timestamp`. The Findings tab shows an error with the event ID `Model` on `example#City$createdAt`.
- Delete the line `@mixin`. Now `with` names a shape that is not a mixin. The Findings tab shows an error with the event ID `Target` on `example#City`.
- Add this structure at the end:

  ```smithy
  structure Place {
      audit: Audited
  }
  ```

  A member [cannot target a mixin](https://smithy.io/2.0/spec/mixins.html#mixins-cannot-be-referenced-other-than-as-mixins-to-other-shapes). The Findings tab shows an error with the event ID `Target` on `example#Place$audit`.
