Feature: One version across the workspace
  All modules share one version. The check lists each place that has another version. The set command
  changes the version of each module, the imports between modules and the version strings in the sources.

  Scenario: Read the version
    Given the text:
      """
      name = "moonrockz/smithy"

      version = "0.1.0"
      """
    Then the module version is "0.1.0"

  Scenario: A file with no version line has no version
    Given the text:
      """
      name = "moonrockz/smithy"
      """
    Then there is no module version

  Scenario: Set the version keeps everything else
    Given the text:
      """
      # A comment

      name = "moonrockz/smithy"

      version = "0.1.0"

      description = "Smithy"
      """
    When I set the module version to "0.0.1"
    Then the result is:
      """
      # A comment

      name = "moonrockz/smithy"

      version = "0.0.1"

      description = "Smithy"
      """

  Scenario: Only sibling imports change
    Given the text:
      """
      import {
        "moonrockz/smithy-syntax@0.1.0",
        "moonrockz/expect@0.6.1",
        "moonrockz/moonspec@0.11.0",
      }
      """
    When I set the imports of "moonrockz/smithy-syntax,moonrockz/smithy" to "0.0.1"
    Then the result is:
      """
      import {
        "moonrockz/smithy-syntax@0.0.1",
        "moonrockz/expect@0.6.1",
        "moonrockz/moonspec@0.11.0",
      }
      """

  Scenario: A lib file version
    Given the text:
      """
      pub fn version() -> String {
        "0.1.0"
      }
      """
    When I replace the quoted "0.1.0" with "0.0.1"
    Then the result is:
      """
      pub fn version() -> String {
        "0.0.1"
      }
      """

  Scenario: Mismatches are listed
    Given a file "pkgs/smithy/moon.mod" with the text:
      """
      name = "moonrockz/smithy"

      version = "0.1.0"
      """
    When I look for versions other than "0.0.1"
    Then the mismatches are "pkgs/smithy/moon.mod: found 0.1.0, expected 0.0.1"

  Scenario: A sibling import and a third-party import in a module
    Given a file "a/moon.mod" with the text:
      """
      name = "moonrockz/a"

      version = "0.0.1"
      """
    And a file "b/moon.mod" with the text:
      """
      name = "moonrockz/b"

      version = "0.0.1"

      import {
        "moonrockz/a@0.1.0",
        "moonrockz/expect@0.6.1",
      }
      """
    When I look for versions other than "0.0.1"
    Then the mismatches are "b/moon.mod: found 0.1.0, expected 0.0.1"

  Scenario: A version string in a source file
    Given a file "pkgs/smithy/smithy_test.mbt" with the text:
      """
      inspect(@smithy.version(), content="0.1.0")
      """
    When I look for versions other than "0.0.1"
    Then the mismatches are "pkgs/smithy/smithy_test.mbt: found 0.1.0, expected 0.0.1"

  Scenario: An unrelated version-like string in a version file is left alone
    Given a file "pkgs/smithy-syntax/src/lib.mbt" with the text:
      """
      pub let spec : String = "1.0.0"

      pub fn version() -> String {
        "0.1.0"
      }
      """
    When I look for versions other than "0.1.0"
    Then the mismatches are ""
    When I look for versions other than "0.0.1"
    Then the mismatches are "pkgs/smithy-syntax/src/lib.mbt: found 0.1.0, expected 0.0.1"

  Scenario: Set changes only the version of a version file
    Given a file "pkgs/smithy-syntax/src/lib_test.mbt" with the text:
      """
      inspect("1.0.0", content="1.0.0")
      inspect(@syntax.version(), content="0.1.0")
      """
    When I set the versions of the files to "0.0.1"
    Then the result is:
      """
      inspect("1.0.0", content="1.0.0")
      inspect(@syntax.version(), content="0.0.1")
      """
