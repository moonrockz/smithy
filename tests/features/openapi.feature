Feature: OpenAPI conversion
  Convert an assembled service through its serialization protocol.

  Scenario Outline: Both supported versions preserve core service behavior
    Given the OpenAPI model "local/core-features.smithy"
    When I convert service "example.core#Example" to OpenAPI "<version>"
    Then the OpenAPI document matches "generated/<golden>.openapi.json"

    Examples:
      | version | golden           |
      | 3.0.2   | core-features    |
      | 3.1.0   | core-features-31 |

  Scenario: A missing service fails conversion
    Given the OpenAPI model "local/core-features.smithy"
    When I convert service "example.core#Missing" to OpenAPI "3.0.2"
    Then OpenAPI conversion reports a missing service
