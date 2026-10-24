///|
/// Order by UTF-16 code unit, as Java `String.compareTo` does. `String::compare` orders by length first.
fn code_unit_order(a : String, b : String) -> Int32 {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    if a.code_unit_at(i) != b.code_unit_at(i) {
      return a.code_unit_at(i).to_int() - b.code_unit_at(i).to_int()
    }
  }
  a.length() - b.length()
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

///|
/// The model of tour lesson 25 with an `items` member, for the slice case.
fn items_model(expression : String) -> String {
  time_range(expression).replace(
    old="    end: Timestamp\n",
    new="    end: Timestamp\n    items: Items\n",
  ) +
  "list Items {\n    member: String\n}\n"
}

///|
test "a warning has the ID of a Smithy warning" {
  // Java: Invalid comparator '<' for string, a WARNING.
  let model = "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n@conditions({Ordered: {expression: \"a < b\", documentation: \"x\"}})\nstructure S {\n    a: String\n    b: String\n}\n"
  assert_true(
    contract_keys(model).contains(
      "ConditionsTrait.JmespathProblem.JmespathEventWarning.Ordered|WARNING|example#S",
    ),
  )
}

///|
test "a zero slice step has no static event, as in Smithy" {
  assert_eq(contract_keys(items_model("length(items[::0]) == `0`")), [])
}

///|
test "the selector check reports a contract trait on the wrong shape once" {
  // The loader diagnostic SM-MODEL-011 is the only TraitTarget source of the
  // loader. It carries no event: the selector check of the trait gives it.
  for
    shape in [
      "operation Thing {}", "resource Thing {}", "service Thing {\n    version: \"1\"\n}",
    ] {
    let text = "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n@conditions({Never: {expression: \"`false`\", documentation: \"x\"}})\n@error(\"client\")\n" +
      shape +
      "\n"
    let result = @smithy.Loader::new().add_idl("model.smithy", text).assemble()
    let loader = result.diagnostics.filter(d => d.code == "SM-MODEL-011")
    assert_eq(loader.length(), 1)
    assert_eq(loader[0].report, CoveredBySelector)
    // One event for conditions and one for error, none twice.
    assert_eq(contract_keys(text), [
      "TraitTarget|ERROR|example#Thing", "TraitTarget|ERROR|example#Thing",
    ])
    let messages = result
      .validation_events()
      .filter(e => e.id == "TraitTarget")
      .map(e => e.message)
    assert_eq(
      messages.filter(m => m.contains("smithy.contracts#conditions")).length(),
      1,
    )
  }
}
