///|
fn null_selector_model() -> @smithy.Model {
  let source =
    #|$version: "2"
    #|namespace example
    #|@trait
    #|document t
    #|@t({value: null, items: [null], object: {a: null}})
    #|string NullOnly
    #|@t({value: false, items: [null, "text"], object: {a: "text"}})
    #|string Mixed
    #|@t({value: {}, items: [], object: {}})
    #|string EmptyObject
    #|@t({value: [], items: [], object: {}})
    #|string EmptyArray
    #|@t({value: "", items: [], object: {}})
    #|string EmptyString
  @smithy.Loader::new().add_idl("null.smithy", source).assemble().model.unwrap()
}

///|
fn check_null_selector(
  expression : String,
  names : Array[String],
) -> Unit raise {
  let expected = names.map(name => "example#" + name)
  expected.sort()
  let actual = @smithy.Selector::parse("string" + expression).select_ids(
    null_selector_model(),
  )
  actual.sort()
  assert_eq(actual, expected, msg=expression + " actual=" + actual.join(","))
}

///|
test "null attributes are absent while aggregate values remain present" {
  check_null_selector("[trait|example#t|value]", [
    "Mixed", "EmptyObject", "EmptyArray", "EmptyString",
  ])
  check_null_selector("[trait|example#t|value=true]", [])
  check_null_selector("[trait|example#t|value=\"\"]", [
    "EmptyObject", "EmptyArray", "EmptyString",
  ])
  check_null_selector("[trait|example#t|value|(length)=0]", [
    "EmptyObject", "EmptyArray", "EmptyString",
  ])
}

///|
test "null projections preserve presence and exclude null comparisons" {
  check_null_selector("[trait|example#t|items|(values)]", ["NullOnly", "Mixed"])
  check_null_selector("[trait|example#t|items|(values)=null]", [])
  check_null_selector("[trait|example#t|items|(values)=\"\"]", [])
  check_null_selector("[trait|example#t|items|(values)=text]", ["Mixed"])
  check_null_selector("[trait|example#t|object|(values)|(length)=4]", ["Mixed"])
}

///|
test "scoped null values follow direct and projected presence rules" {
  check_null_selector("[@trait|example#t: @{value} ?= false]", ["NullOnly"])
  check_null_selector("[@trait|example#t|value: @{missing} ?= false]", [
    "Mixed", "EmptyObject", "EmptyArray", "EmptyString",
  ])
  check_null_selector(
    "[@trait|example#t|items|(values): @{missing} ?= false]",
    ["NullOnly", "Mixed"],
  )
  check_null_selector(
    "[@trait|example#t: @{items|(values)} {=} @{items|(values)}]",
    ["EmptyObject", "EmptyArray", "EmptyString"],
  )
}
