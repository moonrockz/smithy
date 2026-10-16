Feature: Recovery per statement
  An error inside a statement is reported once; the parser resumes at the
  next statement and the CST keeps every token.

  Scenario: A broken shape does not take the next one with it
    Given the Smithy model:
      """smithy
      $version: "2"
      namespace com.foo

      structure Bad {
          a String
      }

      string Foo
      """
    When I parse the model
    Then the diagnostics are "SM-PARSE-001"
    And the shapes are "Bad, Foo"
    And the CST prints the model back unchanged

  Scenario: An unclosed brace resumes at the next statement start
    Given the Smithy model:
      """smithy
      $version: "2"
      namespace com.foo

      structure Bad {
          a: String

      @deprecated
      string Bar
      """
    When I parse the model
    Then there is 1 error
    And the shapes include "Bar"
    And the CST has 1 skipped statement
    And the CST prints the model back unchanged
