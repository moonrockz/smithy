///|
fn rows(text : String) -> Array[(String, Kind, Verdict, String)] raise Failure {
  match kit_examples("k.feature", text) {
    Ok(found) =>
      found.map(fn(e) { (e.at, e.kind, e.verdict, e.value.stringify()) })
    Err(message) => fail(message)
  }
}

///|
test "step: its canonical JSON spelling is" {
  let text =
    #|@node:Type
    #|Feature: T
    #|  Scenario: s
    #|    Then its canonical JSON spelling is "a"
    #|    And its canonical JSON spelling is {"Unit": {}}
  assert_eq(rows(text), [
    ("line 4", Type, Accepted, "\"a\""),
    ("line 5", Type, Accepted, "{\"Unit\":{}}"),
  ])
}

///|
test "step: a reader of JSON accepts, with and without a warning" {
  let text =
    #|@node:Name
    #|Feature: T
    #|  Scenario: s
    #|    Then a reader of JSON accepts ["a"]
    #|    And a reader of JSON accepts ["b"] with warning legacy_spelling
  assert_eq(rows(text), [
    ("line 4", Name, Accepted, "[\"a\"]"),
    ("line 5", Name, Legacy("legacy_spelling"), "[\"b\"]"),
  ])
}

///|
test "step: a reader of JSON rejects" {
  let text =
    #|@node:Name
    #|Feature: T
    #|  Scenario: s
    #|    Then a reader of JSON rejects "Usd" with invalid_name
  assert_eq(rows(text), [("line 4", Name, Rejected("invalid_name"), "\"Usd\"")])
}

///|
test "outline: canonical spelling keeps the JSON rows only" {
  let text =
    #|@node:Path
    #|Feature: T
    #|  Scenario Outline: s
    #|    Then its canonical <format> spelling is <spelling>
    #|
    #|    Examples:
    #|      | format | spelling      |
    #|      | YAML   | morphir/SDK   |
    #|      | JSON   | "morphir/SDK" |
  assert_eq(rows(text), [("line 9", Path, Accepted, "\"morphir/SDK\"")])
}

///|
test "outline: accepts, accepts with warning and rejects" {
  let text =
    #|@node:Name
    #|Feature: T
    #|  Scenario Outline: a
    #|    Then a reader of <format> accepts <input>
    #|    Examples:
    #|      | format | input |
    #|      | JSON   | "a"   |
    #|      | YAML   | a     |
    #|  Scenario Outline: b
    #|    Then a reader of <format> accepts <input> with warning <warning>
    #|    Examples:
    #|      | format | input | warning         |
    #|      | JSON   | ["b"] | legacy_spelling |
    #|  Scenario Outline: c
    #|    Then a reader of <format> rejects <input> with <diagnostic>
    #|    Examples:
    #|      | format | input | diagnostic   |
    #|      | JSON   | "C"   | invalid_name |
  assert_eq(rows(text), [
    ("line 7", Name, Accepted, "\"a\""),
    ("line 13", Name, Legacy("legacy_spelling"), "[\"b\"]"),
    ("line 18", Name, Rejected("invalid_name"), "\"C\""),
  ])
}

///|
test "a scenario tag overrides the tag of the feature" {
  let text =
    #|@node:Type
    #|Feature: T
    #|  @node:Name
    #|  Scenario: s
    #|    Then its canonical JSON spelling is "a"
    #|  Scenario: t
    #|    Then its canonical JSON spelling is "b"
  assert_eq(rows(text), [
    ("line 5", Name, Accepted, "\"a\""),
    ("line 7", Type, Accepted, "\"b\""),
  ])
}

///|
test "a YAML-only scenario gives nothing" {
  let text =
    #|@node:Type
    #|Feature: T
    #|  Scenario: s
    #|    Then its canonical YAML spelling is:
    #|      """
    #|      Then a reader of JSON accepts "inside a docstring"
    #|      """
    #|    And a reader of YAML reads a as b
  assert_eq(rows(text), [])
}

