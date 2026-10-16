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
