///|
let access_model : String =
  #|$version: "2"
  #|namespace example
  #|use smithy.serialization#jsonEncoding
  #|
  #|/// Canonically external; legacy readers also accept internal and adjacent tags and lower-case tags.
  #|@jsonEncoding(base: {union: {style: "external", accept: [
  #|  {style: "internal", tag: "access"}
  #|  {style: "adjacent", tag: "access", content: "value"}
  #|]}})
  #|union Access {
  #|  @jsonEncoding(base: {aliases: ["public", "pub"]})
  #|  Public: Documented
  #|  Private: Documented
  #|}
  #|
  #|structure Documented {
  #|  doc: String
  #|  @required
  #|  @jsonEncoding(base: {flatten: true, aliases: ["value"]})
  #|  definition: Definition
  #|}
  #|
  #|@jsonEncoding(base: {union: {style: "external", accept: [{style: "tagArray"}]}})
  #|union Definition {
  #|  Alias: Integer
  #|  Opaque: Unit
  #|}
  #|
  #|@jsonEncoding(base: {dictionary: {layout: "object", accept: ["entries"]}})
  #|map Table {
  #|  key: String
  #|  value: Integer
  #|}
  #|
  #|structure Pair {
  #|  @required
  #|  name: String
  #|  @required
  #|  value: Integer
  #|}
  #|
  #|@jsonEncoding(base: {forms: [
  #|  {member: "Named", read: {kind: "object", field: "name", absent: "Positional"}}
  #|]})
  #|union Argument {
  #|  Named: Pair
  #|  Positional: Integer
  #|}

///|
test "reader-only tags, layouts, flattened members and dictionary layouts" {
  let model = load(access_model)
  let access = @codec.PreparedCodec::prepare(model, id("example#Access"))
  let canonical = "{\"Public\":{\"doc\":\"d\",\"Alias\":1}}"
  for
    text in [
      canonical, "{\"public\":{\"doc\":\"d\",\"Alias\":1}}", "{\"access\":\"pub\",\"doc\":\"d\",\"Alias\":1}",
      "{\"access\":\"Public\",\"value\":{\"doc\":\"d\",\"Alias\":1}}",
    ] {
    assert_eq(access.canonicalize(text), canonical)
  }
  assert_eq(
    access.canonicalize("{\"Private\":{\"Opaque\":{}}}"),
    "{\"Private\":{\"Opaque\":{}}}",
  )
  let two = access.check("{\"Public\":{\"Alias\":1,\"Opaque\":{}}}")
  assert_eq(two.findings[0].code, Arity)
  let unknown = access.check("{\"Public\":{\"Other\":1}}")
  assert_eq(unknown.findings[0].code, UnknownTag)
  assert_eq(unknown.findings[0].path.pointer(), "/Public/Other")
  let table = @codec.PreparedCodec::prepare(model, id("example#Table"))
  assert_eq(table.canonicalize("[[\"b\",2],[\"a\",1]]"), "{\"a\":1,\"b\":2}")
  assert_eq(table.canonicalize("{\"b\":2}"), "{\"b\":2}")
  let argument = @codec.PreparedCodec::prepare(model, id("example#Argument"))
  assert_eq(
    argument.canonicalize("{\"name\":\"n\",\"value\":1}"),
    "{\"Named\":{\"name\":\"n\",\"value\":1}}",
  )
  assert_eq(argument.canonicalize("{\"Positional\":2}"), "{\"Positional\":2}")
}

///|
test "reader-only declarations are checked" {
  inspect(
    refusal(
      header +
      "union U { @jsonEncoding(base: {aliases: [\"B\"]}) A: Integer, B: Integer }",
      "example#U",
      None,
    ),
    content="InvalidDeclaration: example#U: Members A and B use the same wire name \"B\".",
  )
  inspect(
    refusal(
      header +
      "structure S { @jsonEncoding(base: {flatten: true}) a: U, @jsonEncoding(base: {flatten: true}) b: U }\nunion U { x: Integer }",
      "example#S",
      None,
    ),
    content="InvalidDeclaration: example#S: An object structure can flatten at most one member.",
  )
  inspect(
    refusal(
      header +
      "structure S { x: Integer, @jsonEncoding(base: {flatten: true}) b: U }\nunion U { x: Integer }",
      "example#S",
      None,
    ),
    content="InvalidDeclaration: example#S: Flattened tag x collides with member x.",
  )
  inspect(
    refusal(
      header +
      "@jsonEncoding(base: {union: {style: \"tagArray\", accept: [{style: \"tagArray\", unit: \"slot\"}]}})\nunion U { x: Integer }",
      "example#U",
      None,
    ),
    content="InvalidDeclaration: example#U: A union can read only one tag-array layout.",
  )
}
