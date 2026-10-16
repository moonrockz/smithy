Feature: Diagnostics
  Every problem is reported with a code, a title, a message under the span,
  context labels, notes in the first person and a hint, and rendered in the
  Rust and codespan layout.

  Scenario: A missing colon in a member names the member and the construct
    Given the Smithy model "model.smithy":
      """smithy
      $version: "2"
      namespace com.foo

      structure S {
          a String
      }
      """
    When I parse the model
    Then the diagnostics are "SM-PARSE-001"
    And the first diagnostic renders as:
      """
      error[SM-PARSE-001]: UNEXPECTED TOKEN
       --> model.smithy:5:7
        |
      4 | structure S {
        | --------- the structure `S` started here
      5 |     a String
        |       ^^^^^^ I was expecting `:` after the member name `a` but found `String`
        |
        = I was parsing the structure `S` when I got stuck.
        = example:
            a: String

      """
    And the short form is "model.smithy:5:7: error[SM-PARSE-001]: I was expecting `:` after the member name `a` but found `String`"

  Scenario: Two statements on one line
    Given the Smithy model "m.smithy":
      """smithy
      namespace a use b#C
      """
    When I parse the model
    Then the diagnostics are "SM-PARSE-003"
    And the first title is "MISSING LINE BREAK"
    And the first hint is "Put `use` on its own line."

  Scenario: A detached doc comment is a warning, not an error
    Given the Smithy model "m.smithy":
      """smithy
      namespace a

      string S
      /// nothing follows
      """
    When I parse the model
    Then the diagnostics are "SM-PARSE-009"
    And there are no errors
