# moonrockz/smithy-syntax

Smithy IDL syntax for MoonBit: a lossless scanner, a typed AST with spans, a
CST that prints the source back byte for byte, a parser with recovery per
statement, and diagnostics in the style of Elm and Rust.

## Status

- Scanner: done.
- AST: done.
- CST: done.
- Parser: done.
- Diagnostics: done.
- Traversal and the JSON AST: planned, in a later sub-project.

## Example

```mbt check
test {
  let r = @syntax.parse_idl(
    (
      #|$version: "2"
      #|namespace com.foo
      #|
      #|string Name
      #|
    ),
    name="a.smithy",
  )
  inspect(r.has_errors(), content="false")
}
```

## Installation

```shell
moon add moonrockz/smithy-syntax
```

## Packages

| Package | Import path | Holds |
|---|---|---|
| `span` | `moonrockz/smithy-syntax/span` | `Span`, `Position`, `SourceText` |
| `diagnostic` | `.../diagnostic` | `Severity`, `Label`, `Diagnostic`, `codes()` |
| `scanner` | `.../scanner` | `TokenKind`, `Token`, `Trivia`, `Comment`, `TokenStream`, `tokenize`, `unescape`, `text_block_value` |
| `ast` | `.../ast` | the typed IDL tree |
| `cst` | `.../cst` | `IdlCst`, `StatementCst`, `StatementKind` |
| `parser` | `.../parser` | `parse`, `parse_tokens`, `ParseResult`, `Version`, `max_nesting` |
| `report` | `.../report` | `render_terminal`, `render_plain`, `render_short` |
| root | `moonrockz/smithy-syntax` | `parse_idl`, re-exports of every public type |

Dependencies point one way: `span` ← `diagnostic` ← `scanner` ← `ast` ← `cst` ← `parser` ← `report` ← root.
Each package has a `README.mbt.md` with checked examples. See the design in
`docs/superpowers/specs/2026-10-15-idl-syntax-design.md`, and the cookbook in `docs/cookbook` for task
articles.