///|
test "a step that names JSON and fits no form is an error with its line" {
  let text =
    #|@node:Type
    #|Feature: T
    #|  Scenario: s
    #|    Then a reader of JSON frobs 1
  match kit_examples("k.feature", text) {
    Err(message) => assert_true(message.contains("k.feature:4"))
    Ok(_) => fail("I expected an error")
  }
}

///|
test "JSON that does not parse is an error with its line" {
  let text =
    #|@node:Type
    #|Feature: T
    #|  Scenario: s
    #|    Then its canonical JSON spelling is {oops
  match kit_examples("k.feature", text) {
    Err(message) => assert_true(message.contains("k.feature:4"))
    Ok(_) => fail("I expected an error")
  }
}

///|
test "a row with the wrong number of cells is an error with its line" {
  let text =
    #|@node:Type
    #|Feature: T
    #|  Scenario Outline: s
    #|    Then a reader of <format> accepts <input>
    #|    Examples:
    #|      | format | input |
    #|      | JSON   | "a" | extra |
  match kit_examples("k.feature", text) {
    Err(message) => assert_true(message.contains("k.feature:7"))
    Ok(_) => fail("I expected an error")
  }
}

///|
fn kit_error(text : String) -> String {
  match kit_examples("k.feature", text) {
    Err(message) => message
    Ok(_) => "I expected an error"
  }
}

///|
test "an unknown node tag is an error with its line" {
  let message = kit_error(
    (
      #|@node:Frob
      #|Feature: T
      #|  Scenario: s
      #|    Then its canonical JSON spelling is "a"
    ),
  )
  assert_true(message.contains("k.feature:1"))
  assert_true(message.contains("Frob"))
}

///|
test "a row without a node tag is an error with its line" {
  let message = kit_error(
    (
      #|Feature: T
      #|  Scenario Outline: s
      #|    Then a reader of <format> accepts <input>
      #|    Examples:
      #|      | format | input |
      #|      | JSON   | "a"   |
    ),
  )
  assert_true(message.contains("k.feature:6"))
  assert_true(message.contains("node tag"))
}

///|
test "a step without a node tag is an error with its line" {
  let message = kit_error(
    (
      #|Feature: T
      #|  Scenario: s
      #|    Then its canonical JSON spelling is "a"
    ),
  )
  assert_true(message.contains("k.feature:3"))
}

///|
test "a table without a format column is an error with its line" {
  let message = kit_error(
    (
      #|@node:Name
      #|Feature: T
      #|  Scenario Outline: s
      #|    Then a reader of <format> accepts <input>
      #|    Examples:
      #|      | input |
      #|      | "a"   |
    ),
  )
  assert_true(message.contains("k.feature:7"))
  assert_true(message.contains("format"))
}

///|
test "a But step or a star step is read like an And step" {
  let text =
    #|@node:Name
    #|Feature: T
    #|  Scenario: s
    #|    Then its canonical JSON spelling is "a"
    #|    But a reader of JSON rejects "B" with invalid_name
    #|    * a reader of JSON accepts ["c"]
  assert_eq(rows(text), [
    ("line 4", Name, Accepted, "\"a\""),
    ("line 5", Name, Rejected("invalid_name"), "\"B\""),
    ("line 6", Name, Accepted, "[\"c\"]"),
  ])
}

///|
test "a separator inside a JSON string does not split the step" {
  let text =
    #|@node:Name
    #|Feature: T
    #|  Scenario: s
    #|    Then a reader of JSON rejects "a with b \" with c" with invalid_name
    #|    And a reader of JSON accepts "x with warning y" with warning legacy_spelling
    #|    And a reader of JSON accepts "p with warning q"
  assert_eq(rows(text), [
    ("line 4", Name, Rejected("invalid_name"), "\"a with b \\\" with c\""),
    ("line 5", Name, Legacy("legacy_spelling"), "\"x with warning y\""),
    ("line 6", Name, Accepted, "\"p with warning q\""),
  ])
}
