///|
fn assemble(name : String, text : String) -> @smithy.Model raise {
  let result = @smithy.Loader::new().add_idl(name, text).assemble()
  guard result.model is Some(model) else {
    fail(result.validation_events().map(e => e.message).join("\n"))
  }
  model
}

///|
test "source locations comments and whitespace do not cause semantic changes" {
  let a = assemble(
    "before.smithy", "$version: \"2\"\nnamespace example\nstructure Value { name: String }",
  )
  let b = assemble(
    "after.smithy", "$version: \"2\"\nnamespace example\n// moved\n\nstructure Value {\n  name: String\n}",
  )
  let d = @diff.Differences::detect(a, b)
  assert_true(
    d.added.is_empty() &&
    d.removed.is_empty() &&
    d.changed.is_empty() &&
    d.metadata.is_empty(),
  )
  assert_true(@diff.compare(a, b).events.is_empty())
}

///|
test "a changed member also changes its container but keeps the member target typed" {
  let a = assemble(
    "a.smithy", "$version: \"2\"\nnamespace example\nstructure Value { name: String }",
  )
  let b = assemble(
    "b.smithy", "$version: \"2\"\nnamespace example\nstructure Value { name: Integer }",
  )
  let d = @diff.Differences::detect(a, b)
  assert_eq(d.changed.map(c => c.new_shape.id.to_string()), [
    "example#Value", "example#Value$name",
  ])
  assert_true(
    d.changed[1].new_shape.body is Member(target~) &&
    target == @smithy.ShapeId::parse("smithy.api#Integer").unwrap(),
  )
  assert_true(@diff.compare(a, b).is_breaking())
}

///|
test "entity relationship order is a set while structure member order is significant" {
  let source = "$version: \"2\"\nnamespace example\noperation A {}\noperation B {}\nservice Api { version: \"1\", operations: [A, B] }\nstructure Value { a: String, b: String }"
  let a = assemble("a.smithy", source)
  let b = assemble("b.smithy", source.replace_all(old="[A, B]", new="[B, A]"))
  assert_true(@diff.Differences::detect(a, b).changed.is_empty())
  let c = assemble(
    "c.smithy",
    source.replace_all(old="a: String, b: String", new="b: String, a: String"),
  )
  assert_true(
    @diff.compare(a, c).events
    .iter()
    .any(e => e.id == "ChangedMemberOrder" && e.severity == "DANGER"),
  )
}

///|
test "range comparison retains integers beyond Double precision" {
  let source = "$version: \"2\"\nnamespace example\n@range(min: 9007199254740992)\nlong Value"
  let a = assemble("a.smithy", source)
  let b = assemble(
    "b.smithy",
    source.replace_all(old="9007199254740992", new="9007199254740993"),
  )
  assert_true(
    @diff.compare(a, b).events
    .iter()
    .any(e => e.id == "ChangedRangeTrait" && e.severity == "ERROR"),
  )
}
