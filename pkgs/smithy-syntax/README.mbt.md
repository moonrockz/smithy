# moonrockz/smithy-syntax

Smithy IDL syntax for MoonBit: a lossless scanner, a typed AST with spans, a
CST that prints the source back byte for byte, a parser with recovery per
statement, and diagnostics in the style of Elm and Rust.

```mbt check
test {
  inspect(@syntax.version(), content="0.1.0")
}
```

Packages: `span`, `diagnostic`, `scanner`, `ast`, `cst`, `parser`, `report`
and the root facade. See the design in
`docs/superpowers/specs/2026-10-15-idl-syntax-design.md`.
