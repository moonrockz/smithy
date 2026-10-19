///|
test "selector traverses members and their targets" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|structure Person { name: String }
  let result = @smithy.Loader::new().add_idl("person.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let selector = @smithy.Selector::parse(
    "structure[id|namespace=example] > member > string",
  )
  assert_eq(selector.select_ids(model), ["smithy.api#String"])
}

///|
test "unknown selector functions parse successfully" {
  let selector = @smithy.Selector::parse(":futureFunction(structure)")
  assert_eq(selector.source, ":futureFunction(structure)")
}

///|
test "unknown shape types and malformed functions fail parsing" {
  assert_true(
    try @smithy.Selector::parse("futureShape") catch {
      @smithy.InvalidSelector(_) => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try @smithy.Selector::parse(":not(string, list)") catch {
      @smithy.InvalidSelector(_) => true
    } noraise {
      _ => false
    },
  )
}

///|
test "selector matches trait and identifier attributes" {
  let source =
    #|$version: "2.0"
    #|namespace example
    #|@documentation("A person")
    #|structure Person {}
    #|structure Other {}
  let result = @smithy.Loader::new().add_idl("person.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  let selector = @smithy.Selector::parse(
    "structure[trait|documentation][id|name=Person]",
  )
  assert_eq(selector.select_ids(model), ["example#Person"])
}
