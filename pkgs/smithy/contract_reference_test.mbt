///|
/// Order by code unit, as the Java reference does. `String::compare` orders by length first.
fn code_unit_order(a : String, b : String) -> Int32 {
  let x = a.to_array()
  let y = b.to_array()
  for i in 0..<(if x.length() < y.length() { x.length() } else { y.length() }) {
    if x[i] != y[i] {
      return x[i].to_int() - y[i].to_int()
    }
  }
  x.length() - y.length()
}

///|
/// Sorted keys `id|SEVERITY|shape` of the WARNING, DANGER and ERROR events of `text`.
fn contract_keys(text : String) -> Array[String] {
  let result = @smithy.Loader::new().add_idl("model.smithy", text).assemble()
  let keys = result
    .validation_events()
    .filter(e => {
      e.severity == "WARNING" || e.severity == "DANGER" || e.severity == "ERROR"
    })
    .map(e => {
      e.id +
      "|" +
      e.severity +
      "|" +
      e.shape.map(s => s.to_string()).unwrap_or("-")
    })
  keys.sort_by(code_unit_order)
  keys
}

///|
/// The model of tour lesson 25 with `expression` as the condition StartBeforeEnd.
fn time_range(expression : String) -> String {
  "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n@conditions({\n    StartBeforeEnd: {\n        expression: " +
  Json::string(expression).stringify() +
  "\n        documentation: \"The start time must be before the end time.\"\n    }\n})\nstructure TimeRange {\n    @required\n    start: Timestamp\n    @required\n    end: Timestamp\n}\n"
}

///|
let invalid_expressions : String =
  #|$version: "2"
  #|
  #|namespace smithy.example
  #|
  #|use smithy.contracts#conditions
  #|
  #|@conditions({
  #|    Good: {
  #|        documentation: "Good"
  #|        expression: "length(string) < length(string2)"
  #|    }
  #|    WrongType: {
  #|        documentation: "WrongType"
  #|        expression: "string"
  #|    }
  #|    WrongType2: {
  #|        documentation: "WrongType2"
  #|        expression: "int"
  #|    }
  #|    MissingField: {
  #|        documentation: "MissingField"
  #|        expression: "foo"
  #|    }
  #|})
  #|structure BadConditions {
  #|    string: String
  #|    string2: String
  #|    int: Integer
  #|}

///|
let invalid_jmespath_syntax : String =
  #|$version: "2"
  #|
  #|namespace smithy.example
  #|
  #|use smithy.contracts#conditions
  #|
  #|@conditions({
  #|    BadSyntax: {
  #|        documentation: "I have no idea what this would mean"
  #|        expression: "||"
  #|    }
  #|})
  #|structure FooBar {
  #|    int: Integer
  #|}

///|
test "contract findings have the event IDs and severities of Smithy" {
  assert_eq(contract_keys(time_range("start < end")), [])
  assert_eq(contract_keys(time_range("start")), [
    "ConditionsTrait|DANGER|example#TimeRange",
  ])
  assert_eq(contract_keys(time_range("start <")), [
    "Model|ERROR|example#TimeRange",
  ])
  assert_eq(contract_keys(time_range("length(start) > `0`")), [
    "ConditionsTrait|ERROR|example#TimeRange",
  ])
  assert_eq(contract_keys(time_range("foo(start)")), [
    "ConditionsTrait|DANGER|example#TimeRange", "ConditionsTrait|ERROR|example#TimeRange",
  ])
  assert_eq(contract_keys(time_range("abs(start, end)")), [
    "ConditionsTrait|DANGER|example#TimeRange", "ConditionsTrait|ERROR|example#TimeRange",
  ])
  assert_eq(
    contract_keys(
      time_range("start < end").replace(
        old="StartBeforeEnd:",
        new="startBeforeEnd:",
      ),
    ),
    ["TraitValue|ERROR|example#TimeRange"],
  )
  assert_eq(
    contract_keys(
      "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n@conditions({Never: {expression: \"`false`\", documentation: \"x\"}})\noperation Ping {}\n",
    ),
    ["TraitTarget|ERROR|example#Ping"],
  )
}

///|
test "the Java errorfiles of the contract traits" {
  // invalid-expressions.smithy and invalid-jmespath-syntax.smithy of
  // smithy-contract-traits/src/test/resources/software/amazon/smithy/contracts/errorfiles.
  assert_eq(contract_keys(invalid_expressions), [
    "ConditionsTrait.JmespathProblem.JmespathEventDanger.MissingField|DANGER|smithy.example#BadConditions",
    "ConditionsTrait|DANGER|smithy.example#BadConditions", "ConditionsTrait|DANGER|smithy.example#BadConditions",
    "ConditionsTrait|DANGER|smithy.example#BadConditions",
  ])
  assert_eq(contract_keys(invalid_jmespath_syntax), [
    "Model|ERROR|smithy.example#FooBar",
  ])
}
