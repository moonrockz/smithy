///|
fn load(text : String) -> @smithy.Model raise {
  let loaded = @contract.loader().add_idl("model.smithy", text).assemble()
  let errors = loaded.diagnostics.filter(d => d.severity == Error)
  if !errors.is_empty() {
    fail(errors.map(d => d.message).join("\n"))
  }
  for event in loaded.validation_events() {
    if event.severity == "ERROR" || event.severity == "DANGER" {
      fail(event.id + ": " + event.message)
    }
  }
  loaded.model.unwrap()
}

///|
fn id(text : String) -> @smithy.ShapeId {
  @smithy.ShapeId::parse(text).unwrap()
}

///|
fn profile(text : String) -> @contract.ProfileId raise {
  @contract.ProfileId::parse(text)
}

///|
let expr_model : String =
  #|$version: "2"
  #|namespace example
  #|use smithy.serialization#jsonProfiles
  #|use smithy.serialization#jsonEncoding
  #|
  #|@jsonProfiles([
  #|  {id: "object"}
  #|  {id: "array", defaults: {union: {style: "tagArray"}}}
  #|])
  #|union Expr {
  #|  Num: Count
  #|  Add: Add
  #|}
  #|
  #|@range(min: 0, max: 100)
  #|integer Count
  #|
  #|@jsonEncoding(profiles: {"array": {tuple: {members: ["left", "right"]}}})
  #|structure Add {
  #|  @required
  #|  left: Expr
  #|  @required
  #|  right: Expr
  #|}

///|
test "one model with object and tagged-array profiles" {
  let model = load(expr_model)
  let object = @codec.PreparedCodec::prepare(
    model,
    id("example#Expr"),
    profile=Some(profile("object")),
  )
  let array = @codec.PreparedCodec::prepare(
    model,
    id("example#Expr"),
    profile=Some(profile("array")),
  )
  let text = "{\"Add\":{\"left\":{\"Num\":1},\"right\":{\"Add\":{\"left\":{\"Num\":2},\"right\":{\"Num\":3}}}}}"
  let value = object.decode(text)
  assert_eq(object.encode(value), text)
  let arrays = array.encode(value)
  assert_eq(arrays, "[\"Add\",[\"Num\",1],[\"Add\",[\"Num\",2],[\"Num\",3]]]")
  assert_true(array.decode(arrays) == value)
  assert_eq(object.semantic_root(), array.semantic_root())
}

///|
test "a constraint inside a tagged array reports the array position" {
  let model = load(expr_model)
  let array = @codec.PreparedCodec::prepare(
    model,
    id("example#Expr"),
    profile=Some(profile("array")),
  )
  let result = array.check("[\"Add\",[\"Num\",1],[\"Num\",101]]")
  assert_false(result.is_valid())
  assert_eq(result.findings.length(), 1)
  assert_eq(result.findings[0].code, Constraint(Range))
  assert_eq(result.findings[0].path.pointer(), "/2/1")
  let missing = array.check("[\"Add\",[\"Num\",1]]")
  assert_eq(missing.findings[0].code, MissingMember)
  assert_eq(missing.findings[0].path.pointer(), "/2")
  let extra = array.check("[\"Add\",[\"Num\",1],[\"Num\",2],[\"Num\",3]]")
  assert_eq(extra.findings[0].code, Arity)
  assert_eq(extra.findings[0].path.pointer(), "/3")
}
