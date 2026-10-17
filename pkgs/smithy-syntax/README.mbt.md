# moonrockz/smithy-syntax

Smithy syntax for MoonBit: a lossless IDL scanner, a typed AST with spans, a
CST that prints the source back byte for byte, a parser with recovery per
statement, diagnostics in the style of Elm and Rust, and a typed JSON AST codec.

## Status

- Scanner: done.
- AST: done.
- CST: done.
- Parser: done.
- Diagnostics: done.
- Traversal: done (`traversal`: `NodeRef`, `walk`, `fold`, `reduce`, `accept`, events, `Tree`, `TreeCursor`).
- JSON AST: done (`json_ast`: typed records, decoder and encoder with exact numeric text round trips).

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
| `traversal` | `.../traversal` | `NodeRef`, `walk`, `fold`, `reduce`, `reduce_pruned`, `accept`, `EventReader`, `push_events`, `Tree`, `TreeCursor`, `NodePath`, `kind_table` |
| `report` | `.../report` | `render_terminal`, `render_plain`, `render_short` |
| `json_ast` | `.../json_ast` | `JsonAst`, shape records, `parse`, `decode`, `encode`, `stringify` |
| root | `moonrockz/smithy-syntax` | `parse_idl`, `parse_json_ast`, `decode_json_ast`, `encode_json_ast`, public type re-exports |

Dependencies point one way: `span` ← `diagnostic` ← `scanner` ← `ast` ← `cst` ← `parser` ← `traversal` and `report` ← root (`traversal` and `report` do not import each other).
Each package has a `README.mbt.md` with checked examples. See the design in
[DESIGN.md](DESIGN.md), and the cookbook in `docs/cookbook` for task
articles.

The JSON AST package depends on core JSON and the IDL AST's simple-type enum.
Its [package guide](src/json_ast/README.mbt.md) defines the codec's preservation
and validation rules. The semantic loader and IDL-to-JSON conversion are available
in `moonrockz/smithy`.

The facade also exports `parse_tokens`, `codes` and `render_all_to`. Use the
scanner package for its pipeline records `Piece` and `Step`, and the parser
package for `Depth` and `ParseError`. Property-test generators are internal.

`ShapeKind::keyword()` and its `Show` implementation return IDL keywords.
`NumberLiteral::as_double()` returns signed infinity on overflow. The exact
number stays in `NumberLiteral::value`. Partial trees may contain duplicate
member names; check `has_errors()` before relying on member uniqueness.
