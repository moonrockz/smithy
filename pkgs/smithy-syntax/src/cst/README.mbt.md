# cst

The token stream grouped per statement. `IdlCst::to_source()` is the text
byte for byte, also when the parser skipped a statement.

```mbt check
///|
test {
  let s = @scanner.tokenize_text("string Foo\n")
  let st = @cst.StatementCst::new(
    kind=Shape(Simple(String)),
    name=Some("Foo"),
    tokens=s.tokens,
  )
  inspect(@cst.IdlCst::new(s, [st]).to_source(), content="string Foo\n")
}
```
