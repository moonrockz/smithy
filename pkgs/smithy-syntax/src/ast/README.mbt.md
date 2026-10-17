# ast

The typed Smithy IDL tree. Every node has a `span`; every list is a
read-only `ArrayView`; shape IDs are syntactic and unresolved.

```mbt check
///|
test {
  let id = @ast.ShapeId::new("String", namespace="smithy.api")
  inspect(id, content="smithy.api#String")
}
```

`ShapeKind::keyword()` returns the IDL spelling for every shape kind.
`NumberLiteral::as_double()` rounds exact values to a floating point number
and returns signed infinity on overflow. The exact `value` remains available.
Member names are unique when `ParseResult::has_errors()` is false. A partial
AST keeps duplicate members after reporting `SM-PARSE-014`.
