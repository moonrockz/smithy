# Parse a model

`parse_idl` reads Smithy IDL text and gives back the AST, the CST and the
diagnostics. Nothing is resolved: shape IDs are as written.

```mbt check
///|
test "read the shapes of a model" {
  let r = @syntax.parse_idl(
    (
      #|$version: "2"
      #|namespace com.example
      #|
      #|/// A person.
      #|structure Person {
      #|    @required
      #|    name: String
      #|    age: Integer = 0
      #|}
      #|
    ),
    name="person.smithy",
  )
  inspect(r.has_errors(), content="false")
  debug_inspect(r.version, content="Some(V2)")
  guard r.ast is Some(file) else { fail("no ast") }
  let person = file.shapes()[0]
  inspect(person.docs[0].text, content=" A person.")
  guard person.shape is Aggregate(kind=Structure, members~, ..) else {
    fail("not a structure")
  }
  debug_inspect(members.map(m => m.name.value), content="[\"name\", \"age\"]")
  debug_inspect(members[1].default.bind(d => d.as_string()), content="None")
}
```

The CST keeps every token with its whitespace and comments, so a tool can
print the file back unchanged, also when a statement did not parse:

```mbt check
///|
test "the CST is lossless" {
  let text =
    #|namespace a
    #|string Good
    #|string 42
    #|string AlsoGood
    #|
  let r = @syntax.parse_idl(text)
  inspect(r.cst.to_source() == text, content="true")
  inspect(r.errors().length(), content="1")
  inspect(r.cst.skipped()[0].to_source(), content="string 42\n")
  guard r.ast is Some(file) else { fail("no ast") }
  debug_inspect(
    file.shapes().map(s => s.shape.name().value),
    content="[\"Good\", \"AlsoGood\"]",
  )
}
```
