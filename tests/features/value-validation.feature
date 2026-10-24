Feature: Direct application value validation
  Validate JSON against Smithy data shapes through the reusable value engine.

  Scenario: Leap seconds use the UTC insertion date through numeric offsets
    Given a prepared date-time member validator
    When I validate the JSON value "{\"at\":\"2017-01-01T05:29:60.5+05:30\"}"
    Then the value is valid
    When I validate the JSON value "{\"at\":\"2017-01-01T05:29:60.5-05:30\"}"
    Then the value finding is "InvalidTimestamp" at "/at" on "example#Input$at"

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

  Scenario: A nested alternation pattern validates within the default work limit
    Given a value model whose input has the pattern "^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*:([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*#([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*$"
    When I prepare the value validator
    And I validate the JSON value "\"morphir/SDK:basics#int\""
    Then the value is valid

  Scenario: A long FQName validates within the default work limit
    Given a value model whose input has the pattern "^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*:([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*#([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*$"
    When I prepare the value validator
    And I validate the JSON value "\"my-org/finance-and-risk/regulatory-reporting:liquidity/coverage-ratio#calculate-net-cash-outflows\""
    Then the value is valid

  Scenario: A literal dash may end a character class
    Given a value model whose input has the pattern "^[A-Za-z0-9/-]+:[A-Za-z0-9/-]+#[A-Za-z0-9-]+$"
    When I prepare the value validator
    And I validate the JSON value "\"morphir/SDK:basics#int\""
    Then the value is valid

  Scenario: Duplicate names cannot hide an invalid input
    Given a prepared count value validator
    When I validate the JSON value "{\"count\":0,\"count\":2}"
    Then the JSON value has duplicate names
