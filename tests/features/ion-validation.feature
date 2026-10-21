Feature: Direct Ion value validation
  Validate native Ion values against Smithy without converting them through JSON.

  Scenario: Text and binary values satisfy the same modeled contract
    Given a prepared count Ion validator
    When I validate the Ion text "{count: 2}"
    Then the Ion value is valid
    When I validate the equivalent Ion binary
    Then the Ion value is valid

  Scenario: A native violation retains its kind and target member
    Given a prepared count Ion validator
    When I validate the Ion text "{count: 0}"
    Then the Ion finding is "Range" at "/count" on "example#Input$count" with kind "int"
    When I validate the equivalent Ion binary
    Then the Ion finding is "Range" at "/count" on "example#Input$count" with kind "int"

  Scenario: Duplicate fields retain their distinct occurrence
    Given a prepared count Ion validator
    When I validate the Ion text "{count: 1, count: 2}"
    Then the duplicate Ion field has occurrence 1

  Scenario: Annotations are not inferred Smithy types
    Given a prepared count Ion validator
    When I validate the Ion text "custom::{count: 2}"
    Then the Ion finding is "UnsupportedValue" at "" on "example#Input" with kind "struct"
