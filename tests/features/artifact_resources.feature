Feature: Reusable local artifact resources
  Smithy manifest discovery consumes directory and JAR entry trees supplied by
  the independent resource library. Providers can supply those trees without
  changes to Smithy parsing.

  Scenario Outline: Assemble the same declared model from each container
    Given the declared artifact model:
      """smithy
      $version: "2"
      namespace example.resources
      string Message
      """
    When I discover Smithy resources from a "<container>" container
    Then the artifact model contains "example.resources#Message"
    And the artifact model excludes "example.resources#Unlisted"
    And the artifact model source is "<source>"
    And the resource logical name is "nested/message.smithy"

    Examples:
      | container | source                                                |
      | directory | fixture-directory/META-INF/smithy/nested/message.smithy |
      | jar       | fixture.jar!/META-INF/smithy/nested/message.smithy      |
      | provider  | fixture.jar!/META-INF/smithy/nested/message.smithy      |

  Scenario: Keep the provider chain distinct from physical source names
    Given the declared artifact model:
      """smithy
      $version: "2"
      namespace example.resources
      string Message
      """
    When I discover Smithy resources from a "provider" container
    Then the resource provenance includes "fixtures[models@1] -> models@1 -> fixture.jar!/META-INF/smithy/nested/message.smithy"

  Scenario Outline: Select models from an ordinary source tree without a manifest
    Given the declared artifact model:
      """smithy
      $version: "2"
      namespace example.resources
      string Message
      """
    When I explicitly select resources from a "<container>" source tree
    Then the artifact model contains "example.resources#Message"
    And the artifact model excludes "example.resources#Unlisted"
    And the artifact model source is "<source>"
    And the resource logical name is "nested/message.smithy"

    Examples:
      | container | source                                                  |
      | directory | fixture-directory/module/models/nested/message.smithy   |
      | zip       | fixture.zip!/module/models/nested/message.smithy          |

  Scenario: Load models beneath the npm wrapper without installing the package
    When I load the local npm model package without installation
    Then the artifact model contains "example.resources#Message"
    And the artifact model contains "example.resources#SharedName"
    And the artifact model excludes "example.resources#ProjectionOnly"

  Scenario: Resolve a pinned public GitHub asset and assemble it offline
    Given the declared artifact model:
      """smithy
      $version: "2"
      namespace example.resources
      string Message
      """
    When I explicitly select resources from a "github" source tree
    Then the artifact model contains "example.resources#Message"
    And the artifact model excludes "example.resources#Unlisted"
    And the artifact model source is "https://cdn.fixture.test/models.zip!/module/models/nested/message.smithy"
    And the resource logical name is "nested/message.smithy"

  Scenario: Resolve an exact scoped npm version and assemble it offline
    When I resolve the pinned npm model package offline
    Then the artifact model contains "example.resources#Message"
    And the artifact model contains "example.resources#SharedName"
    And the artifact model excludes "example.resources#ProjectionOnly"

  Scenario Outline: Resolve a pinned Maven JAR and preserve manifest discovery offline
    Given the declared artifact model:
      """smithy
      $version: "2"
      namespace example.resources
      string Message
      """
    When I resolve the "<access>" Maven JAR offline
    Then the artifact model contains "example.resources#Message"
    And the artifact model excludes "example.resources#Unlisted"
    And the resource logical name is "nested/message.smithy"

    Examples:
      | access        |
      | public        |
      | authenticated |
