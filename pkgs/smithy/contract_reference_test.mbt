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
fn contract_keys(
  text : String,
  protocol_tests~ : Bool = false,
) -> Array[String] {
  let result = @smithy.Loader::new(protocol_tests~)
    .add_idl("model.smithy", text)
    .assemble()
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

///|
test "values in the model must match the contract conditions, as in Smithy" {
  let size_trait = "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n@trait\n@conditions({\n    MinNotAboveMax: {\n        expression: \"min <= max\"\n        documentation: \"min must not be more than max.\"\n    }\n})\nstructure size {\n    @required\n    min: Integer\n    @required\n    max: Integer\n}\n"
  assert_eq(
    contract_keys(size_trait + "@size(min: 1, max: 2)\nstring Name\n"),
    [],
  )
  assert_eq(
    contract_keys(size_trait + "@size(min: 10, max: 2)\nstring Name\n"),
    ["TraitValue.MinNotAboveMax|ERROR|example#Name"],
  )
  let city_id = "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n@conditions({\n    NoSpaces: {\n        expression: \"!contains(@, ' ')\"\n        documentation: \"A city ID has no spaces.\"\n    }\n})\nstring CityId\n"
  assert_eq(
    contract_keys(
      city_id + "structure Search {\n    cityId: CityId = \"new-york\"\n}\n",
    ),
    [],
  )
  assert_eq(
    contract_keys(
      city_id + "structure Search {\n    cityId: CityId = \"new york\"\n}\n",
    ),
    ["DefaultTrait.NoSpaces|ERROR|example#Search$cityId"],
  )
}

///|
/// The events of `text` that come from a contract condition on a value.
fn condition_events(text : String) -> Array[String] {
  let result = @smithy.Loader::new().add_idl("model.smithy", text).assemble()
  let events = result
    .validation_events()
    .filter(e => {
      e.id.has_prefix("TraitValue.") ||
      e.id.has_prefix("DefaultTrait.") ||
      e.id.has_prefix("ExamplesTrait.")
    })
    .map(e => {
      e.id +
      "|" +
      e.severity +
      "|" +
      e.shape.map(s => s.to_string()).unwrap_or("-") +
      "|" +
      e.message
    })
  events.sort_by(code_unit_order)
  events
}

///|
test "each shape that a value visits checks its own conditions, as in Smithy" {
  let header = "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n"
  // A member and its target both have conditions.
  assert_eq(
    condition_events(
      header +
      "@conditions({T: {expression: \"@ > `5`\", documentation: \"x\"}})\ninteger N\nstructure S {\n    @conditions({M: {expression: \"@ > `3`\", documentation: \"x\"}})\n    n: N = 1\n}\n",
    ),
    [
      "DefaultTrait.M|ERROR|example#S$n|Error validating value: Value provided for `example#S$n` must match the M condition expression",
      "DefaultTrait.T|ERROR|example#S$n|Error validating value: Value provided for `example#N` must match the T condition expression",
    ],
  )
  // A list and its member, inside a trait value.
  assert_eq(
    condition_events(
      header +
      "@trait\nstructure t {\n    items: Items\n}\n@conditions({Short: {expression: \"length(@) < `2`\", documentation: \"x\"}})\nlist Items {\n    @conditions({NoX: {expression: \"@ != 'x'\", documentation: \"x\"}})\n    member: String\n}\n@t(items: [\"a\", \"x\", \"b\"])\nstring X\n",
    ),
    [
      "TraitValue.NoX|ERROR|example#X|Error validating value/items/1: Value provided for `example#Items$member` must match the NoX condition expression",
      "TraitValue.Short|ERROR|example#X|Error validating value/items: Value provided for `example#Items` must match the Short condition expression",
    ],
  )
  // Map keys, map values, and two conditions on one shape.
  assert_eq(
    condition_events(
      header +
      "@trait\nmap t {\n    key: K\n    value: V\n}\n@conditions({KeyShort: {expression: \"length(@) < `3`\", documentation: \"x\"}})\nstring K\n@conditions({Pos: {expression: \"@ > `0`\", documentation: \"x\"}, Small: {expression: \"@ < `5`\", documentation: \"x\"}})\ninteger V\n@t(abcd: 9, ab: -1)\nstring X\n",
    ).map(e => e.split("|").take(3).map(s => s.to_owned()).join("|")),
    [
      "TraitValue.KeyShort|ERROR|example#X", "TraitValue.Pos|ERROR|example#X", "TraitValue.Small|ERROR|example#X",
    ],
  )
  // An enum, a timestamp, and a union value with two members.
  assert_eq(
    condition_events(
      header +
      "@conditions({Never: {expression: \"`false`\", documentation: \"x\"}})\nenum E {\n    A\n}\n@conditions({Never: {expression: \"`false`\", documentation: \"x\"}})\ntimestamp T\n@conditions({Never: {expression: \"`false`\", documentation: \"x\"}})\nunion U {\n    a: String\n    b: String\n}\nstructure S {\n    e: E = \"A\"\n    t: T = 0\n}\n@trait\nstructure tr { u: U }\n@tr(u: {a: \"x\", b: \"y\"})\nstring X\n",
    ).map(e => e.split("|").take(3).map(s => s.to_owned()).join("|")),
    [
      "DefaultTrait.Never|ERROR|example#S$e", "DefaultTrait.Never|ERROR|example#S$t",
      "TraitValue.Never|ERROR|example#X",
    ],
  )
}

///|
test "a value that does not reach a shape skips its conditions, as in Smithy" {
  let header = "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n@conditions({Never: {expression: \"`false`\", documentation: \"x\"}})\n"
  // Document values are always valid.
  assert_eq(
    condition_events(
      header + "document D\nstructure S {\n    d: D = \"x\"\n}\n",
    ),
    [],
  )
  // A value of the wrong type gives only the type event.
  assert_eq(
    condition_events(header + "integer N\nstructure S {\n    n: N = \"a\"\n}\n"),
    [],
  )
  // A null default is not validated.
  assert_eq(
    condition_events(
      header +
      "integer N\nstructure S {\n    @conditions({M: {expression: \"`false`\", documentation: \"x\"}})\n    n: N = null\n}\n",
    ),
    [],
  )
}

///|
test "an example value that fails a condition has the examples event ID" {
  let model = "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n@conditions({Small: {expression: \"@ < `10`\", documentation: \"x\"}})\ninteger N\nstructure In {\n    n: N\n}\n@examples([{title: \"one\", input: {n: 20}}])\noperation Op {\n    input: In\n}\n"
  assert_eq(condition_events(model), [
    "ExamplesTrait.Small|ERROR|example#Op|Example input of `one`.n: Value provided for `example#N` must match the Small condition expression",
  ])
  // allowConstraintErrors makes the event a warning.
  let allowed = model
    .replace(
      old="input: {n: 20}}",
      new="input: {n: 20}, allowConstraintErrors: true, error: {shapeId: Err, content: {}}}",
    )
    .replace(
      old="    input: In\n}\n",
      new="    input: In\n    errors: [Err]\n}\n",
    ) +
    "@error(\"client\")\nstructure Err {}\n"
  assert_eq(condition_events(allowed), [
    "ExamplesTrait.Small|WARNING|example#Op|Example input of `one`.n: Value provided for `example#N` must match the Small condition expression",
  ])
}

///|
test "a typed metadata value that fails a condition has the metadata event ID" {
  let model = "$version: \"2\"\nmetadata limits = {min: 10, max: 2}\nnamespace example\nuse smithy.contracts#conditions\n@metadata(key: \"limits\")\n@conditions({\n    MinNotAboveMax: {\n        expression: \"min <= max\"\n        documentation: \"min must not be more than max.\"\n    }\n})\nstructure Limits {\n    @required\n    min: Integer\n    @required\n    max: Integer\n}\n"
  assert_eq(contract_keys(model), [
    "TypedMetadata.limits.MinNotAboveMax|ERROR|-",
  ])
  assert_eq(
    contract_keys(
      model.replace(old="{min: 10, max: 2}", new="{min: 1, max: 2}"),
    ),
    [],
  )
}

///|
test "protocol test parameters that fail a condition have the protocol test event ID" {
  let model = "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\nuse smithy.test#httpRequestTests\n\n@protocolDefinition\n@trait\nstructure testProtocol {}\n\n@testProtocol\nservice Svc {\n    version: \"1\"\n    operations: [Op]\n}\n\n@http(method: \"POST\", uri: \"/op\")\n@httpRequestTests([\n    {\n        id: \"OpBad\"\n        protocol: testProtocol\n        method: \"POST\"\n        uri: \"/op\"\n        params: {n: 20}\n    }\n])\noperation Op {\n    input: OpInput\n}\n\n@input\nstructure OpInput {\n    n: Small\n}\n\n@conditions({\n    Under10: {\n        expression: \"@ < `10`\"\n        documentation: \"Under ten.\"\n    }\n})\ninteger Small\n"
  assert_eq(contract_keys(model, protocol_tests=true), [
    "HttpRequestTestsInput.Under10|ERROR|example#Op",
  ])
  assert_eq(
    contract_keys(
      model.replace(old="params: {n: 20}", new="params: {n: 2}"),
      protocol_tests=true,
    ),
    [],
  )
}

///|
test "a failed condition says why when the result is not boolean or the evaluation fails" {
  // Smithy stops the validation in these cases; we fail the condition and say why.
  let header = "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n"
  let with_default = fn(expression : String) {
    header +
    "@conditions({C: {expression: " +
    Json::string(expression).stringify() +
    ", documentation: \"x\"}})\ninteger N\nstructure S {\n    n: N = 1\n}\n"
  }
  assert_eq(condition_events(with_default("@")), [
    "DefaultTrait.C|ERROR|example#S$n|Error validating value: Value provided for `example#N` must match the C condition expression, but the result is a number, not a boolean",
  ])
  assert_eq(condition_events(with_default("length(@) > `0`")), [
    "DefaultTrait.C|ERROR|example#S$n|Error validating value: Value provided for `example#N` must match the C condition expression, but I could not evaluate it: I expected string|array|object in JMESPath function length.",
  ])
  assert_eq(
    condition_events(
      header +
      "@trait\n@conditions({HasA: {expression: \"a\", documentation: \"x\"}})\nstructure t {\n    a: Boolean\n}\n@t\nstring X\n",
    ),
    [
      "TraitValue.HasA|ERROR|example#X|Error validating value: Value provided for `example#t` must match the HasA condition expression, but the result is null, not a boolean",
    ],
  )
}

///|
test "large numbers compare as in Smithy" {
  // Java compares two integers, or a number that a double cannot hold, exactly,
  // and compares with a double only when one side is a double. Keys from the
  // Smithy reference.
  let failed = ["DefaultTrait.C|ERROR|example#S$n"]
  for
    (shape, expression, default, expected) in [
      ("long", "@ > `9007199254740992`", "9007199254740993", []),
      ("long", "@ <= `9007199254740992`", "9007199254740993", failed),
      ("long", "@ == `9007199254740992`", "9007199254740993", failed),
      ("long", "@ == `9223372036854775806`", "9223372036854775807", failed),
      ("bigInteger", "@ > `9007199254740992`", "9007199254740993", []),
      ("bigInteger", "@ == `9007199254740992`", "9007199254740993", failed),
      ("bigInteger", "@ > `18446744073709551616`", "18446744073709551617", []),
      (
        "bigInteger", "@ == `18446744073709551616`", "18446744073709551617", failed,
      ),
      ("bigDecimal", "@ > `9007199254740992`", "9007199254740993", []),
      ("bigDecimal", "@ == `9007199254740992`", "9007199254740993", failed),
      (
        "bigDecimal",
        "@ > `0.10000000000000000001`",
        "0.10000000000000000002",
        [],
      ),
      (
        "bigDecimal", "@ == `0.10000000000000000001`", "0.10000000000000000002",
        failed,
      ),
      // The default is an integer token, so both sides are exact.
      ("double", "@ > `9007199254740992`", "9007199254740993", []),
      // A literal with a decimal point that a double holds is a double, so the
      // comparison rounds the integer to a double, as in Smithy.
      ("long", "@ > `9007199254740992.0`", "9007199254740993", failed),
    ] {
    let model = "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n@conditions({C: {expression: " +
      Json::string(expression).stringify() +
      ", documentation: \"x\"}})\n" +
      shape +
      " N\nstructure S {\n    n: N = " +
      default +
      "\n}\n"
    assert_eq(contract_keys(model), expected, msg=shape + " " + expression)
  }
}
