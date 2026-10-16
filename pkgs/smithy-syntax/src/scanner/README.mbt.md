# scanner

The lossless scanner, a pipeline of pure stages: `scan_pieces` unfolds
`scan_at` over the text into steps (a token or a trivia piece each),
`attach_trivia` groups them into tokens with their comments and whitespace,
and `tokenize` is the two composed. The scan never fails: a problem becomes
an `Error` token and a diagnostic, and `TokenStream::to_source()` is always
the text, byte for byte.

```mbt check
///|
test {
  let s = @scanner.tokenize_text("string Foo\n")
  inspect(s.to_source(), content="string Foo\n")
  debug_inspect(
    s.tokens.iter().map(t => t.kind).collect(),
    content=(
      #|[Identifier, Identifier]
    ),
  )
  inspect(s.has_errors(), content="false")
}
```
