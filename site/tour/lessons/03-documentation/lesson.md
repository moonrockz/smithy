# Comments and documentation

The Smithy IDL has two kinds of comment.

A [line comment](https://smithy.io/2.0/spec/idl.html#comments) starts with `//`. It can go at any place where whitespace can go. A newline ends it. A line comment does not change the model. Look at the JSON AST output: the member `message` has no traits.

A documentation comment is a line that starts with `///`. Spaces can come before the `///`. The comment documents the shape or the member that comes directly after it. A documentation comment is the same as the trait `smithy.api#documentation`. The text of the comment becomes the value of the trait.

Look at the structure `Greeting` in the JSON AST output. It has the trait `smithy.api#documentation`, with the value `"A greeting for one person."`. Smithy removes the space after `///`.

Now change the comment above `message` from `//` to `///`. The member `message` now has the trait `smithy.api#documentation`, with the value `"The text of the greeting."`.

Some rules for documentation comments:

- Put the comment directly before the shape or the member.
- Put the comment before the traits of the shape.
- Smithy joins two or more `///` lines into one value. A newline goes between the lines.
- Write the text in CommonMark. You can use lists, links and code in it.
