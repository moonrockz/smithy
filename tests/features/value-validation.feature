Feature: Direct application value validation
  Validate JSON against Smithy data shapes through the reusable value engine.

  Scenario: A value satisfies the modeled contract
    Given a prepared count value validator
    When I validate the JSON value "{\"count\":2}"
    Then the value is valid

  Scenario: A violation identifies its exact member
    Given a prepared count value validator
    When I validate the JSON value "{\"count\":0}"
    Then the value finding is "Range" at "/count" on "example#Input$count"

  Scenario: Required and null are different from a valid value
    Given a prepared count value validator
    When I validate the JSON value "{}"
    Then the value finding is "RequiredMember" at "/count" on "example#Input$count"
    When I validate the JSON value "{\"count\":null}"
    Then the value finding is "TypeMismatch" at "/count" on "example#Input$count"

  Scenario: Prepared validation does not retain prior findings
    Given a prepared count value validator
    When I validate the JSON value "{\"count\":0}"
    Then the value finding is "Range" at "/count" on "example#Input$count"
    When I validate the JSON value "{\"count\":2}"
    Then the value is valid

  Scenario: Unsupported constraints cannot silently pass
    Given a value model with an unsupported pattern
    When I prepare the value validator
    Then value preparation reports an unsupported constraint

  Scenario: Duplicate names cannot hide an invalid input
    Given a prepared count value validator
    When I validate the JSON value "{\"count\":0,\"count\":2}"
    Then the JSON value has duplicate names
