Feature: Semantic model assembly
  IDL and JSON files assemble together with the standard prelude. References,
  mixins and trait applications resolve before a model is returned.

  Scenario: Resolve references across JSON and IDL files
    Given the IDL model file "city.smithy":
      """smithy
      $version: "2"
      namespace example.weather
      use example.shared#Name
      structure City {
          name: Name
          active: Boolean
      }
      """
    And the JSON model file "name.json":
      """json
      {"smithy":"2.0","shapes":{"example.shared#Name":{"type":"string"}}}
      """
    When I assemble the semantic model
    Then the model has no errors
    And the semantic member "example.weather#City$name" targets "example.shared#Name"
    And the semantic member "example.weather#City$active" targets "smithy.api#Boolean"
    And the assembled model exports and reloads unchanged

  Scenario: Inherit members and apply traits to the inherited copy
    Given the IDL model file "mixins.smithy":
      """smithy
      $version: "2"
      namespace example.weather
      @mixin
      structure Base {
          @documentation("base")
          name: String
      }
      structure City with [Base] {
          @required
          $name
      }
      apply City$name @documentation("city")
      """
    When I assemble the semantic model
    Then the model has no errors
    And the semantic member "example.weather#City$name" targets "smithy.api#String"
    And the semantic shape "example.weather#City$name" has trait "smithy.api#required"
    And the semantic shape "example.weather#City$name" has documentation "city"
    And the semantic shape "example.weather#Base$name" has documentation "base"

  Scenario: Merge metadata and array traits across files
    Given the IDL model file "a.smithy":
      """smithy
      $version: "2"
      metadata files = ["a"]
      namespace example.weather
      @tags(["first"])
      string Name
      """
    And the IDL model file "b.smithy":
      """smithy
      $version: "2"
      metadata files = ["b"]
      namespace example.weather
      apply Name @tags(["second"])
      """
    When I assemble the semantic model
    Then the model has no errors
    And the metadata "files" contains strings "a, b"
    And the semantic shape "example.weather#Name" has tags "first, second"

  Scenario: Resolve inline inputs and resource-bound identifiers
    Given the IDL model file "resource.smithy":
      """smithy
      $version: "2"
      $operationInputSuffix: "Request"
      namespace example.weather
      resource City {
          identifiers: { id: String }
          read: GetCity
      }
      operation GetCity {
          input := for City { $id }
      }
      """
    When I assemble the semantic model
    Then the model has no errors
    And the semantic member "example.weather#GetCityRequest$id" targets "smithy.api#String"
    And the semantic shape "example.weather#GetCityRequest" has trait "smithy.api#input"

  Scenario: An unresolved reference prevents a partial model
    Given the IDL model file "broken.smithy":
      """smithy
      $version: "2"
      namespace example.weather
      structure City { name: Missing }
      """
    When I assemble the semantic model
    Then the model diagnostics include "SM-MODEL-004"
    And no semantic model is returned
    And the model errors name source "broken.smithy"

  Scenario: Mixin cycles produce diagnostics
    Given the IDL model file "cycle.smithy":
      """smithy
      $version: "2"
      namespace example.weather
      @mixin
      structure A with [B] {}
      @mixin
      structure B with [A] {}
      """
    When I assemble the semantic model
    Then the model diagnostics include "SM-MODEL-009"
    And no semantic model is returned

  Scenario: Conflicting exact metadata numbers are errors
    Given the JSON model file "a.json":
      """json
      {"smithy":"2","metadata":{"number":9007199254740992}}
      """
    And the JSON model file "b.json":
      """json
      {"smithy":"2","metadata":{"number":9007199254740993}}
      """
    When I assemble the semantic model
    Then the model diagnostics include "SM-MODEL-006"
    And no semantic model is returned

  Scenario: Convert mixed IDL and JSON inputs back to IDL without changing the model
    Given the IDL model file "example.smithy":
      """smithy
      $version: "2"
      metadata numbers = [9007199254740993]
      namespace example
      @mixin
      structure Base { @required name: String }
      structure Request with [Base] { result: other#Result }
      """
    And the JSON model file "other.json":
      """json
      {"smithy":"2","shapes":{"other#Result":{"type":"structure","members":{"value":{"target":"smithy.api#String"}}}}}
      """
    When I assemble the semantic model
    Then the model has no errors
    And converting the model to IDL and back preserves the JSON AST
    And IDL conversion emits 2 namespace files

  Scenario: Load contract conditions and preserve them across model conversion
    Given the IDL model file "contracts.smithy":
      """smithy
      $version: "2"
      namespace example.logs
      use smithy.contracts#conditions
      @conditions({
          StartBeforeEnd: {
              expression: "start < end"
              documentation: "The start time must be **strictly less** than the end time."
          }
      })
      structure FetchLogsInput {
          @required
          start: Timestamp
          @required
          end: Timestamp
      }
      """
    And the JSON model file "name.json":
      """json
      {"smithy":"2.0","shapes":{"example.logs#Name":{"type":"string","traits":{"smithy.contracts#conditions":{"NoKeywords":{"expression":"!contains(@, 'id') && !contains(@, 'name')","documentation":"No reserved keywords."}}}}}}
      """
    When I assemble the semantic model
    Then the model has no errors
    And the semantic shape "example.logs#FetchLogsInput" has trait "smithy.contracts#conditions"
    And the semantic shape "example.logs#Name" has trait "smithy.contracts#conditions"
    And the assembled model exports and reloads unchanged
    And converting the model to IDL and back preserves the JSON AST
    And IDL conversion emits 1 namespace files

  Scenario Outline: Reject conditions on service shape kinds
    Given the IDL model file "target.smithy":
      """smithy
      $version: "2"
      namespace example
      use smithy.contracts#conditions
      @conditions
      <declaration>
      """
    When I assemble the semantic model
    Then the model diagnostics include "SM-MODEL-011"
    And no semantic model is returned
    And the model errors name source "target.smithy"

    Examples:
      | declaration                  |
      | service S { version: "1" }   |
      | operation S {}               |
      | resource S {}                |

  Scenario Outline: Reject malformed condition definitions
    Given the IDL model file "condition.smithy":
      """smithy
      $version: "2"
      namespace example
      use smithy.contracts#conditions
      @conditions({<name>: <value>})
      string S
      """
    When I assemble the semantic model
    Then the model diagnostics include "SM-MODEL-011"
    And no semantic model is returned
    And the model errors name source "condition.smithy"

    Examples:
      | name        | value                                         |
      | Check       | {}                                            |
      | Check       | {expression: "@"}                             |
      | Check       | {documentation: "description"}                |
      | Check       | {expression: 1, documentation: "description"} |
      | Check       | {expression: "@", documentation: false}       |
      | "lowercase" | {expression: "@", documentation: "ok"}        |
      | "Has-dash"  | {expression: "@", documentation: "ok"}        |

  Scenario Outline: Reject invalid JMESPath contract expressions during assembly
    Given the IDL model file "analysis.smithy":
      """smithy
      $version: "2"
      namespace example
      use smithy.contracts#conditions
      @conditions(Check: {expression: "<expression>", documentation: "A contract."})
      structure Request { name: String, count: Integer }
      """
    When I assemble the semantic model
    Then the model diagnostics include "<code>"
    And no semantic model is returned
    And the model errors name source "analysis.smithy"

    Examples:
      | expression                      | code         |
      | name[                          | SM-MODEL-015 |
      | missing == `null`              | SM-MODEL-016 |
      | length(count) > `0`            | SM-MODEL-016 |
      | starts_with(name)              | SM-MODEL-016 |
      | unknown(name) == `true`        | SM-MODEL-016 |
      | name                          | SM-MODEL-017 |

  Scenario: Analyze contracts without enforcing their truth during conversion
    Given the IDL model file "false.smithy":
      """smithy
      $version: "2"
      namespace example
      use smithy.contracts#conditions
      @conditions(Never: {expression: "`false`", documentation: "A runtime condition."})
      boolean Flag
      structure Request { flag: Flag = true }
      """
    When I assemble the semantic model
    Then the model has no errors
    And the assembled model exports and reloads unchanged
    And converting the model to IDL and back preserves the JSON AST
