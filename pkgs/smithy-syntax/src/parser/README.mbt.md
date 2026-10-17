# parser

`parse_text` parses Smithy IDL into a `ParseResult`: the AST (`ast`), the
CST (`cst`, lossless), the declared `version` and the `diagnostics`. An
error inside a statement is reported once and the parser resumes at the
next statement.

```mbt check
///|
test {
  let r = @parser.parse_text(
    (
      #|$version: "2"
      #|namespace com.foo
      #|
      #|string Name
      #|
    ),
  )
  inspect(r.has_errors(), content="false")
  guard r.ast is Some(f) else { fail("no ast") }
  inspect(f.shapes()[0].shape.name().value, content="Name")
}
```
