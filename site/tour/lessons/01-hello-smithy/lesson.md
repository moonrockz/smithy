# Hello, Smithy

A Smithy model has one or more files. A file uses the Smithy IDL or the JSON AST. This tour writes models in the Smithy IDL. This model has one file.

An IDL file has three sections, in this order: the control section, the metadata section, and the shape section. Each section is optional. This file has no metadata section.

The control section is the first line: `$version: "2"`. It tells the tools which version of the Smithy IDL the file uses.

The shape section starts with a `namespace` statement. A namespace groups shapes. Here, the namespace is `example`. After the namespace, you define shapes.

A shape is one named item of the model. This model has one shape: the structure `Greeting`. A structure is a group of named members. The member `message` has the type `String`.

The full name of a shape is its namespace, a `#` character, and its name. The full name of this shape is `example#Greeting`. Look at the JSON AST output. It uses this name as a key.

Now break the model. Delete the line `namespace example`. A namespace must come before the first shape. The Findings tab now shows one error. The error says that the parser found `structure` but no `namespace` statement before it. Put the line back, and the error goes away.
