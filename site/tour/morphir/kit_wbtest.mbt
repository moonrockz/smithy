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
