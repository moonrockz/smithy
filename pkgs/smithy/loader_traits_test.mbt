///|
test "omitted values and empty parentheses use the trait's declared shape" {
  let model = loaded(
    @smithy.Loader::new().add_idl(
      "traits.smithy",
      (
        #|$version: "2"
        #|namespace example.traits
        #|@trait
        #|document arbitrary
        #|@tags
        #|@arbitrary
        #|string A
        #|@tags()
        #|@arbitrary()
        #|string B
        #|@arbitrary({})
        #|string C
      ),
    ),
  )
  for name in ["A", "B"] {
    assert_eq(
      model
      .get("example.traits#" + name)
      .unwrap()
      .trait_value("smithy.api#tags"),
      Some(Array([])),
    )
    assert_eq(
      model
      .get("example.traits#" + name)
      .unwrap()
      .trait_value("example.traits#arbitrary"),
      Some(Null),
    )
  }
  assert_eq(
    model
    .get("example.traits#C")
    .unwrap()
    .trait_value("example.traits#arbitrary"),
    Some(Object(Map([]))),
  )
  let result = @smithy.Loader::new()
    .add_idl(
      "boolean.smithy",
      (
        #|$version: "2"
        #|namespace example.traits
        #|@trait
        #|boolean flag
        #|@flag()
        #|string A
      ),
    )
    .assemble()
  assert_true(result.diagnostics.iter().any(d => d.code == "SM-MODEL-011"))
}

///|
test "private shapes and traits cannot be referenced across namespaces" {
  let result = @smithy.Loader::new()
    .add_idl(
      "private.smithy",
      (
        #|$version: "2"
        #|namespace example.private
        #|@private
        #|string Secret
        #|@private
        #|@trait
        #|structure secretTrait {}
      ),
    )
    .add_idl(
      "external.smithy",
      (
        #|$version: "2"
        #|namespace example.public
        #|@example.private#secretTrait
        #|structure S { value: example.private#Secret }
      ),
    )
    .assemble()
  assert_eq(result.model, None)
  assert_true(result.diagnostics.iter().any(d => d.code == "SM-MODEL-005"))
  assert_true(result.diagnostics.iter().any(d => d.code == "SM-MODEL-011"))
}
