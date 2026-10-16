Feature: Smithy JSON AST
  JSON documents decode into typed records and encode without losing fields
  or numeric precision. The semantic loader resolves and validates models.

  Scenario Outline: Decode each shape family
    Given the JSON AST document:
      """json
      {"smithy":"2.0","shapes":{"example.test#Value":{"type":"<type>"}}}
      """
    When I decode the JSON AST
    Then the JSON shape "example.test#Value" has type "<type>"
    And the JSON AST round trips

    Examples:
      | type       |
      | blob       |
      | boolean    |
      | document   |
      | string     |
      | byte       |
      | short      |
      | integer    |
      | long       |
      | float      |
      | double     |
      | bigInteger |
      | bigDecimal |
      | timestamp  |
      | list       |
      | set        |
      | map        |
      | structure  |
      | union      |
      | enum       |
      | intEnum    |
      | operation  |
      | service    |
      | resource   |
      | apply      |

  Scenario: Preserve mixins and separate trait applications
    Given the JSON AST document:
      """json
      {
        "smithy": "2.0",
        "metadata": {},
        "shapes": {
          "example.test#Derived": {"type":"list","mixins":[{"target":"example.test#Base"}]},
          "example.test#Derived$member": {"type":"apply","traits":{"smithy.api#documentation":"Name"}}
        }
      }
      """
    When I decode the JSON AST
    Then the JSON AST round trips

  Scenario: Preserve decimal and integer precision
    Given the JSON AST document:
      """json
      {"smithy":"2","metadata":{"integer":9007199254740993,"decimal":0.12345678901234567890123456789}}
      """
    When I decode the JSON AST
    Then the encoded JSON AST contains "9007199254740993"
    And the encoded JSON AST contains "0.12345678901234567890123456789"

  Scenario Outline: Explain malformed fields with JSON Pointer paths
    Given the JSON AST document:
      """json
      <json>
      """
    When I decode the JSON AST
    Then the JSON AST error path is "<path>"

    Examples:
      | json                                                                                              | path                             |
      | {}                                                                                                | /smithy                          |
      | {"smithy":"2","metadata":null}                                                                    | /metadata                        |
      | {"smithy":"2","shapes":{"example.test#S":{"type":"unknown"}}}                                       | /shapes/example.test#S/type       |
      | {"smithy":"2","shapes":{"example.test#S":{"type":"apply","mixins":[]}}}                             | /shapes/example.test#S/mixins     |
      | {"smithy":"2","shapes":{"example.test#S":{"type":"list","member":{"target":"String"}}}}               | /shapes/example.test#S/member/target |
      | {"smithy":"2","shapes":{"example.test#S":{"type":"string","extra":true}}}                            | /shapes/example.test#S/extra      |

  Scenario: The vendored reference corpus is compatible
    Given the vendored JSON AST reference corpus
    When I round trip every JSON AST reference case
    Then every JSON AST reference case preserves its fields
