Feature: Model compatibility comparison
  Compare assembled models and report reference-compatible difference events.

  Scenario: An operation output change is a breaking change
    Given the old diff model "local/toolchain.a.smithy"
    And the new diff model "local/toolchain.b.smithy"
    When I compare the models
    Then the diff contains "ChangedOperationOutput.From.example.diff#Out.To.example.diff#Out2" on "example.diff#Op" at severity "ERROR"
    And the diff is breaking

  Scenario: Preview changes are downgraded
    Given the old diff model "upstream/diffs/previewFeatures/changed-member-target.a.smithy"
    And the new diff model "upstream/diffs/previewFeatures/changed-member-target.b.smithy"
    When I compare the models
    Then the diff contains "ChangedMemberTarget" on "smithy.example#PreviewIn$data" at severity "WARNING"

  Scenario: Comparing a model with itself has no differences
    Given the old diff model "local/toolchain.a.smithy"
    And the new diff model "local/toolchain.a.smithy"
    When I compare the models
    Then the diff is empty
